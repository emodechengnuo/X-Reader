//
// XReaderApp.swift
// X-Reader
//
// Created by 虾虾 on 2026-04-08.
//

import SwiftUI
import AppKit

@main
struct XReaderApp: App {
 @StateObject private var appState = AppState()
 @AppStorage("app_language") private var appLanguage: String = AppLanguage.chinese.rawValue
 private static var closeHandler: WindowCloseHandler?

/// 当前语言（从 appLanguage 派生）
private var lang: AppLanguage {
 AppLanguage(rawValue: appLanguage) ?? .chinese
}

 var body: some Scene {
 WindowGroup {
 MainView()
 .environmentObject(appState)
 .onAppear {
 configureWindow()
 // 注册菜单刷新（只更新 AppKit 菜单，不触发 SwiftUI 重建）
 MenuRefresher.shared.register(appState: appState)
 }
 }
 .windowStyle(.hiddenTitleBar)
 .defaultSize(width: 1200, height: 800)
 .commands {
 // 删除编辑菜单
 CommandGroup(replacing: .pasteboard) { }

 // File menu - 替换"新建"项为"打开PDF"
 CommandGroup(replacing: .newItem) {
 Button(lang == .chinese ? "打开 PDF…" : "Open PDF...") {
 appState.openPDF()
 }
 .keyboardShortcut("o", modifiers: .command)
 }

 CommandGroup(after: .sidebar) {
 Divider()
 Button(lang == .chinese ? "进入全屏" : "Enter Fullscreen") {
 if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
 window.toggleFullScreen(window)
 }
 }
 .keyboardShortcut("f", modifiers: [.control, .command])

 Divider()

 Menu(lang == .chinese ? "语音引擎" : "Voice Engine") {
 ForEach(TTSService.allVoices.prefix(8)) { voice in
 Button(action: {
 appState.selectedVoiceId = voice.id
 appState.selectedVoiceName = voice.name
 }) {
 HStack {
 Text(voice.name)
 if voice.isKokoro {
 Text("⭐")
 }
 if voice.id == appState.selectedVoiceId {
 Image(systemName: "checkmark")
 }
 }
 }
 }
 }
 }
 }

 Settings {
 SettingsView()
 .environmentObject(appState)
 .localized()
 }
}

/// 使用 AppKit 直接刷新菜单，不重建 Scene
@MainActor
final class MenuRefresher {
 static let shared = MenuRefresher()
 private var observer: Any?

 private init() {}

 func register(appState: AppState) {
 // 监听语言变化，直接用 AppKit 更新菜单标题
 observer = NotificationCenter.default.addObserver(
   forName: .L10nLanguageChanged,
   object: nil,
   queue: .main
) { [weak self] _ in
   self?.refreshMenuTitles()
}
 }

 func refreshMenuTitles() {
 guard let lang = L10n.shared.language as AppLanguage? else { return }
 let isChinese = lang == .chinese

 // 更新 File 菜单中打开 PDF 的标题
 if let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu,
 let openItem = fileMenu.item(withTitle: "打开 PDF…") ?? fileMenu.item(withTitle: "Open PDF...") {
 openItem.title = isChinese ? "打开 PDF…" : "Open PDF..."
 }

 // 更新 View 菜单中的全屏和语音引擎
 if let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu {
 for item in viewMenu.items {
 if item.title == "进入全屏" || item.title == "Enter Fullscreen" {
 item.title = isChinese ? "进入全屏" : "Enter Fullscreen"
 }
 if let submenu = item.submenu, submenu.title == "语音引擎" || submenu.title == "Voice Engine" {
 submenu.title = isChinese ? "语音引擎" : "Voice Engine"
 }
 }
 }
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
 XReaderApp.closeHandler = handler
 if let closeButton = window.standardWindowButton(.closeButton) {
 closeButton.target = handler
 closeButton.action = #selector(WindowCloseHandler.handleClose)
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
}