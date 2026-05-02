//
//  ToolbarView.swift
//  X-Reader
//
//  Top toolbar with controls
//


import SwiftUI
import PDFKit

// MARK: - NSSearchField subclass that reliably handles ⌘V/C/X/A
// SwiftUI NSViewRepresentable wrapping can sometimes prevent the field editor from
// receiving key equivalents directly; overriding performKeyEquivalent ensures paste always works.
private class PasteableSearchField: NSSearchField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only handle plain ⌘ combos (no additional modifiers)
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods == .command else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": return NSApp.sendAction(#selector(NSText.paste(_:)),     to: nil, from: self)
        case "c": return NSApp.sendAction(#selector(NSText.copy(_:)),      to: nil, from: self)
        case "x": return NSApp.sendAction(#selector(NSText.cut(_:)),       to: nil, from: self)
        case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        default:  return super.performKeyEquivalent(with: event)
        }
    }
}

// MARK: - NSSearchField wrapper to bypass SwiftUI TextField focus issues

struct SearchFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onEnter: () -> Void
    let onShiftEnter: () -> Void
    @Binding var shouldFocus: Bool
    /// 创建完 NSSearchField 后回调，供调用方持有引用（closeSearch 清理用）
    var onFieldCreated: ((NSSearchField) -> Void)? = nil

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = PasteableSearchField()
        searchField.placeholderString = placeholder
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.isBordered = true
        searchField.bezelStyle = .roundedBezel
        searchField.delegate = context.coordinator
        searchField.cell?.sendsActionOnEndEditing = false

        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.cancelButtonCell?.target = context.coordinator
            cell.cancelButtonCell?.action = #selector(Coordinator.cancelSearch)
        }

        context.coordinator.searchField = searchField
        context.coordinator.shouldFocus = $shouldFocus

        context.coordinator.registerFocusObserver()

        // 把 NSSearchField 引用回传给 ToolbarView，供 closeSearch 清理用
        context.coordinator.onSearchFieldCreated?(searchField)

        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
        // ⌘F sets shouldFocus=true → show searchField → this fires → focus and reset
        if shouldFocus {
            searchField.window?.makeFirstResponder(searchField)
            shouldFocus = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, shouldFocus: $shouldFocus, onEnter: onEnter, onShiftEnter: onShiftEnter, onFieldCreated: onFieldCreated)
    }

    static func dismantleNSView(_ searchField: NSSearchField, coordinator: Coordinator) {
        coordinator.unregisterFocusObserver()
    }

    class Coordinator: NSObject, NSSearchFieldDelegate, NSTextFieldDelegate {
        var text: Binding<String>
        var shouldFocus: Binding<Bool>
        let onEnter: () -> Void
        let onShiftEnter: () -> Void
        var searchField: NSSearchField?
        var onSearchFieldCreated: ((NSSearchField) -> Void)?
        private var focusObserver: NSObjectProtocol?

        init(text: Binding<String>, shouldFocus: Binding<Bool>, onEnter: @escaping () -> Void, onShiftEnter: @escaping () -> Void, onFieldCreated: ((NSSearchField) -> Void)? = nil) {
            self.text = text
            self.shouldFocus = shouldFocus
            self.onEnter = onEnter
            self.onShiftEnter = onShiftEnter
            super.init()
            self.onSearchFieldCreated = onFieldCreated
        }

        deinit {
            unregisterFocusObserver()
        }

        func registerFocusObserver() {
            guard focusObserver == nil else { return }
            focusObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("focusSearch"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.focusSearch()
            }
        }

        func unregisterFocusObserver() {
            if let focusObserver {
                NotificationCenter.default.removeObserver(focusObserver)
                self.focusObserver = nil
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            if let searchField = obj.object as? NSSearchField {
                text.wrappedValue = searchField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) { onShiftEnter() } else { onEnter() }
                return true
            }
            return false
        }

        @objc func cancelSearch() { text.wrappedValue = "" }

        @objc func focusSearch() {
            if let searchField = self.searchField {
                searchField.window?.makeFirstResponder(searchField)
            }
        }
    }
}

struct ToolbarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @State private var showSearchField: Bool = false
    @State private var searchFieldText: String = ""
    @State private var shouldFocusSearchField: Bool = false
    @State private var _currentSearchField: NSSearchField?  // 持有当前 NSSearchField 引用，closeSearch 时用

    private func t(_ key: L10nKey) -> String { l10n.string(key) }

    var body: some View {
        ZStack {
            HStack {
                toolbarMainControls
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                toolbarRightControls
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            if showSearchField {
                searchBarView.transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("focusSearch"))) { _ in
            if !showSearchField {
                // 搜索框未显示 → 显示并聚焦
                showSearchField = true
                shouldFocusSearchField = true
            } else {
                // 搜索框已显示 → 关闭（再按 ⌘F 切换）
                withAnimation(.easeInOut(duration: 0.15)) { showSearchField = false }
                closeSearch()
            }
        }
    }

    @ViewBuilder
    private var toolbarMainControls: some View {
        HStack(spacing: 6) {
            Button(action: { appState.openPDF() }) {
                Image(systemName: "folder")
            }.help(t(.openPdfHelp))

            Divider().frame(height: 18)

            // Search toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) { showSearchField.toggle() }
                if !showSearchField { closeSearch() }
            }) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(showSearchField ? .accentColor : .secondary)
            }
            .help(t(.searchHelp))
            .disabled(appState.document == nil)

            // Zoom out
            Button(action: { appState.currentScale = max(0.25, appState.currentScale - 0.25) }) {
                Image(systemName: "minus.magnifyingglass")
            }.help(t(.zoomOutHelp))

            Text("\(Int(appState.currentScale * 100))%")
                .font(.caption).monospacedDigit().frame(width: 40)

            // Zoom in
            Button(action: { appState.currentScale = min(5.0, appState.currentScale + 0.25) }) {
                Image(systemName: "plus.magnifyingglass")
            }.help(t(.zoomInHelp))

            // Reset zoom
            Button(action: { appState.currentScale = 1.0 }) {
                Image(systemName: "arrow.counterclockwise")
            }.help(t(.resetZoomHelp))

            Divider().frame(height: 18)

            // Highlight colors
            HStack(spacing: 8) {
                ForEach(AppState.highlightColors, id: \.id) { highlight in
                    Button(action: { appState.addHighlight(color: highlight.nsColor) }) {
                        Circle()
                            .fill(highlight.color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help(t(.highlightHelp))
                    .disabled(appState.document == nil)
                }
            }
            .alignmentGuide(.firstTextBaseline) { _ in 0 }

            Divider().frame(height: 18)

            // Clear all highlights
            Button(action: {
                let alert = NSAlert()
                alert.messageText = t(.clearAllHighlightsTitle)
                alert.informativeText = t(.clearAllHighlightsMessage)
                alert.alertStyle = .warning
                alert.addButton(withTitle: t(.clearButton))
                alert.addButton(withTitle: t(.cancelButton))

                if alert.runModal() == .alertFirstButtonReturn {
                    appState.clearAllHighlights()
                }
            }) {
                Image(systemName: "eraser")
                    .foregroundColor(.red)
            }
            .help(t(.clearAllHighlightsHelp))
            .disabled(appState.document == nil)

            Divider().frame(height: 18)
            Button(action: { appState.addBookmark() }) {
                Image(systemName: appState.isBookmarked(appState.currentPage) ? "bookmark.fill" : "bookmark")
                    .foregroundColor(appState.isBookmarked(appState.currentPage) ? .accentColor : .secondary)
            }.help(t(.bookmarkHelp)).disabled(appState.document == nil)

            // OCR
            Button(action: { Task { await appState.runOCR() } }) {
                if appState.isOCRRunning {
                    ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "doc.text.viewfinder")
                }
            }.help(t(.ocrHelp)).disabled(appState.document == nil)
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var toolbarRightControls: some View {
        HStack(spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { appState.showSidebar.toggle() } }) {
                Image(systemName: "sidebar.leading").symbolRenderingMode(.hierarchical)
                    .foregroundColor(appState.showSidebar ? .accentColor : .secondary)
            }.help(t(.toggleSidebarHelp))

            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { appState.showAnalysis.toggle() } }) {
                Image(systemName: "sidebar.trailing").symbolRenderingMode(.hierarchical)
                    .foregroundColor(appState.showAnalysis ? .accentColor : .secondary)
            }.help(t(.toggleAnalysisHelp))

            Button(action: toggleFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").symbolRenderingMode(.hierarchical)
            }.help(t(.fullscreenHelp))

            Divider().frame(height: 18)

            Button(action: { appState.toggleTheme() }) {
                Image(systemName: appState.themeMode.icon)
            }.help(t(.themeHelp) + " (\(appState.themeMode.label))")
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Search Bar

    @ViewBuilder
    private var searchBarView: some View {
        HStack(spacing: 4) {
            SearchFieldRepresentable(
                text: $searchFieldText,
                placeholder: t(.searchPdfPlaceholder),
                onEnter: { performSearchOrNext() },
                onShiftEnter: { performSearchOrPrevious() },
                shouldFocus: $shouldFocusSearchField,
                onFieldCreated: { field in _currentSearchField = field }
            ).frame(maxWidth: .infinity)

            if appState.isSearchActive {
                Text(matchCountText).font(.system(size: 11))
                    .foregroundColor(appState.searchResultCount > 0 ? .secondary : .red)
                    .monospacedDigit().frame(minWidth: 40)
            }

            Button(action: { performSearchOrPrevious() }) {
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(appState.searchResultCount > 0 ? .primary : .secondary)
            }.buttonStyle(.borderless).disabled(appState.searchResultCount == 0)

            Button(action: { performSearchOrNext() }) {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(appState.searchResultCount > 0 ? .primary : .secondary)
            }.buttonStyle(.borderless).disabled(appState.searchResultCount == 0)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) { showSearchField = false }
                closeSearch()
            }) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
        .cornerRadius(6).padding(.horizontal, 12)
    }

    private var matchCountText: String {
        guard appState.searchResultCount > 0 else { return "0" }
        return "\(appState.currentSearchMatchIndex + 1)/\(appState.searchResultCount)"
    }

    private func performSearchOrNext() {
        let q = searchFieldText; guard !q.isEmpty else { return }
        if appState.isSearchActive && appState.searchResultCount > 0 { appState.searchNext(q) }
        else { appState.searchInPDF(q) }
    }

    private func performSearchOrPrevious() {
        let q = searchFieldText
        guard !q.isEmpty, appState.isSearchActive, appState.searchResultCount > 0 else { return }
        appState.searchPrevious(q)
    }

    private func closeSearch() {
        // 临时把 NSSearchField 的 delegate 设为 nil，切断旧 Coordinator 的回调链
        // 再改 text，避免触发 controlTextDidChange 导致 deallocated 对象访问
        if let field = _currentSearchField {
            field.delegate = nil
            field.stringValue = ""
        }
        _currentSearchField = nil
        searchFieldText = ""
        appState.isSearchActive = false
        appState.searchResultCount = 0
        appState.currentSearchMatchIndex = 0
    }

    private func toggleFullscreen() {
        guard let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) })
        else { return }
        w.toggleFullScreen(w)
    }
}
