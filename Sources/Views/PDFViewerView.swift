//
//  PDFViewerView.swift
//  X-Reader
//
//  PDF rendering, text selection, pinch-to-zoom
//


import SwiftUI
import PDFKit

struct PDFViewerView: NSViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeNSView(context: Context) -> XReaderPDFView {
        let pdfView = XReaderPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .underPageBackgroundColor
        pdfView.minScaleFactor = 0.25
        pdfView.maxScaleFactor = 5.0
        pdfView.document = appState.document

        // Text selection callback — analyze selected text
        pdfView.onTextSelected = { [weak appState] text, range in
            guard let appState = appState else { return }
            Task { @MainActor in
                appState.handleTextSelection(text, range: range)
            }
        }

        // Pinch zoom callback
        pdfView.onPinchZoom = { [weak appState] scale in
            guard let appState = appState else { return }
            Task { @MainActor in
                appState.currentScale = max(0.25, min(5.0, scale))
            }
        }

        // Listen for page navigation notifications
        context.coordinator.goToPageObserver = NotificationCenter.default.addObserver(
            forName: .xreaderGoToPage,
            object: nil,
            queue: .main
        ) { [weak pdfView] notification in
            guard let page = notification.object as? PDFPage else { return }
            pdfView?.go(to: page)
        }

        context.coordinator.attachPDFObservers(to: pdfView)

        return pdfView
    }

    func updateNSView(_ pdfView: XReaderPDFView, context: Context) {
        let targetDocument = appState.document

        // Avoid resetting document on every state update: this causes visible flicker.
        if pdfView.document !== targetDocument {
            pdfView.document = targetDocument
            context.coordinator.lastAppliedPendingTarget = nil
            context.coordinator.lastAppliedPendingDocumentID = nil
        }

        // Apply pending target only once per (document, page) pair.
        if let targetPage = appState.pendingTargetPage,
           let doc = targetDocument {
            let safeIndex = max(0, min(targetPage, doc.pageCount - 1))
            let docID = ObjectIdentifier(doc)
            let alreadyApplied =
                context.coordinator.lastAppliedPendingDocumentID == docID &&
                context.coordinator.lastAppliedPendingTarget == safeIndex

            if !alreadyApplied, let targetPDFPage = doc.page(at: safeIndex) {
                context.coordinator.lastAppliedPendingDocumentID = docID
                context.coordinator.lastAppliedPendingTarget = safeIndex
                DispatchQueue.main.async { [weak pdfView] in
                    pdfView?.go(to: targetPDFPage)
                }
            }
        }

        // Only set scale if it's different (avoid feedback loop)
        let targetScale = appState.currentScale
        if abs(pdfView.scaleFactor - targetScale) > 0.001 {
            pdfView.scaleFactor = targetScale
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    static func dismantleNSView(_ pdfView: XReaderPDFView, coordinator: Coordinator) {
        coordinator.detachPDFObservers(from: pdfView)
        if let observer = coordinator.goToPageObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.goToPageObserver = nil
        }
    }

    @MainActor class Coordinator: NSObject {
        let appState: AppState
        var goToPageObserver: NSObjectProtocol?
        var lastAppliedPendingDocumentID: ObjectIdentifier?
        var lastAppliedPendingTarget: Int?
        private weak var observedPDFView: PDFView?
        private var selectionDebounceWork: DispatchWorkItem?
        private var lastForwardedText: String = ""

        init(appState: AppState) {
            self.appState = appState
        }

        deinit {
            selectionDebounceWork?.cancel()
            if let observer = goToPageObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attachPDFObservers(to pdfView: PDFView) {
            detachPDFObservers(from: observedPDFView)
            observedPDFView = pdfView

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pdfViewPageChanged(_:)),
                name: Notification.Name.PDFViewPageChanged,
                object: pdfView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pdfViewScaleChanged(_:)),
                name: Notification.Name.PDFViewScaleChanged,
                object: pdfView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pdfViewSelectionChanged(_:)),
                name: Notification.Name.PDFViewSelectionChanged,
                object: pdfView
            )
        }

        func detachPDFObservers(from pdfView: PDFView?) {
            guard let pdfView else { return }
            NotificationCenter.default.removeObserver(self, name: Notification.Name.PDFViewPageChanged, object: pdfView)
            NotificationCenter.default.removeObserver(self, name: Notification.Name.PDFViewScaleChanged, object: pdfView)
            NotificationCenter.default.removeObserver(self, name: Notification.Name.PDFViewSelectionChanged, object: pdfView)
            if observedPDFView === pdfView {
                observedPDFView = nil
            }
        }

        @objc func pdfViewPageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }

            let pageIndex = document.index(for: currentPage)
            guard !appState.isRestoringPosition, !appState.isRestoringLayout else { return }
            appState.currentPage = pageIndex
        }

        @objc func pdfViewScaleChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            appState.currentScale = pdfView.scaleFactor
        }

        // MARK: - Selection monitoring via PDFViewSelectionChanged notification
        @objc func pdfViewSelectionChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            selectionDebounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.handleSelectionChange(pdfView)
            }
            selectionDebounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        private func handleSelectionChange(_ pdfView: PDFView) {
            let text: String
            if let sel = pdfView.currentSelection, let str = sel.string {
                text = str.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                text = ""
            }

            // Skip if selection hasn't actually changed
            if text == lastForwardedText { return }
            lastForwardedText = text

            appState.handleTextSelection(text, range: text.isEmpty
                ? NSRange(location: 0, length: 0)
                : NSRange(location: 0, length: text.count))
        }
    }
}

// MARK: - Custom PDFView with selection & pinch zoom

class XReaderPDFView: PDFView, NSGestureRecognizerDelegate {
    private var lastSelectedText: String = ""
    private var lastMenuEventPoint: NSPoint?
    var onTextSelected: ((String, NSRange) -> Void)?
    var onPinchZoom: ((CGFloat) -> Void)?
    private static let menuAlignmentImage: NSImage = {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }()
    private static let menuIconConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // PDFView has built-in trackpad pinch-to-zoom via NSMagnificationGestureRecognizer.
        // We removed the custom gesture to avoid conflicts with PDFView's internal one.
        // Scale changes are synced to AppState via PDFViewScaleChanged notification in Coordinator.
    }

    // MARK: - Right-click context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let systemMenu = super.menu(for: event)
        let isZh = L10n.shared.language == .chinese

        let localPoint = convert(event.locationInWindow, from: nil)
        lastMenuEventPoint = localPoint

        let hasSelectedText = currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        // Custom items
        var customItems: [NSMenuItem] = []

        let translateItem = NSMenuItem(title: isZh ? "翻译" : "Translate", action: #selector(contextTranslate), keyEquivalent: "")
        translateItem.target = self
        setMenuIcon(translateItem, symbolName: "globe")
        customItems.append(translateItem)

        let speakItem = NSMenuItem(title: isZh ? "朗读" : "Speak", action: #selector(contextSpeak), keyEquivalent: "")
        speakItem.target = self
        setMenuIcon(speakItem, symbolName: "speaker.wave.2")
        customItems.append(speakItem)

        customItems.append(NSMenuItem.separator())

        let zoomInItem = NSMenuItem(title: isZh ? "放大" : "Zoom In", action: #selector(contextZoomIn), keyEquivalent: "")
        zoomInItem.target = self
        setMenuIcon(zoomInItem, symbolName: "plus.magnifyingglass")
        customItems.append(zoomInItem)

        let zoomOutItem = NSMenuItem(title: isZh ? "缩小" : "Zoom Out", action: #selector(contextZoomOut), keyEquivalent: "")
        zoomOutItem.target = self
        setMenuIcon(zoomOutItem, symbolName: "minus.magnifyingglass")
        customItems.append(zoomOutItem)

        customItems.append(NSMenuItem.separator())

        let bookmarkItem = NSMenuItem(title: isZh ? "书签" : "Bookmark", action: #selector(contextBookmark), keyEquivalent: "")
        bookmarkItem.target = self
        setMenuIcon(bookmarkItem, symbolName: "bookmark")
        customItems.append(bookmarkItem)

        let fullscreenItem = NSMenuItem(title: isZh ? "全屏" : "Fullscreen", action: #selector(contextFullscreen), keyEquivalent: "")
        fullscreenItem.target = self
        setMenuIcon(fullscreenItem, symbolName: "arrow.up.left.and.arrow.down.right")
        customItems.append(fullscreenItem)

        // 检查是否有高亮，添加"清除高亮"菜单项
        var hasHighlight = false
        if let selection = currentSelection, hasHighlightAtSelection(selection) {
            hasHighlight = true
        } else if hasHighlightAtPoint(localPoint) {
            hasHighlight = true
        }
        if hasHighlight {
            customItems.append(NSMenuItem.separator())
        }

        if hasHighlight || hasSelectedText {
            customItems.append(makeHighlightColorMenuItem())
        }

        if hasHighlight {
            let clearItem = NSMenuItem(title: isZh ? "清除高亮" : "Clear Highlight", action: #selector(contextClearHighlight), keyEquivalent: "")
            clearItem.target = self
            setMenuIcon(clearItem, symbolName: "eraser")
            customItems.append(clearItem)
        }

        if let menu = systemMenu {
            // 删除 PDFKit 自带的高亮编辑项，避免失灵的按钮和歪斜布局
            removeConflictingAnnotationItems(menu)
            applySystemMenuIcons(menu)

            // 在 Copy 后面插入自定义项
            let insertIdx = findInsertIndex(menu)
            for (offset, item) in customItems.enumerated() {
                menu.insertItem(item, at: insertIdx + offset)
            }
            return menu
        } else {
            let menu = NSMenu()
            for item in customItems {
                menu.addItem(item)
            }
            return menu
        }
    }

    private func findInsertIndex(_ menu: NSMenu) -> Int {
        for (idx, item) in menu.items.enumerated() {
            if item.action == #selector(copy(_:)) || item.action == NSSelectorFromString("copy:") {
                return idx + 1
            }
        }
        return 0
    }

    private func alignTextItem(_ item: NSMenuItem) {
        item.image = Self.menuAlignmentImage
    }

    private func setMenuIcon(_ item: NSMenuItem, symbolName: String) {
        let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(Self.menuIconConfiguration)
        item.image = icon ?? Self.menuAlignmentImage
    }

    private func applySystemMenuIcons(_ menu: NSMenu) {
        for item in menu.items {
            if item.isSeparatorItem { continue }

            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if title.isEmpty { continue }

            if title.contains("单页连续") || title.contains("single page continuous") {
                setMenuIcon(item, symbolName: "doc.on.doc")
                continue
            }

            if title.contains("双页连续") || title.contains("two-up continuous") || title.contains("two pages continuous") {
                setMenuIcon(item, symbolName: "square.split.2x1")
                continue
            }
        }
    }

    private func removeConflictingAnnotationItems(_ menu: NSMenu) {
        // 删除 PDFKit 自带但经常失灵的注释编辑项，保留其余系统菜单
        var indicesToRemove: [Int] = []
        for (idx, item) in menu.items.enumerated() {
            if item.isSeparatorItem { continue }

            let titleLower = item.title.lowercased()
            let title = titleLower.trimmingCharacters(in: .whitespacesAndNewlines)

            if item.view != nil
                || title.isEmpty
                || title == "u"
                || title == "s"
                || title.contains("remove note") || title.contains("移除备注") || title.contains("删除备注")
                || title.contains("remove highlight") || title.contains("删除高亮") || title.contains("移除高亮") {
                indicesToRemove.append(idx)
            }
        }

        for idx in indicesToRemove.reversed() {
            menu.removeItem(at: idx)
        }

        collapseAdjacentSeparators(in: menu)
    }

    private func collapseAdjacentSeparators(in menu: NSMenu) {
        var previousWasSeparator = true
        for index in menu.items.indices.reversed() {
            let item = menu.items[index]
            if item.isSeparatorItem {
                if previousWasSeparator || index == menu.items.count - 1 {
                    menu.removeItem(at: index)
                }
                previousWasSeparator = true
            } else {
                previousWasSeparator = false
            }
        }
    }

    private func makeHighlightColorMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let rowView = HighlightColorMenuRowView(
            colors: AppState.highlightColors,
            activeColorID: activeHighlightColorID(),
            onSelectColorID: { [weak self] colorID in
                self?.contextApplyHighlightColor(colorID: colorID)
            }
        )
        item.view = rowView
        return item
    }

    private func activeHighlightColorID() -> String? {
        guard let annotation = highlightAnnotationAtCurrentContext() else { return nil }
        return AppState.highlightColorID(for: annotation.color)
    }

    private func highlightAnnotationAtCurrentContext() -> PDFAnnotation? {
        if let selection = currentSelection {
            let selectionsByLine = selection.selectionsByLine()
            for lineSelection in selectionsByLine {
                guard let page = lineSelection.pages.first else { continue }
                let bounds = lineSelection.bounds(for: page)
                guard !bounds.isEmpty else { continue }

                if let annotation = page.annotations.first(where: { $0.type == "Highlight" && $0.bounds.intersects(bounds) }) {
                    return annotation
                }
            }
        }

        guard let point = lastMenuEventPoint,
              let page = page(for: point, nearest: true) else { return nil }
        let pagePoint = convert(point, to: page)
        return page.annotations.first(where: { $0.type == "Highlight" && $0.bounds.contains(pagePoint) })
    }

    private func hasHighlightAtSelection(_ selection: PDFSelection) -> Bool {
        let selectionsByLine = selection.selectionsByLine()
        for lineSelection in selectionsByLine {
            guard let page = lineSelection.pages.first else { continue }
            let bounds = lineSelection.bounds(for: page)
            if bounds.isEmpty { continue }

            for annotation in page.annotations {
                if annotation.type == "Highlight" {
                    if annotation.bounds.intersects(bounds) {
                        return true
                    }
                }
            }
        }
        return false
        
    }

    private func hasHighlightAtPoint(_ point: NSPoint) -> Bool {
        guard let page = page(for: point, nearest: true) else { return false }
        let pagePoint = convert(point, to: page)
        return page.annotations.contains { annotation in
            annotation.type == "Highlight" && annotation.bounds.contains(pagePoint)
        }
    }

    // MARK: - Selection & Gestures

    @objc private func contextTranslate() { checkSelection() }
    @objc private func contextSpeak() {
        if let s = currentSelection?.string?.trimmingCharacters(in:.whitespacesAndNewlines), !s.isEmpty {
            onTextSelected?(s, NSRange(location:0,length:s.count))
        }
    }
    @objc private func contextClearHighlight() {
        guard let point = lastMenuEventPoint else {
            NotificationCenter.default.post(name: NSNotification.Name("contextClearHighlight"), object: nil)
            return
        }
        NotificationCenter.default.post(name: NSNotification.Name("contextClearHighlight"), object: nil, userInfo: ["eventPoint": NSValue(point: point)])
    }
    private func contextApplyHighlightColor(colorID: String) {
        guard let point = lastMenuEventPoint,
              let color = AppState.highlightColors.first(where: { $0.id == colorID })?.nsColor else { return }

        NotificationCenter.default.post(
            name: NSNotification.Name("contextHighlight"),
            object: color,
            userInfo: ["eventPoint": NSValue(point: point)]
        )
    }
    @objc private func contextZoomIn() { onPinchZoom?(scaleFactor*1.25) }
    @objc private func contextZoomOut() { onPinchZoom?(scaleFactor/1.25) }
    @objc private func contextBookmark() { NotificationCenter.default.post(name:Notification.Name("xreaderAddBookmark"),object:nil) }
    @objc private func contextFullscreen() { window?.toggleFullScreen(nil) }

    // MARK: - Selection (for right-click menu)

    /// Called by right-click menu — reads currentSelection directly
    private func checkSelection() {
        guard let sel = currentSelection,
              let str = sel.string,
              !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastSelectedText = ""
            return
        }
        let t = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != lastSelectedText else { return }
        lastSelectedText = t
        onTextSelected?(t, NSRange(location: 0, length: t.count))
    }
}

private final class HighlightColorMenuRowView: NSView {
    private let colors: [AppState.HighlightColor]
    private let activeColorID: String?
    private let onSelectColorID: (String) -> Void
    private let leadingInset: CGFloat = 44
    private let dotSize: CGFloat = 16
    private let dotSpacing: CGFloat = 18

    override var isFlipped: Bool { true }

    init(colors: [AppState.HighlightColor], activeColorID: String?, onSelectColorID: @escaping (String) -> Void) {
        self.colors = colors
        self.activeColorID = activeColorID
        self.onSelectColorID = onSelectColorID
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 34))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for (index, highlight) in colors.enumerated() {
            let rect = circleRect(at: index)
            highlight.nsColor.setFill()
            NSBezierPath(ovalIn: rect).fill()

            let ringColor: NSColor = (highlight.id == activeColorID) ? .white : NSColor.black.withAlphaComponent(0.2)
            ringColor.setStroke()
            let ringPath = NSBezierPath(ovalIn: rect)
            ringPath.lineWidth = (highlight.id == activeColorID) ? 2 : 1
            ringPath.stroke()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let tappedIndex = colors.indices.first(where: { circleRect(at: $0).contains(point) }) else {
            super.mouseUp(with: event)
            return
        }

        onSelectColorID(colors[tappedIndex].id)
        enclosingMenuItem?.menu?.cancelTracking()
    }

    private func circleRect(at index: Int) -> NSRect {
        let x = leadingInset + CGFloat(index) * (dotSize + dotSpacing)
        let y = (bounds.height - dotSize) / 2
        return NSRect(x: x, y: y, width: dotSize, height: dotSize)
    }
}
