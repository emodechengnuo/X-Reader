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

@MainActor
class AppState: ObservableObject {
    
    /// Shared reference for WindowCloseHandler to set isTerminating before quit
    nonisolated(unsafe) static weak var shared: AppState?
    private var annotationSaveWorkItem: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []
    
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
            guard !isRestoringPosition && !isRestoringLayout && !isTerminating else { return }
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
    private let sidebarVisibleKey = "xreader_sidebar_visible"
    private let analysisPanelVisibleKey = "xreader_analysis_panel_visible"

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

        // === Restore last opened PDF with hidden bookmark ===
        if let urlString = UserDefaults.standard.string(forKey: lastOpenedPDFKey),
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {

            // Consume hidden bookmark (read & delete in one shot)
            let savedPage = readHiddenBookmark()
            let targetPage = savedPage ?? 0  // fallback to page 0

            print("[X-Reader] Launching PDF — hidden bookmark page: \(targetPage)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.loadPDF(from: url, targetPage: targetPage)
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
            return
        }

        if let point = eventPoint, let page = pdfView.page(for: point, nearest: true) {
            let pagePoint = pdfView.convert(point, to: page)
            let annotationsToRemove = page.annotations.filter { annotation in
                annotation.type == "Highlight" && annotation.bounds.contains(pagePoint)
            }
            for annotation in annotationsToRemove {
                page.removeAnnotation(annotation)
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

        let alert = NSAlert()
        alert.messageText = L10n.t(.noTextSelectedTitle)
        alert.informativeText = L10n.t(.noTextSelectedMessage)
        alert.alertStyle = .warning
        alert.runModal()
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
        return page.annotations.filter { annotation in
            annotation.type == "Highlight" && annotation.bounds.contains(pagePoint)
        }
    }

    private func deduplicatedAnnotations(_ annotations: [PDFAnnotation]) -> [PDFAnnotation] {
        var seen = Set<ObjectIdentifier>()
        return annotations.filter { annotation in
            let identifier = ObjectIdentifier(annotation)
            return seen.insert(identifier).inserted
        }
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
    
    // MARK: - Open PDF
    func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = L10n.t(.selectPdfFile)
        
        if panel.runModal() == .OK, let url = panel.url {
            loadPDF(from: url)
        }
    }
    
    func loadPDF(from url: URL, targetPage: Int = 0) {
        // Save current position as hidden bookmark BEFORE switching
        if pdfURL != nil {
            saveHiddenBookmark()
        }

        if let doc = PDFDocument(url: url) {
            // Clamp target page to valid range first
            let safePage = max(0, min(targetPage, doc.pageCount - 1))

            print("[X-Reader] Loading PDF — pages:\(doc.pageCount), target page:\(safePage)")

            // === SET PENDING TARGET PAGE FIRST (before setting document!) ===
            // This tells the PDFView (once created) to jump to this page.
            // We set it BEFORE document so SwiftUI's re-render picks it up together.
            pendingTargetPage = safePage

            // Lock restoration — prevent PDFView's auto page-0 from overwriting us
            isRestoringPosition = true
            isRestoringLayout = true

            // NOW set the document (triggers SwiftUI to create/update PDFView)
            self.document = doc
            self.pdfURL = url
            self.bookTitle = url.deletingPathExtension().lastPathComponent
            self.totalPages = doc.pageCount

            // Extract outline
            self.outlineItems = outlineService.extractOutline(from: doc)

            // Load bookmarks
            loadBookmarks(for: url)

            // Save as last opened PDF
            UserDefaults.standard.set(url.absoluteString, forKey: lastOpenedPDFKey)

            // Reset state
            self.selectedText = ""
            self.translatedText = ""
            self.wordAnalysis = nil
            self.searchQuery = ""
            self.isSearchActive = false
            self.currentSearchMatchIndex = 0

            // Set currentPage for UI consistency
            self.currentPage = safePage

            // Gradual release of restoration locks
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.isRestoringPosition = false
                // Re-save hidden bookmark now that locks are released
                // (was suppressed during restoration, but the page is correct)
                self?.saveHiddenBookmark()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.isRestoringLayout = false
                self?.pendingTargetPage = nil  // Clear after use
            }
        }
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
            
            // Fetch missing translations in background
            let uncachedWords = words.filter { 
                wordTranslationCache.getTranslation(for: $0) == nil 
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
            }
        } else {
            wordAnalysis = analysis
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
        guard let doc = document, let url = pdfURL else { return }
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
    
    private func loadBookmarks(for url: URL) {
        let key = bookmarksKey + "_" + sanitizeForUserDefaults(url.absoluteString)
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = saved
        } else {
            bookmarks = []
        }
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
