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
 ReaderWindowManager.shared.attachCurrentKeyWindowIfNeeded(appState: appState)
 // 注册菜单刷新（只更新 AppKit 菜单，不触发 SwiftUI 重建）
 MenuRefresher.shared.register(appState: appState)
 }
 }
 .windowStyle(.hiddenTitleBar)
 .defaultSize(width: 1200, height: 800)
 .commands {
 // 删除编辑菜单
 CommandGroup(replacing: .pasteboard) { }
 // 删除 App 菜单中的“服务”
 CommandGroup(replacing: .systemServices) { }
 // 自定义帮助组
 CommandGroup(replacing: .help) {
 Button(lang == .chinese ? "X-Reader 项目主页" : "X-Reader Project Page") {
 if let url = URL(string: "https://github.com/emodechengnuo/X-Reader") {
 NSWorkspace.shared.open(url)
 }
 }
 }
 // 清空窗口相关系统组，避免注入不需要的窗口/标签页命令
 CommandGroup(replacing: .windowSize) { }
 CommandGroup(replacing: .windowList) { }
 CommandGroup(replacing: .windowArrangement) {
 Button(lang == .chinese ? "最小化" : "Minimize") {
 if let window = NSApp.keyWindow ?? NSApp.mainWindow {
 window.miniaturize(nil)
 }
 }
 .keyboardShortcut("m", modifiers: .command)

 Button(lang == .chinese ? "缩放" : "Zoom") {
 if let window = NSApp.keyWindow ?? NSApp.mainWindow {
 window.zoom(nil)
 }
 }
 }

 // File menu - 替换"新建"项为"打开PDF"
 CommandGroup(replacing: .newItem) {
 Button(lang == .chinese ? "新建窗口" : "New Window") {
 ReaderWindowManager.shared.openNewWindow()
 }
 .keyboardShortcut("n", modifiers: .command)

 Divider()

 Button(lang == .chinese ? "打开 PDF…" : "Open PDF...") {
 (ReaderWindowManager.shared.activeAppState ?? appState).openPDF()
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
 private var observers: [NSObjectProtocol] = []
 private var refreshWorkItem: DispatchWorkItem?
 private var isApplyingMenuChanges = false

 private init() {}

 func register(appState: AppState) {
 // 监听语言变化，直接用 AppKit 更新菜单标题
 let languageObserver = NotificationCenter.default.addObserver(
   forName: .L10nLanguageChanged,
   object: nil,
   queue: .main
) { [weak self] _ in
   Task { @MainActor in
     self?.scheduleRefreshMenuTitles()
   }
}
 observers.append(languageObserver)

 // 窗口状态变化后系统可能重建部分菜单，重新应用一次多语言与菜单清理
 let activeObserver = NotificationCenter.default.addObserver(
   forName: NSApplication.didBecomeActiveNotification,
   object: nil,
   queue: .main
 ) { [weak self] _ in
   Task { @MainActor in
     self?.scheduleRefreshMenuTitles()
   }
 }
 observers.append(activeObserver)

 let enterFullScreenObserver = NotificationCenter.default.addObserver(
   forName: NSWindow.didEnterFullScreenNotification,
   object: nil,
   queue: .main
 ) { [weak self] _ in
   Task { @MainActor in
     self?.scheduleRefreshMenuTitles()
   }
 }
 observers.append(enterFullScreenObserver)

 let exitFullScreenObserver = NotificationCenter.default.addObserver(
   forName: NSWindow.didExitFullScreenNotification,
   object: nil,
   queue: .main
 ) { [weak self] _ in
   Task { @MainActor in
     self?.scheduleRefreshMenuTitles()
   }
 }
 observers.append(exitFullScreenObserver)

 refreshMenuTitles()
 }

 private func scheduleRefreshMenuTitles() {
 refreshWorkItem?.cancel()
 let work = DispatchWorkItem { [weak self] in
   self?.refreshMenuTitles()
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
     self?.refreshMenuTitles()
   }
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) { [weak self] in
     self?.refreshMenuTitles()
   }
 }
 refreshWorkItem = work
 DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
 }

 func refreshMenuTitles() {
 if isApplyingMenuChanges { return }
 isApplyingMenuChanges = true
 defer { isApplyingMenuChanges = false }

 guard let lang = L10n.shared.language as AppLanguage? else { return }
 let isChinese = lang == .chinese
 guard let mainMenu = NSApp.mainMenu else { return }

 updateTopLevelMenuTitles(in: mainMenu, isChinese: isChinese)
 localizeMenuItemsBySelector(in: mainMenu, isChinese: isChinese)
 localizeMenuItemsByKnownTitles(in: mainMenu, isChinese: isChinese)
 localizeHelpSearchField(in: mainMenu, isChinese: isChinese)
 updateAppMenu(in: mainMenu, isChinese: isChinese)
 updateWindowMenu(in: mainMenu, isChinese: isChinese)
 cleanMenus(in: mainMenu)

 updateMenuItemTitles(
   in: mainMenu,
   matching: ["打开 PDF…", "打开 PDF...", "Open PDF..."],
   to: isChinese ? "打开 PDF…" : "Open PDF..."
 )
 updateMenuItemTitles(
   in: mainMenu,
   matching: ["进入全屏", "Enter Fullscreen"],
   to: isChinese ? "进入全屏" : "Enter Fullscreen"
 )
 updateSubmenuTitles(
   in: mainMenu,
   matching: ["语音引擎", "Voice Engine"],
   to: isChinese ? "语音引擎" : "Voice Engine"
 )
 }

 private func updateTopLevelMenuTitles(in mainMenu: NSMenu, isChinese: Bool) {
 let menuTitlePairs: [([String], String, String)] = [
   (["File", "文件"], "文件", "File"),
   (["Edit", "编辑"], "编辑", "Edit"),
   (["View", "显示", "视图"], "显示", "View"),
   (["Window", "窗口"], "窗口", "Window"),
   (["Help", "帮助"], "帮助", "Help")
 ]

 for item in mainMenu.items {
   for (candidates, zhTitle, enTitle) in menuTitlePairs where candidates.contains(item.title) {
     let newTitle = isChinese ? zhTitle : enTitle
     item.title = newTitle
     item.submenu?.title = newTitle
     break
   }
 }
 }

 private func updateMenuItemTitles(in menu: NSMenu, matching titles: [String], to targetTitle: String) {
 for item in menu.items {
 if titles.contains(item.title) {
 item.title = targetTitle
 }
 if let submenu = item.submenu {
 updateMenuItemTitles(in: submenu, matching: titles, to: targetTitle)
 }
 }
 }

 private func localizeMenuItemsBySelector(in menu: NSMenu, isChinese: Bool) {
 let selectorTitleMap: [(String, String, String)] = [
   ("orderFrontStandardAboutPanel:", "关于 X-Reader", "About X-Reader"),
   ("showSettingsWindow:", "设置…", "Settings..."),
   ("hide:", "隐藏 X-Reader", "Hide X-Reader"),
   ("hideOtherApplications:", "隐藏其他", "Hide Others"),
   ("unhideAllApplications:", "显示全部", "Show All"),
   ("terminate:", "退出 X-Reader", "Quit X-Reader"),
   ("undo:", "撤销", "Undo"),
   ("redo:", "重做", "Redo"),
   ("cut:", "剪切", "Cut"),
   ("copy:", "复制", "Copy"),
   ("paste:", "粘贴", "Paste"),
   ("selectAll:", "全选", "Select All"),
   ("complete:", "自动填充", "AutoFill"),
   ("orderFrontSubstitutionsPanel:", "自动填充", "AutoFill"),
   ("startDictation:", "开始听写", "Start Dictation"),
    ("toggleContinuousSpellChecking:", "检查拼写时键入", "Check Spelling While Typing"),
   ("toggleSmartInsertDelete:", "智能插入和删除", "Smart Copy/Paste"),
   ("orderFrontCharacterPalette:", "表情与符号", "Emoji & Symbols"),
   ("performMiniaturize:", "最小化", "Minimize"),
   ("performZoom:", "缩放", "Zoom"),
   ("arrangeInFront:", "前置全部窗口", "Bring All to Front"),
   ("selectPreviousTab:", "显示上一个标签页", "Show Previous Tab"),
   ("selectNextTab:", "显示下一个标签页", "Show Next Tab"),
   ("moveTabToNewWindow:", "将标签页移到新窗口", "Move Tab to New Window"),
   ("mergeAllWindows:", "合并所有窗口", "Merge All Windows"),
   ("toggleFullScreen:", "进入全屏", "Enter Fullscreen")
 ]

 for item in menu.items {
   if let action = item.action {
     let actionName = NSStringFromSelector(action)
     if let (_, zh, en) = selectorTitleMap.first(where: { $0.0 == actionName }) {
       item.title = isChinese ? zh : en
     }
   }
   if let submenu = item.submenu {
     localizeMenuItemsBySelector(in: submenu, isChinese: isChinese)
   }
 }
 }

 private func localizeMenuItemsByKnownTitles(in menu: NSMenu, isChinese: Bool) {
 let titlePairs: [([String], String, String)] = [
   (["关于 X-Reader", "关于X-Reader", "About X-Reader"], "关于 X-Reader", "About X-Reader"),
   (["设置…", "设置...", "偏好设置…", "Settings...", "Preferences..."], "设置…", "Settings..."),
   (["隐藏 X-Reader", "隐藏X-Reader", "Hide X-Reader"], "隐藏 X-Reader", "Hide X-Reader"),
   (["隐藏其他", "Hide Others"], "隐藏其他", "Hide Others"),
   (["显示全部", "全部显示", "Show All"], "显示全部", "Show All"),
   (["退出 X-Reader", "退出X-Reader", "Quit X-Reader"], "退出 X-Reader", "Quit X-Reader"),
   (["关闭", "Close"], "关闭", "Close"),
   (["自动填充", "AutoFill"], "自动填充", "AutoFill"),
   (["拼写与语法", "Spelling and Grammar"], "拼写与语法", "Spelling and Grammar"),
   (["替换", "Substitutions"], "替换", "Substitutions"),
   (["显示标签页栏", "Show Tab Bar"], "显示标签页栏", "Show Tab Bar"),
   (["显示所有标签页", "Show All Tabs"], "显示所有标签页", "Show All Tabs"),
   (["最小化", "Minimize"], "最小化", "Minimize"),
   (["缩放", "Zoom"], "缩放", "Zoom"),
   (["填充", "Fill"], "填充", "Fill"),
   (["居中", "Center"], "居中", "Center"),
   (["进入全屏幕", "进入全屏", "Enter Full Screen", "Enter Fullscreen"], "进入全屏幕", "Enter Full Screen"),
   (["移动与调整大小", "Move & Resize"], "移动与调整大小", "Move & Resize"),
   (["全屏幕平铺", "Tile Window"], "全屏幕平铺", "Tile Window"),
   (["从组中移除窗口", "Remove Window from Set"], "从组中移除窗口", "Remove Window from Set"),
   (["前置全部窗口", "Bring All to Front"], "前置全部窗口", "Bring All to Front"),
   (["显示上一个标签页", "显示前一个标签页", "Show Previous Tab"], "显示上一个标签页", "Show Previous Tab"),
   (["显示下一个标签页", "显示后一个标签页", "Show Next Tab"], "显示下一个标签页", "Show Next Tab"),
   (["将标签页移到新窗口", "Move Tab to New Window"], "将标签页移到新窗口", "Move Tab to New Window"),
   (["合并所有窗口", "Merge All Windows"], "合并所有窗口", "Merge All Windows"),
   (["反馈给 Apple", "Send Feedback to Apple"], "反馈给 Apple", "Send Feedback to Apple"),
   (["搜索", "Search"], "搜索", "Search")
 ]

 for item in menu.items {
   for (candidates, zh, en) in titlePairs where candidates.contains(item.title) {
     item.title = isChinese ? zh : en
     break
   }
   if let submenu = item.submenu {
     localizeMenuItemsByKnownTitles(in: submenu, isChinese: isChinese)
   }
 }
 }

 private func localizeHelpSearchField(in mainMenu: NSMenu, isChinese: Bool) {
 guard let helpMenu = findSubmenu(in: mainMenu, titles: ["帮助", "Help"]) else { return }
 let placeholder = isChinese ? "搜索" : "Search"
 for item in helpMenu.items {
   guard let view = item.view else { continue }
   for field in extractSearchFields(from: view) {
     field.placeholderString = placeholder
   }
 }
 }

 private func extractSearchFields(from view: NSView) -> [NSSearchField] {
 var result: [NSSearchField] = []
 if let searchField = view as? NSSearchField {
   result.append(searchField)
 }
 for subview in view.subviews {
   result.append(contentsOf: extractSearchFields(from: subview))
 }
 return result
 }

 private func updateSubmenuTitles(in menu: NSMenu, matching titles: [String], to targetTitle: String) {
 for item in menu.items {
 if let submenu = item.submenu {
 if titles.contains(item.title) || titles.contains(submenu.title) {
 item.title = targetTitle
 submenu.title = targetTitle
 }
 updateSubmenuTitles(in: submenu, matching: titles, to: targetTitle)
 }
 }
 }

 private func updateAppMenu(in mainMenu: NSMenu, isChinese: Bool) {
 guard let appMenu = findSubmenu(in: mainMenu, titles: ["X-Reader"]) else { return }

 updateMenuItemTitles(
   in: appMenu,
   matching: ["关于 X-Reader", "About X-Reader"],
   to: isChinese ? "关于 X-Reader" : "About X-Reader"
 )
 updateMenuItemTitles(
   in: appMenu,
   matching: ["设置…", "偏好设置…", "Settings...", "Preferences..."],
   to: isChinese ? "设置…" : "Settings..."
 )
 updateMenuItemTitles(
   in: appMenu,
   matching: ["隐藏 X-Reader", "Hide X-Reader"],
   to: isChinese ? "隐藏 X-Reader" : "Hide X-Reader"
 )
 updateMenuItemTitles(
   in: appMenu,
   matching: ["隐藏其他", "Hide Others"],
   to: isChinese ? "隐藏其他" : "Hide Others"
 )
 updateMenuItemTitles(
   in: appMenu,
   matching: ["显示全部", "Show All"],
   to: isChinese ? "显示全部" : "Show All"
 )
 updateMenuItemTitles(
   in: appMenu,
   matching: ["退出 X-Reader", "Quit X-Reader"],
   to: isChinese ? "退出 X-Reader" : "Quit X-Reader"
 )
 }

 private func updateWindowMenu(in mainMenu: NSMenu, isChinese: Bool) {
 guard let windowMenu = findSubmenu(in: mainMenu, titles: ["窗口", "Window"]) else { return }

 updateMenuItemTitles(
   in: windowMenu,
   matching: ["最小化", "Minimize"],
   to: isChinese ? "最小化" : "Minimize"
 )
 updateMenuItemTitles(
   in: windowMenu,
   matching: ["缩放", "Zoom"],
   to: isChinese ? "缩放" : "Zoom"
 )
 updateMenuItemTitles(
   in: windowMenu,
   matching: ["前置全部窗口", "Bring All to Front"],
   to: isChinese ? "前置全部窗口" : "Bring All to Front"
 )
 }

private func cleanMenus(in mainMenu: NSMenu) {
 removeTopLevelMenu(in: mainMenu, titles: ["Edit", "编辑"])

 if let appMenu = findSubmenu(in: mainMenu, titles: ["X-Reader"]) {
   removeMenuItems(in: appMenu, titles: ["服务", "Services"], selectorNames: ["orderFrontServicesMenu:"])
 }

 if let viewMenu = findSubmenu(in: mainMenu, titles: ["显示", "视图", "View"]) {
   removeMenuItems(in: viewMenu, titles: [
     "显示标签页栏",
     "Show Tab Bar",
     "显示所有标签页",
     "Show All Tabs"
   ], selectorNames: [
     "toggleTabBar:",
     "showAllTabs:"
   ])
   collapseAdjacentSeparators(in: viewMenu)
 }

 if let windowMenu = findSubmenu(in: mainMenu, titles: ["窗口", "Window"]) {
   removeMenuItems(in: windowMenu, titles: [
     "从组中移除窗口",
     "Remove Window from Set",
     "前置全部窗口",
     "Bring All to Front",
     "显示上一个标签页",
     "Show Previous Tab",
     "显示前一个标签页",
     "Show Previous Tab",
     "显示下一个标签页",
     "Show Next Tab",
     "显示后一个标签页",
     "Show Next Tab",
     "将标签页移到新窗口",
     "Move Tab to New Window",
     "合并所有窗口",
     "Merge All Windows"
   ], selectorNames: [
     "arrangeInFront:",
     "selectPreviousTab:",
     "selectNextTab:",
     "moveTabToNewWindow:",
     "mergeAllWindows:"
   ], containsPatterns: [
     "移除窗口",
     "remove window",
     "前置全部窗口",
     "bring all to front",
     "上一个标签页",
     "previous tab",
     "下一个标签页",
     "next tab",
     "移到新窗口",
     "new window",
     "合并所有窗口",
     "merge all windows"
   ])
   collapseAdjacentSeparators(in: windowMenu)
 }

 if let helpMenu = findSubmenu(in: mainMenu, titles: ["帮助", "Help"]) {
   removeMenuItems(
     in: helpMenu,
     titles: ["反馈给 Apple", "Send Feedback to Apple"],
     selectorNames: ["showFeedbackPage:", "sendFeedback:", "sendFeedbackToApple:"],
     containsPatterns: ["feedback", "反馈", "apple"]
   )
   collapseAdjacentSeparators(in: helpMenu)
 }
 }

 private func findSubmenu(in mainMenu: NSMenu, titles: [String]) -> NSMenu? {
 for item in mainMenu.items {
   if titles.contains(item.title) {
     return item.submenu
   }
   if let submenu = item.submenu, titles.contains(submenu.title) {
     return submenu
   }
 }
 return nil
 }

 private func removeTopLevelMenu(in mainMenu: NSMenu, titles: [String]) {
   let removeIndices = mainMenu.items.enumerated().compactMap { idx, item in
     titles.contains(item.title) ? idx : nil
   }
   for idx in removeIndices.reversed() {
     mainMenu.removeItem(at: idx)
   }
 }

 private func removeMenuItems(
   in menu: NSMenu,
   titles: [String],
   selectorNames: [String] = [],
   containsPatterns: [String] = []
 ) {
 var indicesToRemove: [Int] = []
 for (index, item) in menu.items.enumerated() {
   let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
   let lowerTitle = normalizedTitle.lowercased()
   let actionName = item.action.map(NSStringFromSelector) ?? ""
   let lowerPatterns = containsPatterns.map { $0.lowercased() }

   let titleExactMatch = titles.contains(normalizedTitle)
   let selectorMatch = selectorNames.contains(actionName)
   let titleContainsMatch = lowerPatterns.allSatisfy { pattern in
     // pattern "apple" + "feedback" should both match if provided together
     pattern.isEmpty || lowerTitle.contains(pattern)
   } || lowerPatterns.contains { lowerTitle.contains($0) }

   if titleExactMatch || selectorMatch || titleContainsMatch {
     indicesToRemove.append(index)
   }
 }
 for index in indicesToRemove.reversed() {
   menu.removeItem(at: index)
 }
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
}

@MainActor
final class ReaderWindowManager: NSObject, NSWindowDelegate {
 static let shared = ReaderWindowManager()

 private var windowStates: [ObjectIdentifier: AppState] = [:]
 private var retainedWindows: [ObjectIdentifier: NSWindow] = [:]

 private override init() {
 super.init()
 }

 var activeAppState: AppState? {
   if let keyWindow = NSApp.keyWindow {
     return windowStates[ObjectIdentifier(keyWindow)]
   }
   if let mainWindow = NSApp.mainWindow {
     return windowStates[ObjectIdentifier(mainWindow)]
   }
   return nil
 }

 func register(window: NSWindow, appState: AppState) {
   let id = ObjectIdentifier(window)
   windowStates[id] = appState
   retainedWindows[id] = window
   window.delegate = self
 }

 func attachCurrentKeyWindowIfNeeded(appState: AppState) {
   if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
     register(window: window, appState: appState)
     return
   }

   DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
     self?.attachCurrentKeyWindowIfNeeded(appState: appState)
   }
 }

 func openNewWindow() {
   let newState = AppState()
   let rootView = MainView().environmentObject(newState)
   let hosting = NSHostingController(rootView: rootView)

   let window = NSWindow(contentViewController: hosting)
   window.title = "X-Reader"
   window.setContentSize(NSSize(width: 1200, height: 800))
   window.minSize = NSSize(width: 800, height: 600)
   window.titleVisibility = .hidden
   window.titlebarAppearsTransparent = true
   window.toolbar = nil
   window.collectionBehavior = [.fullScreenPrimary]
   window.makeKeyAndOrderFront(nil)

   register(window: window, appState: newState)
 }

 func windowWillClose(_ notification: Notification) {
   guard let window = notification.object as? NSWindow else { return }
   let id = ObjectIdentifier(window)
   windowStates.removeValue(forKey: id)
   retainedWindows.removeValue(forKey: id)
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
 ReaderWindowManager.shared.activeAppState?.persistSessionNow()
 NSApp.keyWindow?.miniaturize(nil)
 } else {
 // Quit app — set flag to prevent PDFView teardown from overwriting bookmark
 ReaderWindowManager.shared.activeAppState?.persistSessionNow()
 ReaderWindowManager.shared.activeAppState?.isTerminating = true
NSApp.terminate(nil)
   }
 }
}
}
