//
//  AppState.swift
//  X-Reader
//
//  Global app state management
//


import SwiftUI
import PDFKit
import Combine

// MARK: - Notification names
extension Notification.Name {
    static let xreaderGoToPage = Notification.Name("xreaderGoToPage")
    static let xreaderSearchPDF = Notification.Name("xreaderSearchPDF")
}

// MARK: - Bookmark model
struct Bookmark: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let page: Int
    let date: Date
    
    init(title: String, page: Int) {
        self.id = UUID()
        self.title = title
        self.page = page
        self.date = Date()
    }
}

struct OpenPDFTab: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var title: String
    let document: PDFDocument
    var currentPage: Int
    var totalPages: Int
    var outlineItems: [OutlineItem]
    var bookmarks: [Bookmark]

    static func == (lhs: OpenPDFTab, rhs: OpenPDFTab) -> Bool {
        lhs.id == rhs.id
    }
}

private struct PersistedOpenPDFTab: Codable {
    let id: UUID
    let url: String
    let path: String?
    let title: String
    let currentPage: Int
}

private struct PersistedTabSession: Codable {
    let tabs: [PersistedOpenPDFTab]
    let activeTabID: UUID?
}

@MainActor
class AppState: ObservableObject {
    
    /// Shared reference for WindowCloseHandler to set isTerminating before quit
    nonisolated(unsafe) static weak var shared: AppState?
    private var annotationSaveWorkItem: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []
    private var isSwitchingTabs = false
    
    // MARK: - PDF State
    @Published var document: PDFDocument?
    @Published var bookTitle: String = "X-Reader"
    
    /// Target page for PDFView to jump to AFTER it's created & document is set.
    /// Solves race condition: goToPage notification fires before PDFView exists.
    @Published var pendingTargetPage: Int? = nil
    
    // Flag to prevent PDFView's page change notification from overwriting restored position
    private(set) var isRestoringPosition: Bool = false
    // Extra flag: suppress ALL page change handling during full layout restoration
    private(set) var isRestoringLayout: Bool = false
    // Suppress page change saves during app termination (PDFView teardown fires spurious page=0)
    nonisolated(unsafe) var isTerminating: Bool = false
    
    @Published var currentPage: Int = 0 {
        didSet {
            guard !isRestoringPosition && !isRestoringLayout && !isTerminating && !isSwitchingTabs else { return }
            syncActiveTabStateFromRuntime()
            saveReadingPosition()
            // Also keep hidden bookmark up-to-date as real-time backup
            // This ensures position survives ANY type of app exit (force quit, crash, etc.)
            saveHiddenBookmark()
        }
    }
    @Published var totalPages: Int = 0
    @Published var currentScale: CGFloat = 1.0 {
        didSet {
            guard !isRestoringLayout else { return }
        }
    }
    @Published var pdfURL: URL?
    @Published var openTabs: [OpenPDFTab] = [] {
        didSet {
            guard !isRestoringTabSession, !isPersistingTabSession else { return }
            saveTabSession()
        }
    }
    @Published var activeTabID: UUID? {
        didSet {
            guard !isRestoringTabSession, !isPersistingTabSession else { return }
            saveTabSession()
        }
    }
    private var documentCache: [String: PDFDocument] = [:]
    private var isRestoringTabSession: Bool = false
    private var isPersistingTabSession: Bool = false

    private var activeTabIndex: Int? {
        guard let activeTabID else { return nil }
        return openTabs.firstIndex { $0.id == activeTabID }
    }
    
    // MARK: - Table of Contents
    @Published var outlineItems: [OutlineItem] = []
    
    // MARK: - Selection & Analysis
    @Published var selectedText: String = ""
    @Published var selectedRange: NSRange?
    @Published var showAnalysis: Bool = false {
        didSet {
            UserDefaults.standard.set(showAnalysis, forKey: analysisPanelVisibleKey)
        }
    }
    
    // MARK: - Translation
    @Published var translatedText: String = ""
    @Published var isTranslating: Bool = false
    @Published var translationError: String = ""
    
    // MARK: - TTS
    @Published var isSpeaking: Bool = false
    @Published var currentWordIndex: Int = 0
    @Published var selectedVoiceId: String = "kokoro:af_bella"
    @Published var selectedVoiceName: String = "Kokoro — Bella (Female, Sweet)"
    
    // MARK: - Word Analysis
    @Published var wordAnalysis: GrammarResult?
    @Published var lookedUpWords: [WordDetail] = [] {
        didSet { saveLookedUpWords() }
    }
    
    // MARK: - OCR
    @Published var isOCRRunning: Bool = false
    @Published var ocrProgress: Double = 0
    
    // MARK: - Theme
    @Published var isDarkMode: Bool = true
    @Published var themeMode: ThemeMode = .dark
    
    enum ThemeMode: String, CaseIterable {
        case light = "light"
        case dark = "dark"
        case system = "system"
        
        var label: String {
            switch self {
            case .light: return "浅色"
            case .dark: return "深色"
            case .system: return "跟随系统"
            }
        }
        
        var icon: String {
            switch self {
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            case .system: return "circle.lefthalf.filled"
            }
        }
    }
    
    // MARK: - Sidebar
    @Published var showSidebar: Bool = true {
        didSet {
            UserDefaults.standard.set(showSidebar, forKey: sidebarVisibleKey)
        }
    }
    
    // MARK: - Search
    @Published var searchQuery: String = ""
    @Published var searchResultCount: Int = 0
    @Published var isSearchActive: Bool = false
    @Published var currentSearchMatchIndex: Int = 0
    
    // MARK: - Highlight
    struct HighlightColor {
        let id: String
        let label: String
        let color: Color
        let nsColor: NSColor
    }
    
    static let highlightColors: [HighlightColor] = [
        HighlightColor(id: "yellow", label: "Yellow", color: .yellow, nsColor: .systemYellow),
        HighlightColor(id: "green", label: "Green", color: .green, nsColor: .systemGreen),
        HighlightColor(id: "pink", label: "Pink", color: .pink, nsColor: .systemPink),
        HighlightColor(id: "blue", label: "Blue", color: .blue, nsColor: .systemBlue),
    ]

    static func highlightColorID(for color: NSColor?) -> String? {
        guard let color else { return nil }
        let source = color.withAlphaComponent(1.0)
        return highlightColors.first { highlight in
            source.isSimilar(to: highlight.nsColor)
        }?.id
    }
    
    func addHighlight(color: NSColor) {
        guard let pdfView = activePDFView(),
              let selection = effectiveSelection(in: pdfView)
        else { return }

        addHighlight(color: color, selection: selection, in: pdfView)
    }

    private func saveAnnotations() {
        guard let doc = document, let url = pdfURL else { return }
        if !doc.write(to: url) {
            print("[X-Reader] Failed to save annotations to \(url.path)")
        } else {
            print("[X-Reader] Saved annotations to \(url.path)")
        }
    }

    func clearAllHighlights() {
        guard let doc = document else { return }
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i) {
                let annotations = page.annotations.filter { $0.type == "Highlight" }
                for annotation in annotations {
                    page.removeAnnotation(annotation)
                }
            }
        }
        saveAnnotations()
    }

    func clearHighlightAtSelection() {
        guard let pdfView = activePDFView(),
              let selection = pdfView.currentSelection else { return }

        let selectionsByLine = selection.selectionsByLine()
        for lineSelection in selectionsByLine {
            guard let page = lineSelection.pages.first else { continue }
            let bounds = lineSelection.bounds(for: page)
            if bounds.isEmpty { continue }

            let annotationsToRemove = page.annotations.filter { annotation in
                annotation.type == "Highlight" && annotation.bounds.intersects(bounds)
            }
            for annotation in annotationsToRemove {
                page.removeAnnotation(annotation)
            }
        }
        saveAnnotations()
    }
    
    // MARK: - Bookmarks
    @Published var bookmarks: [Bookmark] = [] {
        didSet {
            guard !isSwitchingTabs else { return }
            syncActiveTabStateFromRuntime()
            saveBookmarks()
        }
    }
    
    // MARK: - Services
    let pdfService = PDFService()
    let ttsService = TTSService()
    let translationService = TranslationService()
    let grammarService = GrammarService()
    let wordTranslationCache: WordTranslationCache = {
        let ts = TranslationService()
        return WordTranslationCache(translationService: ts)
    }()
    let outlineService = OutlineService()
    let cacheManager = CacheManager()
    let ocrService = OCRService()
    
    // MARK: - UserDefaults keys
    private let bookmarksKey = "xreader_bookmarks"
    private let readingPositionPrefix = "xreader_last_page_"
    private let lastOpenedPDFKey = "xreader_last_opened_pdf"
    private let tabsSessionKey = "xreader_tabs_session_v1"
    private let sidebarVisibleKey = "xreader_sidebar_visible"
    private let analysisPanelVisibleKey = "xreader_analysis_panel_visible"
    private let lookedUpWordsKey = "xreader_looked_up_words_v1"

    /// Hidden bookmark key — stores the page position on app close, consumed on next launch
    private let hiddenBookmarkKey = "xreader_hidden_bookmark"
    
    // MARK: - Init
    init() {
        AppState.shared = self
        // Sync language setting — default to Chinese
        let langStr = UserDefaults.standard.string(forKey: "app_language") ?? AppLanguage.chinese.rawValue
        if let lang = AppLanguage(rawValue: langStr) {
            L10n.shared.language = lang
        }

        loadLookedUpWords()

        // === First-launch default layout ===
        let isFirstLaunch = UserDefaults.standard.object(forKey: sidebarVisibleKey) == nil

        if isFirstLaunch {
            showSidebar = true
            showAnalysis = true
            themeMode = .dark
            currentScale = 1.0
            UserDefaults.standard.set(true, forKey: sidebarVisibleKey)
            UserDefaults.standard.set(true, forKey: analysisPanelVisibleKey)
        } else {
            showSidebar = UserDefaults.standard.bool(forKey: sidebarVisibleKey)
            showAnalysis = UserDefaults.standard.bool(forKey: analysisPanelVisibleKey)
            updateAppearance()
        }

        // === Restore tab session first (multi-tab) ===
        if !restoreTabSession() {
            // Fallback: restore legacy single last-opened PDF
            if let urlString = UserDefaults.standard.string(forKey: lastOpenedPDFKey),
               let url = URL(string: urlString),
               FileManager.default.fileExists(atPath: url.path) {

                let savedPage = readHiddenBookmark()
                let targetPage = savedPage ?? 0

                print("[X-Reader] Launching PDF — hidden bookmark page: \(targetPage)")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.loadPDF(from: url, targetPage: targetPage)
                }
            }
        }

        // Listen for bookmark notification from context menu
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAddBookmarkNotification),
            name: Notification.Name("xreaderAddBookmark"),
            object: nil
        )

        // Listen for context highlight notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleContextHighlight(_:)),
            name: NSNotification.Name("contextHighlight"),
            object: nil
        )

        // Listen for context clear highlight notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleContextClearHighlight(_:)),
            name: NSNotification.Name("contextClearHighlight"),
            object: nil
        )

        updateAppearance()
        ttsService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        // Start loading Kokoro TTS model in background
        Task {
            await ttsService.loadKokoroModel()
        }
    }
    
    @objc private func handleAddBookmarkNotification() {
        addBookmark()
    }

    func persistSessionNow() {
        saveHiddenBookmark()
        saveTabSession()
    }

    @objc private func handleContextHighlight(_ notification: Notification) {
        if let color = notification.object as? NSColor {
            let eventPoint = (notification.userInfo?["eventPoint"] as? NSValue)?.pointValue
            applyHighlightColor(color: color, eventPoint: eventPoint)
        }
    }

    @objc private func handleContextClearHighlight(_ notification: Notification) {
        var eventPoint: NSPoint? = nil
        if let value = notification.userInfo?["eventPoint"] as? NSValue {
            eventPoint = value.pointValue
        }
        clearHighlightAtSelection(eventPoint: eventPoint)
    }

    func clearHighlightAtSelection(eventPoint: NSPoint? = nil) {
        guard let pdfView = activePDFView() else { return }

        var selection = pdfView.currentSelection
        if (selection == nil || selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true), let point = eventPoint {
            if let page = pdfView.page(for: point, nearest: true) {
                let pagePoint = pdfView.convert(point, to: page)
                selection = page.selectionForWord(at: pagePoint)
            }
        }

        if let selection = selection {
            let selectionsByLine = selection.selectionsByLine()
            let directMatches = selectionsByLine.flatMap { lineSelection -> [PDFAnnotation] in
                guard let page = lineSelection.pages.first else { return [] }
                let bounds = lineSelection.bounds(for: page)
                guard !bounds.isEmpty else { return [] }
                return page.annotations.filter { annotation in
                    annotation.type == "Highlight" && annotation.bounds.intersects(bounds)
                }
            }
            let annotationsToRemove = expandedHighlightCluster(for: directMatches)
            for annotation in annotationsToRemove {
                annotation.page?.removeAnnotation(annotation)
            }
            if !annotationsToRemove.isEmpty { saveAnnotations() }
            return
        }

        if let point = eventPoint, let page = pdfView.page(for: point, nearest: true) {
            let pagePoint = pdfView.convert(point, to: page)
            let hitAnnotations = page.annotations.filter { annotation in
                annotation.type == "Highlight" && annotation.bounds.contains(pagePoint)
            }
            let annotationsToRemove = expandedHighlightCluster(for: hitAnnotations)
            for annotation in annotationsToRemove {
                annotation.page?.removeAnnotation(annotation)
            }
            if !annotationsToRemove.isEmpty {
                saveAnnotations()
            }
        }
    }

    private func applyHighlightColor(color: NSColor, eventPoint: NSPoint?) {
        guard let pdfView = activePDFView() else { return }

        let annotationsToUpdate = highlightAnnotations(in: pdfView, eventPoint: eventPoint)
        if !annotationsToUpdate.isEmpty {
            let targetColor = color.withAlphaComponent(0.35)
            for annotation in annotationsToUpdate {
                annotation.color = targetColor
            }
            scheduleSaveAnnotations(delay: 0.25)
            return
        }

        if let selection = effectiveSelection(in: pdfView, eventPoint: eventPoint) {
            addHighlight(color: color, selection: selection, in: pdfView)
            return
        }

        // Avoid blocking modal alerts from context-menu actions.
        // A modal shown while menu tracking can appear as app freeze.
        NSSound.beep()
    }

    private func addHighlight(color: NSColor, selection: PDFSelection, in pdfView: PDFView) {
        guard let selectedText = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else { return }

        let alphaColor = color.withAlphaComponent(0.35)
        let selectionsByLine = selection.selectionsByLine()
        var added = false

        for lineSelection in selectionsByLine {
            guard let page = lineSelection.pages.first else { continue }
            let bounds = lineSelection.bounds(for: page)
            if bounds.isEmpty { continue }

            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = alphaColor
            annotation.border = PDFBorder()
            annotation.border?.lineWidth = 0
            if let text = lineSelection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                annotation.contents = text
            }
            page.addAnnotation(annotation)
            added = true
        }

        if added {
            pdfView.setCurrentSelection(selection, animate: false)
            scheduleSaveAnnotations(delay: 0.35)
        }
    }

    private func effectiveSelection(in pdfView: PDFView, eventPoint: NSPoint? = nil) -> PDFSelection? {
        if let selection = pdfView.currentSelection,
           let selectedText = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedText.isEmpty {
            return selection
        }

        guard let point = eventPoint,
              let page = pdfView.page(for: point, nearest: true) else { return nil }
        let pagePoint = pdfView.convert(point, to: page)
        guard let selection = page.selectionForWord(at: pagePoint),
              let selectedText = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else { return nil }
        return selection
    }

    private func highlightAnnotations(in pdfView: PDFView, eventPoint: NSPoint? = nil) -> [PDFAnnotation] {
        if let selection = effectiveSelection(in: pdfView) {
            let matches = selection.selectionsByLine().flatMap { lineSelection -> [PDFAnnotation] in
                guard let page = lineSelection.pages.first else { return [] }
                let bounds = lineSelection.bounds(for: page)
                guard !bounds.isEmpty else { return [] }
                return page.annotations.filter { annotation in
                    annotation.type == "Highlight" && annotation.bounds.intersects(bounds)
                }
            }
            if !matches.isEmpty {
                return deduplicatedAnnotations(matches)
            }
        }

        guard let point = eventPoint,
              let page = pdfView.page(for: point, nearest: true) else { return [] }
        let pagePoint = pdfView.convert(point, to: page)
        let hitAnnotations = page.annotations.filter { annotation in
            annotation.type == "Highlight" && annotation.bounds.contains(pagePoint)
        }
        guard let seed = hitAnnotations.first else { return [] }
        return highlightCluster(seed: seed, on: page)
    }

    private func deduplicatedAnnotations(_ annotations: [PDFAnnotation]) -> [PDFAnnotation] {
        var seen = Set<ObjectIdentifier>()
        return annotations.filter { annotation in
            let identifier = ObjectIdentifier(annotation)
            return seen.insert(identifier).inserted
        }
    }

    private func expandedHighlightCluster(for seedAnnotations: [PDFAnnotation]) -> [PDFAnnotation] {
        guard !seedAnnotations.isEmpty else { return [] }
        var merged: [PDFAnnotation] = []
        for seed in deduplicatedAnnotations(seedAnnotations) {
            guard let page = seed.page else { continue }
            merged.append(contentsOf: highlightCluster(seed: seed, on: page))
        }
        return deduplicatedAnnotations(merged)
    }

    private func highlightCluster(seed: PDFAnnotation, on page: PDFPage) -> [PDFAnnotation] {
        let allHighlights = page.annotations.filter { $0.type == "Highlight" }
        guard !allHighlights.isEmpty else { return [seed] }

        var queue: [PDFAnnotation] = [seed]
        var visited: Set<ObjectIdentifier> = [ObjectIdentifier(seed)]
        var cluster: [PDFAnnotation] = [seed]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            for candidate in allHighlights {
                let candidateID = ObjectIdentifier(candidate)
                if visited.contains(candidateID) { continue }
                if areLikelySameHighlightBlock(current, candidate) {
                    visited.insert(candidateID)
                    queue.append(candidate)
                    cluster.append(candidate)
                }
            }
        }

        return cluster
    }

    private func areLikelySameHighlightBlock(_ a: PDFAnnotation, _ b: PDFAnnotation) -> Bool {
        // Keep cluster conservative: only connect highlights with similar color.
        let aColor = a.color.withAlphaComponent(1.0)
        let bColor = b.color.withAlphaComponent(1.0)
        guard aColor.isSimilar(to: bColor, tolerance: 0.16) else { return false }

        let aBounds = a.bounds
        let bBounds = b.bounds

        // Directly touching/overlapping lines should definitely be connected.
        if aBounds.insetBy(dx: -4, dy: -3).intersects(bBounds.insetBy(dx: -4, dy: -3)) {
            return true
        }

        // Also connect nearby lines with horizontal overlap / same text column.
        // Reopened PDFs may slightly change bounds, so use adaptive thresholds.
        let yGap: CGFloat = max(0, max(aBounds.minY, bBounds.minY) - min(aBounds.maxY, bBounds.maxY))
        let lineHeight = max(8, min(aBounds.height, bBounds.height))
        let maxYGap = max(12, lineHeight * 1.4)

        let xOverlap: CGFloat = max(0, min(aBounds.maxX, bBounds.maxX) - max(aBounds.minX, bBounds.minX))
        let minWidth = max(1, min(aBounds.width, bBounds.width))
        let overlapRatio = xOverlap / minWidth

        let closeLeftEdge = abs(aBounds.minX - bBounds.minX) <= max(24, lineHeight * 2.2)
        let closeMidX = abs(aBounds.midX - bBounds.midX) <= max(42, lineHeight * 3.0)
        let sameColumn = closeLeftEdge || closeMidX

        return yGap <= maxYGap && (overlapRatio >= 0.08 || sameColumn)
    }

    private func activePDFView() -> PDFView? {
        if let view = NSApp.keyWindow?.contentView?.findPdfView() as? PDFView {
            return view
        }
        if let view = NSApp.mainWindow?.contentView?.findPdfView() as? PDFView {
            return view
        }
        for window in NSApp.orderedWindows {
            if let view = window.contentView?.findPdfView() as? PDFView {
                return view
            }
        }
        return nil
    }

    private func scheduleSaveAnnotations(delay: TimeInterval) {
        annotationSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveAnnotations()
        }
        annotationSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    func updateAppearance() {
        switch themeMode {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
            isDarkMode = false
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
            isDarkMode = true
        case .system:
            NSApp.appearance = nil
            isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
    
    func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
        updateAppearance()
    }
    
    func toggleTheme() {
        // Cycle: dark -> light -> system -> dark
        switch themeMode {
        case .dark: setThemeMode(.light)
        case .light: setThemeMode(.system)
        case .system: setThemeMode(.dark)
        }
    }

    private func syncActiveTabStateFromRuntime() {
        guard let index = activeTabIndex else { return }
        guard let currentDocument = document else { return }
        let activeTab = openTabs[index]
        guard activeTab.document === currentDocument else { return }
        guard totalPages > 0 else { return }
        openTabs[index].currentPage = currentPage
        openTabs[index].totalPages = totalPages
        openTabs[index].outlineItems = outlineItems
        openTabs[index].bookmarks = bookmarks
    }

    private func resetReaderTransientState() {
        selectedText = ""
        translatedText = ""
        wordAnalysis = nil
        searchQuery = ""
        isSearchActive = false
        currentSearchMatchIndex = 0
        searchResultCount = 0
    }

    private func activateTab(_ tabID: UUID, targetPage: Int? = nil, unlockDelay: TimeInterval = 0.7) {
        guard let index = openTabs.firstIndex(where: { $0.id == tabID }) else { return }

        syncActiveTabStateFromRuntime()

        let tab = openTabs[index]
        let safePage = max(0, min(targetPage ?? tab.currentPage, max(0, tab.totalPages - 1)))
        let switchingWithinSameDocument = (document === tab.document)

        if switchingWithinSameDocument {
            activeTabID = tab.id
            pdfURL = tab.url
            bookTitle = tab.title
            totalPages = tab.totalPages
            outlineItems = tab.outlineItems
            bookmarks = tab.bookmarks
            currentPage = safePage
            UserDefaults.standard.set(tab.url.absoluteString, forKey: lastOpenedPDFKey)
            resetReaderTransientState()

            if let page = tab.document.page(at: safePage) {
                NotificationCenter.default.post(name: .xreaderGoToPage, object: page)
            }
            saveHiddenBookmark()
            return
        }

        pendingTargetPage = safePage
        isRestoringPosition = true
        isRestoringLayout = true
        isSwitchingTabs = true

        activeTabID = tab.id
        document = tab.document
        pdfURL = tab.url
        bookTitle = tab.title
        totalPages = tab.totalPages
        outlineItems = tab.outlineItems
        bookmarks = tab.bookmarks
        currentPage = safePage
        UserDefaults.standard.set(tab.url.absoluteString, forKey: lastOpenedPDFKey)
        resetReaderTransientState()

        DispatchQueue.main.asyncAfter(deadline: .now() + unlockDelay) { [weak self] in
            self?.isRestoringPosition = false
            self?.isSwitchingTabs = false
            self?.saveHiddenBookmark()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + unlockDelay + 0.25) { [weak self] in
            self?.isRestoringLayout = false
            self?.pendingTargetPage = nil
        }
    }

    func switchToTab(_ tabID: UUID) {
        activateTab(tabID)
    }

    func closeTab(_ tabID: UUID) {
        syncActiveTabStateFromRuntime()
        guard let index = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let closingActive = activeTabID == tabID
        openTabs.remove(at: index)

        if openTabs.isEmpty {
            activeTabID = nil
            document = nil
            pdfURL = nil
            bookTitle = "X-Reader"
            totalPages = 0
            currentPage = 0
            pendingTargetPage = nil
            outlineItems = []
            bookmarks = []
            resetReaderTransientState()
            return
        }

        if closingActive {
            let fallbackIndex = min(index, openTabs.count - 1)
            activateTab(openTabs[fallbackIndex].id, unlockDelay: 0.45)
        }
    }
    
    // MARK: - Open PDF
    func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = L10n.t(.selectPdfFile)
        
        if panel.runModal() == .OK, let url = panel.url {
            loadPDFReplacingActiveTab(from: url)
        }
    }

    func duplicateCurrentTab() {
        guard let currentURL = pdfURL else {
            openPDF()
            return
        }

        syncActiveTabStateFromRuntime()
        guard let currentIndex = activeTabIndex else {
            loadPDF(from: currentURL, targetPage: currentPage)
            return
        }

        let currentTab = openTabs[currentIndex]
        let duplicate = OpenPDFTab(
            id: UUID(),
            url: currentTab.url,
            title: currentTab.title,
            document: currentTab.document,
            currentPage: currentPage,
            totalPages: currentTab.totalPages,
            outlineItems: currentTab.outlineItems,
            bookmarks: currentTab.bookmarks
        )
        openTabs.append(duplicate)
        activateTab(duplicate.id, targetPage: currentPage, unlockDelay: 0.25)
    }

    func loadPDFReplacingActiveTab(from url: URL, targetPage: Int = 0) {
        if pdfURL != nil {
            saveHiddenBookmark()
            syncActiveTabStateFromRuntime()
        }

        guard let doc = cachedDocument(for: url) else { return }
        let safePage = max(0, min(targetPage, max(0, doc.pageCount - 1)))
        let replacementID = activeTabID ?? UUID()
        let tab = OpenPDFTab(
            id: replacementID,
            url: url,
            title: displayTitle(for: doc, fallbackURL: url),
            document: doc,
            currentPage: safePage,
            totalPages: doc.pageCount,
            outlineItems: outlineService.extractOutline(from: doc),
            bookmarks: bookmarksForURL(url)
        )

        if let index = openTabs.firstIndex(where: { $0.id == replacementID }) {
            openTabs[index] = tab
        } else {
            openTabs.append(tab)
        }

        activateTab(tab.id, targetPage: safePage, unlockDelay: 0.7)
    }
    
    func loadPDF(from url: URL, targetPage: Int = 0) {
        if pdfURL != nil {
            saveHiddenBookmark()
            syncActiveTabStateFromRuntime()
        }

        guard let doc = cachedDocument(for: url) else { return }
        let safePage = max(0, min(targetPage, max(0, doc.pageCount - 1)))
        let tab = OpenPDFTab(
            id: UUID(),
            url: url,
            title: displayTitle(for: doc, fallbackURL: url),
            document: doc,
            currentPage: safePage,
            totalPages: doc.pageCount,
            outlineItems: outlineService.extractOutline(from: doc),
            bookmarks: bookmarksForURL(url)
        )
        openTabs.append(tab)
        activateTab(tab.id, targetPage: safePage, unlockDelay: 0.7)
    }
    
    // MARK: - Go to page
    func goToPage(_ pageIndex: Int) {
        guard let doc = document else { return }
        let safeIndex = max(0, min(pageIndex, doc.pageCount - 1))
        if let page = doc.page(at: safeIndex) {
            currentPage = safeIndex
            NotificationCenter.default.post(name: .xreaderGoToPage, object: page)
        }
    }
    
    // MARK: - Search in PDF
    func searchInPDF(_ query: String) {
        guard !query.isEmpty else {
            searchResultCount = 0
            currentSearchMatchIndex = 0
            isSearchActive = false
            return
        }
        
        isSearchActive = true
        currentSearchMatchIndex = 0
        
        // Count results
        if let doc = document {
            let selections = doc.findString(query, withOptions: .caseInsensitive)
            searchResultCount = selections.count
            // Navigate to first match
            if !selections.isEmpty {
                goToSearchMatch(selections, index: 0)
            }
        }
    }
    
    func searchNext(_ query: String) {
        guard let doc = document, searchResultCount > 0 else { return }
        let nextIndex = (currentSearchMatchIndex + 1) % searchResultCount
        let selections = doc.findString(query, withOptions: .caseInsensitive)
        guard nextIndex < selections.count else { return }
        currentSearchMatchIndex = nextIndex
        goToSearchMatch(selections, index: nextIndex)
    }
    
    func searchPrevious(_ query: String) {
        guard let doc = document, searchResultCount > 0 else { return }
        let prevIndex = (currentSearchMatchIndex - 1 + searchResultCount) % searchResultCount
        let selections = doc.findString(query, withOptions: .caseInsensitive)
        guard prevIndex < selections.count else { return }
        currentSearchMatchIndex = prevIndex
        goToSearchMatch(selections, index: prevIndex)
    }
    
    private func goToSearchMatch(_ selections: [PDFSelection], index: Int) {
        guard index < selections.count else { return }
        let sel = selections[index]
        guard let page = sel.pages.first, let doc = document else { return }
        let pageIndex = doc.index(for: page)
        goToPage(pageIndex)
        // Highlight
        if let pdfView = NSApp.keyWindow?.contentView?.findPdfView() {
            pdfView.setCurrentSelection(sel, animate: true)
            pdfView.go(to: sel)
        }
    }
    
    // MARK: - Selection handling
    private var selectionDebounceTimer: Timer?

    func handleTextSelection(_ text: String, range: NSRange) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedText = trimmed
        selectedRange = range

        // Debounce: wait 0.5s after selection stops changing before acting
        // This prevents constant stop/start TTS while user is dragging to select
        selectionDebounceTimer?.invalidate()
        if trimmed.isEmpty {
            // Just stop speaking — don't auto-close the panel
            // Panel only closes when user taps the close button
            stopSpeaking()
        } else {
            selectionDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self, !self.selectedText.isEmpty else { return }
                    self.showAnalysis = true
                    self.startSpeaking()
                    Task {
                        await self.translateSelectedText()
                        await self.analyzeSelectedWords()
                    }
                }
            }
        }
    }
    
    // MARK: - Translate
    @MainActor
    func translateSelectedText() async {
        guard !selectedText.isEmpty else { return }
        isTranslating = true
        translationError = ""
        
        if let cached = cacheManager.getCachedTranslation(for: selectedText) {
            translatedText = cached
            isTranslating = false
            return
        }
        
        let result = await translationService.translateWithFeedback(selectedText)
        if let error = result.error {
            translationError = error
            translatedText = ""
        } else {
            translatedText = result.text
            cacheManager.cacheTranslation(key: selectedText, value: result.text)
        }
        isTranslating = false
    }
    
    // MARK: - Word Analysis (POS + details)
    @MainActor
    func analyzeSelectedWords() async {
        guard !selectedText.isEmpty else { return }
        
        // First, get basic word analysis
        var analysis = grammarService.analyze(text: selectedText)
        
        // Then fill in translations from cache or API
        let words = analysis.wordDetails.map(\.word)
        if !words.isEmpty {
            // Check cache for all words first
            for i in 0..<analysis.wordDetails.count {
                let word = analysis.wordDetails[i].word
                if let cached = wordTranslationCache.getTranslation(for: word) {
                    analysis.wordDetails[i].meaning = cached
                }
            }
            
            // Update UI immediately with cached results
            wordAnalysis = analysis
            mergeIntoLookedUpWords(analysis.wordDetails)
            
            // Fetch missing translations in background
            let uncachedWords = words.filter {
                wordTranslationCache.shouldFetchAutoTranslation(for: $0)
            }
            
            if !uncachedWords.isEmpty {
                // Show loading state subtly — the cards are already visible
                let translations = await wordTranslationCache.batchTranslate(
                    uncachedWords,
                    engine: translationService
                )
                
                // Update results with newly fetched translations
                for i in 0..<analysis.wordDetails.count {
                    let word = analysis.wordDetails[i].word.lowercased()
                    if let trans = translations[word] ?? translations[analysis.wordDetails[i].word],
                       analysis.wordDetails[i].meaning == nil {
                        analysis.wordDetails[i].meaning = trans
                    }
                }
                
                // Re-assign to trigger UI update
                wordAnalysis = analysis
                mergeIntoLookedUpWords(analysis.wordDetails)
            }
        } else {
            wordAnalysis = analysis
            mergeIntoLookedUpWords(analysis.wordDetails)
        }
    }

    func applyManualMeaning(_ newMeaning: String, for word: WordDetail) {
        let trimmed = newMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        wordTranslationCache.setTranslationForWord(trimmed, for: word.word)

        if let idx = wordAnalysis?.wordDetails.firstIndex(where: { $0.id == word.id }) {
            wordAnalysis?.wordDetails[idx].meaning = trimmed.isEmpty ? nil : trimmed
        }

        let normalizedWord = normalizeWordKey(word.word)
        if let idx = lookedUpWords.firstIndex(where: { normalizeWordKey($0.word) == normalizedWord }) {
            lookedUpWords[idx].meaning = trimmed.isEmpty ? nil : trimmed
        }
    }
    
    // MARK: - TTS
    func startSpeaking() {
        guard !selectedText.isEmpty else { return }
        let voiceId = selectedVoiceId.isEmpty ? nil : selectedVoiceId
        ttsService.speak(selectedText, voiceIdentifier: voiceId) { [weak self] speaking, wordIndex in
            DispatchQueue.main.async {
                self?.isSpeaking = speaking
                self?.currentWordIndex = wordIndex
            }
        }
    }
    
    func stopSpeaking() {
        ttsService.stop()
        isSpeaking = false
        currentWordIndex = 0
    }
    
    // MARK: - OCR
    func runOCR() async {
        guard let doc = document else { return }
        isOCRRunning = true
        ocrProgress = 0
        
        await ocrService.recognizeDocument(doc) { progress in
            DispatchQueue.main.async {
                self.ocrProgress = progress
            }
        }
        
        isOCRRunning = false
    }
    
    // MARK: - Bookmarks
    
    func addBookmark() {
        guard let doc = document, pdfURL != nil else { return }
        let pageIndex = max(0, currentPage)
        guard pageIndex < doc.pageCount else { return }
        
        // Prevent duplicate bookmark for the same page
        if bookmarks.contains(where: { $0.page == pageIndex + 1 }) {
            // Already bookmarked, remove it (toggle behavior)
            // pageIndex is 0-based, but removeBookmark expects 1-based
            removeBookmark(at: pageIndex + 1)
            return
        }
        
        // Get page label
        let pdfPage = doc.page(at: pageIndex)
        let pageTitle = pdfPage?.label ?? "第 \(pageIndex + 1) 页"
        
        // Try to get first line of text from page
        if let pdfPage = pdfPage, let content = pdfPage.string {
            let firstLine = content.components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                .map { String($0.prefix(50)) } ?? pageTitle
            let bookmark = Bookmark(title: firstLine, page: pageIndex + 1)
            bookmarks.append(bookmark)
        } else {
            let bookmark = Bookmark(title: pageTitle, page: pageIndex + 1)
            bookmarks.append(bookmark)
        }
    }
    
    func removeBookmark(at page: Int) {
        bookmarks.removeAll { $0.page == page }
    }
    
    func isBookmarked(_ page: Int) -> Bool {
        bookmarks.contains { $0.page == page + 1 }
    }
    
    // MARK: - Hidden Bookmark (close → save latest one, open → restore & delete)

    /// Save current page as hidden bookmark — always OVERWRITES previous value.
    /// Called on every page change AND on app quit / PDF switch.
    func saveHiddenBookmark() {
        guard pdfURL != nil else { return }
        let data = try? JSONEncoder().encode(currentPage)
        if let data {
            UserDefaults.standard.set(data, forKey: hiddenBookmarkKey)
            print("[X-Reader] Hidden bookmark saved — page:\(currentPage)")
        }
    }

    /// Read the hidden bookmark WITHOUT deleting it.
    /// The bookmark is overwritten on every page turn via saveHiddenBookmark().
    /// Only delete when switching to a different PDF (in openPDF/loadPDF).
    private func readHiddenBookmark() -> Int? {
        guard let data = UserDefaults.standard.data(forKey: hiddenBookmarkKey),
              let savedPage = try? JSONDecoder().decode(Int.self, from: data) else {
            return nil
        }
        print("[X-Reader] Hidden bookmark read — page:\(savedPage)")
        return savedPage
    }

    // MARK: - Legacy persistence (backward compatible)
    
    private func readingPositionKey(for url: URL) -> String {
        readingPositionPrefix + url.absoluteString
    }
    
    private func saveReadingPosition() {
        guard let url = pdfURL else { return }
        saveReadingPosition(for: url)
    }
    
    private func saveReadingPosition(for url: URL) {
        UserDefaults.standard.set(currentPage, forKey: readingPositionKey(for: url))
    }
    
    private func saveBookmarks() {
        guard let url = pdfURL else { return }
        let key = bookmarksKey + "_" + sanitizeForUserDefaults(url.absoluteString)
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func mergeIntoLookedUpWords(_ words: [WordDetail]) {
        guard !words.isEmpty else { return }
        var merged = lookedUpWords

        for incoming in words {
            let key = normalizeWordKey(incoming.word)
            if let idx = merged.firstIndex(where: { normalizeWordKey($0.word) == key }) {
                var existing = merged[idx]
                existing.lemma = incoming.lemma
                existing.difficulty = harderDifficulty(existing.difficulty, incoming.difficulty)
                existing.posTags = mergedPosTags(existing, incoming)
                existing.posTags = sanitizePosTags(existing.posTags)
                if let manualOrCached = wordTranslationCache.getTranslation(for: incoming.word) {
                    existing.meaning = manualOrCached
                } else if existing.meaning == nil {
                    existing.meaning = incoming.meaning
                }
                existing.pos = existing.posTags.first ?? sanitizePosTags([incoming.pos]).first ?? ""
                merged[idx] = existing
            } else {
                var copy = incoming
                if copy.posTags.isEmpty { copy.posTags = [copy.pos] }
                copy.posTags = sanitizePosTags(copy.posTags)
                copy.pos = copy.posTags.first ?? ""
                if let manualOrCached = wordTranslationCache.getTranslation(for: incoming.word) {
                    copy.meaning = manualOrCached
                }
                merged.append(copy)
            }
        }

        lookedUpWords = merged
    }

    private func mergedPosTags(_ a: WordDetail, _ b: WordDetail) -> [String] {
        let source = (a.posTags.isEmpty ? [a.pos] : a.posTags) + (b.posTags.isEmpty ? [b.pos] : b.posTags)
        var seen = Set<String>()
        return source.filter { seen.insert($0).inserted }
    }

    private func sanitizePosTags(_ tags: [String]) -> [String] {
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { tag in
                guard !tag.isEmpty else { return false }
                let lower = tag.lowercased()
                return lower != "otherword" && tag != "未知" && tag != "词" && lower != "word"
            }
        return cleaned
    }

    private func harderDifficulty(_ lhs: String, _ rhs: String) -> String {
        let l = difficultyRank(lhs)
        let r = difficultyRank(rhs)
        return l >= r ? lhs : rhs
    }

    private func difficultyRank(_ value: String) -> Int {
        let upper = value.uppercased()
        if upper.contains("C2") { return 6 }
        if upper.contains("C1") { return 5 }
        if upper.contains("B2") { return 4 }
        if upper.contains("B1") { return 3 }
        if upper.contains("A2") { return 2 }
        return 1
    }

    private func normalizeWordKey(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveLookedUpWords() {
        if let data = try? JSONEncoder().encode(lookedUpWords) {
            UserDefaults.standard.set(data, forKey: lookedUpWordsKey)
        }
    }

    private func loadLookedUpWords() {
        guard let data = UserDefaults.standard.data(forKey: lookedUpWordsKey),
              let saved = try? JSONDecoder().decode([WordDetail].self, from: data) else {
            lookedUpWords = []
            return
        }
        lookedUpWords = saved.map { item in
            var copy = item
            let tags = sanitizePosTags(copy.posTags.isEmpty ? [copy.pos] : copy.posTags)
            copy.posTags = tags
            copy.pos = tags.first ?? ""
            return copy
        }
    }
    
    private func loadBookmarks(for url: URL) {
        bookmarks = bookmarksForURL(url)
    }

    private func bookmarksForURL(_ url: URL) -> [Bookmark] {
        let key = bookmarksKey + "_" + sanitizeForUserDefaults(url.absoluteString)
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            return saved
        }
        return []
    }

    private func displayTitle(for document: PDFDocument, fallbackURL url: URL) -> String {
        if let rawTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func cachedDocument(for url: URL) -> PDFDocument? {
        let key = url.standardizedFileURL.path
        if let cached = documentCache[key] {
            return cached
        }
        guard let document = PDFDocument(url: url) else { return nil }
        documentCache[key] = document
        return document
    }

    private func saveTabSession() {
        guard !isPersistingTabSession else { return }
        isPersistingTabSession = true
        defer { isPersistingTabSession = false }
        syncActiveTabStateFromRuntime()
        let persistedTabs = openTabs.map { tab in
            PersistedOpenPDFTab(
                id: tab.id,
                url: tab.url.absoluteString,
                path: tab.url.path,
                title: tab.title,
                currentPage: tab.currentPage
            )
        }
        let session = PersistedTabSession(tabs: persistedTabs, activeTabID: activeTabID)
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: tabsSessionKey)
        }
    }

    private func restoreTabSession() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: tabsSessionKey),
              let session = try? JSONDecoder().decode(PersistedTabSession.self, from: data),
              !session.tabs.isEmpty else {
            return false
        }

        var restoredTabs: [OpenPDFTab] = []
        for item in session.tabs {
            guard let url = persistedURL(for: item),
                  FileManager.default.fileExists(atPath: url.path),
                  let doc = cachedDocument(for: url) else { continue }

            let safePage = max(0, min(item.currentPage, max(0, doc.pageCount - 1)))
            let tab = OpenPDFTab(
                id: item.id,
                url: url,
                title: item.title.isEmpty ? displayTitle(for: doc, fallbackURL: url) : item.title,
                document: doc,
                currentPage: safePage,
                totalPages: doc.pageCount,
                outlineItems: outlineService.extractOutline(from: doc),
                bookmarks: bookmarksForURL(url)
            )
            restoredTabs.append(tab)
        }

        guard !restoredTabs.isEmpty else { return false }

        isRestoringTabSession = true
        openTabs = restoredTabs
        let restoredActiveID = session.activeTabID.flatMap { id in
            restoredTabs.contains(where: { $0.id == id }) ? id : nil
        } ?? restoredTabs.first?.id
        activeTabID = restoredActiveID
        isRestoringTabSession = false

        if let activeID = restoredActiveID,
           let activeTab = restoredTabs.first(where: { $0.id == activeID }) {
            activateTab(activeID, targetPage: activeTab.currentPage, unlockDelay: 0.35)
            return true
        }

        return false
    }

    private func persistedURL(for item: PersistedOpenPDFTab) -> URL? {
        if let path = item.path, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if let url = URL(string: item.url), url.isFileURL {
            return url
        }
        if !item.url.isEmpty {
            return URL(fileURLWithPath: item.url)
        }
        return nil
    }
    
    /// Sanitize URL string for use as UserDefaults key
    private func sanitizeForUserDefaults(_ string: String) -> String {
        string
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }
}

private extension NSColor {
    func isSimilar(to other: NSColor, tolerance: CGFloat = 0.08) -> Bool {
        guard let lhs = usingColorSpace(.deviceRGB),
              let rhs = other.usingColorSpace(.deviceRGB) else { return false }

        return abs(lhs.redComponent - rhs.redComponent) < tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) < tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) < tolerance
    }
}

// MARK: - Helper: find PDFView in view hierarchy

extension NSView {
    func findPdfView() -> PDFView? {
        if let pdfView = self as? PDFView { return pdfView }
        for subview in subviews {
            if let found = subview.findPdfView() { return found }
        }
        return nil
    }
}
