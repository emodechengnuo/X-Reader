//
//  MainView.swift
//  X-Reader
//
//  Main window layout with three-column design
//


import SwiftUI
import PDFKit

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            ToolbarView()
                .environmentObject(appState)
            
            Divider()

            if !appState.openTabs.isEmpty {
                PDFTabsBar()
                    .environmentObject(appState)
                Divider()
            }
            
            // Main content
            if !appState.openTabs.isEmpty, appState.activeTabID != nil {
                HStack(spacing: 0) {
                    // Left: Sidebar (outline + bookmarks)
                    if appState.showSidebar {
                        TableOfContentsView()
                            .environmentObject(appState)
                            .frame(width: 220)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    
                    if appState.showSidebar {
                        Divider()
                    }
                    
                    // Center: Persistent tab viewers (switch by visibility, no redraw/rebind on tab switch)
                    ZStack {
                        ForEach(appState.openTabs) { tab in
                            PDFViewerView(tabID: tab.id, document: tab.document)
                                .environmentObject(appState)
                                .opacity(appState.activeTabID == tab.id ? 1 : 0)
                                .allowsHitTesting(appState.activeTabID == tab.id)
                                .accessibilityHidden(appState.activeTabID != tab.id)
                        }
                    }
                    
                    // Right: Analysis Panel
                    if appState.showAnalysis {
                        Divider()
                        AnalysisPanelView()
                            .environmentObject(appState)
                            .frame(width: 320)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            } else {
                // Welcome / Empty state
                WelcomeView()
                    .environmentObject(appState)
            }
            
            Divider()
            
            // Bottom status bar
            StatusBarView()
                .environmentObject(appState)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            setupKeyboardShortcuts()
        }
    }

    private func setupKeyboardShortcuts() {
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak appState] event in
            guard let appState = appState else { return event }

            // Don't intercept if a text field has focus
            if let window = NSApp.keyWindow,
               let responder = window.firstResponder {
                if responder is NSTextView || responder is NSTextField {
                    return event
                }
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommand = mods.contains(.command)
            let hasControl = mods.contains(.control)
            let hasShift = mods.contains(.shift)
            let hasOption = mods.contains(.option)

            // Handle command shortcuts
            if hasCommand && !hasControl && !hasShift && !hasOption {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "f":
                    // Focus search field
                    NotificationCenter.default.post(name: NSNotification.Name("focusSearch"), object: nil)
                    return nil
                case "d":
                    // Add bookmark
                    appState.addBookmark()
                    return nil
                default:
                    break
                }
            }

            // Only handle plain arrow keys (no modifiers)
            if hasCommand || hasControl || hasShift || hasOption {
                return event
            }

            switch event.keyCode {
            case 123: // Left arrow
                if appState.document != nil {
                    appState.goToPage(appState.currentPage - 1)
                    return nil
                }
            case 124: // Right arrow
                if appState.document != nil {
                    appState.goToPage(appState.currentPage + 1)
                    return nil
                }
            default:
                break
            }

            return event
        }
    }
}

// MARK: - In-Window PDF Tabs

struct PDFTabsBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(appState.openTabs) { tab in
                    PDFTabChip(tab: tab)
                        .environmentObject(appState)
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: { appState.duplicateCurrentTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .help(l10n.language == .chinese ? "添加 PDF 标签" : "Add PDF Tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct PDFTabChip: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    let tab: OpenPDFTab

    private var isActive: Bool {
        appState.activeTabID == tab.id
    }

    private var tabCornerRadius: CGFloat { 16 }

    private var activeFillOpacity: Double {
        colorScheme == .dark ? 0.035 : 0.10
    }

    private var inactiveFillOpacity: Double {
        colorScheme == .dark ? 0.015 : 0.045
    }

    private var activeStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.22)
    }

    private var inactiveStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.10)
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isActive ? "book" : "book.closed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? .primary.opacity(0.92) : .secondary)

            Text(tab.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isActive ? .primary : .secondary.opacity(0.95))

            Spacer(minLength: 0)
        }
        .padding(.leading, 11)
        .padding(.trailing, 32)
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: tabCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: tabCornerRadius, style: .continuous)
                .fill((colorScheme == .dark ? Color.white : Color.black).opacity(isActive ? activeFillOpacity : inactiveFillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: tabCornerRadius, style: .continuous)
                .stroke(isActive ? activeStrokeColor : inactiveStrokeColor, lineWidth: isActive ? 1.0 : 0.8)
        )
        .overlay(alignment: .trailing) {
            Button(action: { appState.closeTab(tab.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(
                            (colorScheme == .dark ? Color.white : Color.black)
                                .opacity(isActive ? 0.12 : 0.07)
                        )
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .contentShape(RoundedRectangle(cornerRadius: tabCornerRadius, style: .continuous))
        .onTapGesture {
            appState.switchToTab(tab.id)
        }
    }
}

// MARK: - Empty State

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("📖")
                .font(.system(size: 72))

            VStack(spacing: 8) {
                Text(l10n.string(.welcomeTitle))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(l10n.string(.welcomeSubtitle))
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // Features
            VStack(spacing: 12) {
                FeatureRow(icon: "doc.text.viewfinder", title: l10n.string(.featureOCR))
                FeatureRow(icon: "list.bullet.rectangle", title: l10n.string(.featureToc))
                FeatureRow(icon: "speaker.wave.2", title: l10n.string(.featureTTS))
                FeatureRow(icon: "character.book.closed", title: l10n.string(.featureTranslate))
            }
            .padding(.horizontal, 40)

            Button(action: { appState.openPDF() }) {
                HStack {
                    Image(systemName: "folder")
                    Text(l10n.string(.openButton))
                }
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer()
        }
    }
}
