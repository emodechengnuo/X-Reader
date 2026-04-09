//
//  XReaderApp.swift
//  X-Reader
//
//  Created by 虾虾 on 2026-04-08.
//


import SwiftUI

@main
struct XReaderApp: App {
    @StateObject private var appState = AppState()
    private static var closeHandler: WindowCloseHandler?

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .localized()
                .onAppear {
                    configureWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.t(.openPDF)) {
                    appState.openPDF()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .toolbar) {
                // Empty — we use our own ToolbarView
            }
            CommandGroup(after: .toolbar) {
                Button(L10n.t(.fullscreen)) {
                    toggleFullscreen()
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .localized()
        }
    }

    /// Configure the main window after it appears
    private func configureWindow() {
        guard let window = NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.isVisible }) else {
            // Window not ready yet — retry once
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                configureWindow()
            }
            return
        }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.collectionBehavior = [.fullScreenPrimary]

        // Red button → dynamic behavior based on setting
        let handler = WindowCloseHandler()
        Self.closeHandler = handler
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.target = handler
            closeButton.action = #selector(WindowCloseHandler.handleClose)
        }
    }

    private func toggleFullscreen() {
        guard let window = NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
        window.toggleFullScreen(window)
    }
}

/// Handles close button: either minimize to Dock or quit app, based on user setting.
@MainActor
private class WindowCloseHandler: NSObject {
    @objc func handleClose() {
        if UserDefaults.standard.bool(forKey: "close_as_minimize") {
            // Minimize to Dock — save hidden bookmark before hiding
            AppState.shared?.saveHiddenBookmark()
            NSApp.keyWindow?.miniaturize(nil)
        } else {
            // Quit app — set flag to prevent PDFView teardown from overwriting bookmark
            AppState.shared?.isTerminating = true
            NSApp.terminate(nil)
        }
    }
}
