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
    private static var menuManager: AppMenuManager?

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .localized()
                .onAppear {
                    configureWindow()
                    Self.menuManager = AppMenuManager(appState: appState)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)

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
}

/// Dynamically localized app menu bar manager.
@MainActor
final class AppMenuManager {
    private weak var appState: AppState?
    private var notificationObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        buildMenu()
        observeLanguageChanges()
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func observeLanguageChanges() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .L10nLanguageChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.buildMenu()
            }
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "X-Reader", action: nil, keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L10n.t(.openPDF), action: #selector(openPDFMenuItem), keyEquivalent: "o")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L10n.t(.fullscreen), action: #selector(toggleFullscreenMenuItem), keyEquivalent: "f")
        appMenu.items.last?.keyEquivalentModifierMask = [.control, .command]
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide X-Reader", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        appMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit X-Reader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: L10n.t(.openPDF))
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: L10n.t(.openPDF), action: #selector(openPDFMenuItem), keyEquivalent: "o")
        mainMenu.addItem(fileMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openPDFMenuItem() {
        appState?.openPDF()
    }

    @objc private func toggleFullscreenMenuItem() {
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
