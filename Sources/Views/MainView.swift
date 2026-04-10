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
            
            // Main content
            if appState.document != nil {
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
                    
                    // Center: PDF Viewer
                    // Stable id prevents PDFView from being recreated on language change
                    PDFViewerView()
                        .environmentObject(appState)
                        .id(appState.pdfURL?.absoluteString ?? "empty")
                    
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
