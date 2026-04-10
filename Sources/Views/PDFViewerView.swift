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

        // === CRITICAL: Jump to pending target page AFTER document is loaded ===
        if let targetPage = appState.pendingTargetPage,
           let doc = appState.document {
            let safeIndex = max(0, min(targetPage, doc.pageCount - 1))
            if let targetPDFPage = doc.page(at: safeIndex) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak pdfView] in
                    pdfView?.go(to: targetPDFPage)
                    print("[X-Reader] PDFViewerView jumped to pending page:\(safeIndex)")
                }
            }
        }

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

        // Observe page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pdfViewPageChanged(_:)),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )

        // Observe scale changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pdfViewScaleChanged(_:)),
            name: Notification.Name.PDFViewScaleChanged,
            object: pdfView
        )

        // Monitor selection changes via notification
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pdfViewSelectionChanged(_:)),
            name: Notification.Name.PDFViewSelectionChanged,
            object: pdfView
        )

        return pdfView
    }

    func updateNSView(_ pdfView: XReaderPDFView, context: Context) {
        // Only update document reference if it actually changed — prevents page reset
        if pdfView.document !== appState.document {
            pdfView.document = appState.document
        }

        // Handle pending target page when document changes
        if let targetPage = appState.pendingTargetPage,
           let doc = appState.document {
            let safeIndex = max(0, min(targetPage, doc.pageCount - 1))
            if let targetPDFPage = doc.page(at: safeIndex) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak pdfView] in
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

    @MainActor class Coordinator: NSObject {
        let appState: AppState
        var goToPageObserver: NSObjectProtocol?
        private var selectionDebounceWork: DispatchWorkItem?
        private var lastForwardedText: String = ""

        init(appState: AppState) {
            self.appState = appState
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

        // Custom items
        var customItems: [NSMenuItem] = []

        let translateItem = NSMenuItem(title: isZh ? "翻译" : "Translate", action: #selector(contextTranslate), keyEquivalent: "")
        translateItem.target = self
        customItems.append(translateItem)

        let speakItem = NSMenuItem(title: isZh ? "朗读" : "Speak", action: #selector(contextSpeak), keyEquivalent: "")
        speakItem.target = self
        customItems.append(speakItem)

        customItems.append(NSMenuItem.separator())

        let zoomInItem = NSMenuItem(title: isZh ? "放大" : "Zoom In", action: #selector(contextZoomIn), keyEquivalent: "")
        zoomInItem.target = self
        customItems.append(zoomInItem)

        let zoomOutItem = NSMenuItem(title: isZh ? "缩小" : "Zoom Out", action: #selector(contextZoomOut), keyEquivalent: "")
        zoomOutItem.target = self
        customItems.append(zoomOutItem)

        customItems.append(NSMenuItem.separator())

        let bookmarkItem = NSMenuItem(title: isZh ? "书签" : "Bookmark", action: #selector(contextBookmark), keyEquivalent: "")
        bookmarkItem.target = self
        customItems.append(bookmarkItem)

        let fullscreenItem = NSMenuItem(title: isZh ? "全屏" : "Fullscreen", action: #selector(contextFullscreen), keyEquivalent: "")
        fullscreenItem.target = self
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
            let clearItem = NSMenuItem(title: isZh ? "清除高亮" : "Clear Highlight", action: #selector(contextClearHighlight), keyEquivalent: "")
            clearItem.target = self
            customItems.append(clearItem)
        }

        if let menu = systemMenu {
            // 删除 "Remove Note" 菜单项
            removeRemoveNoteItems(menu)

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

    private func removeRemoveNoteItems(_ menu: NSMenu) {
        // 删除 "Remove Note" 和 "Remove Highlight" 相关菜单项（PDFKit 系统菜单自带但无效）
        var indicesToRemove: [Int] = []
        for (idx, item) in menu.items.enumerated() {
            if item.isSeparatorItem { continue }

            let titleLower = item.title.lowercased()
            if titleLower.contains("remove note") || titleLower.contains("移除备注") || titleLower.contains("删除备注")
                || titleLower.contains("remove highlight") || titleLower.contains("删除高亮") || titleLower.contains("移除高亮") {
                indicesToRemove.append(idx)
            }
        }

        for idx in indicesToRemove.reversed() {
            menu.removeItem(at: idx)
        }
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
