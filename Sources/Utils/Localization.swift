//
//  Localization.swift
//  X-Reader
//
//  Multi-language support (Chinese / English) - all views auto-refresh on change
//


import SwiftUI

// MARK: - App Languages

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh"
    case english = "en"
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
    
    /// Detect system language
    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "zh"
        return preferred.hasPrefix("zh") ? .chinese : .english
    }
}

// MARK: - Localization Keys

enum L10nKey: String, CaseIterable {
    // Toolbar help texts
    case openPdfHelp = "open_pdf_help"
    case search = "search"
    case searchHelp = "search_help"
    case zoomOutHelp = "zoom_out_help"
    case zoomInHelp = "zoom_in_help"
    case resetZoomHelp = "reset_zoom_help"
    case bookmarkHelp = "bookmark_help"
    case ocrHelp = "ocr_help"
    case toggleSidebarHelp = "toggle_sidebar_help"
    case toggleAnalysisHelp = "toggle_analysis_help"
    case fullscreenHelp = "fullscreen_help"
    case themeHelp = "theme_help"
    case deleteBookmark = "delete_bookmark"
    
    // Menu commands
    case openPDF = "open_pdf"
    case fullscreen = "fullscreen"
    
    // Sidebar tabs
    case tocTab = "toc_tab"
    case bookmarksTab = "bookmarks_tab"
    
    // Analysis panel tabs
    case translationTab = "translation_tab"
    case grammarTab = "grammar_tab"
    case wordsTab = "words_tab"
    case ttsTab = "tts_tab"
    
    // Translation panel
    case selectedText = "selected_text"
    case translating = "translating"
    case translationLoading = "translation_loading"
    case selectTextHint = "select_text_hint"
    case translatedResult = "translated_result"
    case engineLabel = "engine_label"
    case googleEngine = "google_engine"
    
    // Grammar panel
    case sentenceStructure = "sentence_structure"
    case subject = "subject"
    case predicate = "predicate"
    case object = "object"
    case complement = "complement"
    case adverbial = "adverbial"
    case posTagging = "pos_tagging"
    case analyzing = "analyzing"
    case analyzeHint = "analyze_hint"
    
    // Words panel
    case wordList = "word_list"
    case wordCount = "word_count"
    case wordsHint = "words_hint"
    
    // TTS panel
    case voiceEngine = "voice_engine"
    case speed = "speed"
    case slow = "slow"
    case fast = "fast"
    case ttsHint = "tts_hint"
    case ttsVoiceHint = "tts_voice_hint"
    case speaking = "speaking"
    
    // Settings tabs
    case generalSettings = "general_settings"
    case translationSettings = "translation_settings"
    case speechSettings = "speech_settings"
    
    // General settings
    case languageSetting = "language_setting"
    case interfaceLanguage = "interface_language"
    case languageRestartHint = "language_restart_hint"
    case appearanceSetting = "appearance_setting"
    case themeSetting = "theme_setting"
    case themeLight = "theme_light"
    case themeDark = "theme_dark"
    case themeSystem = "theme_system"
    case ocrAutoSetting = "ocr_auto_setting"
    case closeAsMinimizeSetting = "close_as_minimize_setting"
    case cacheClear = "cache_clear"
    case ocrSection = "ocr_section"
    
    // Translation settings
    case translationEngine = "translation_engine"
    case selectEngine = "select_engine"
    case translationHint = "translation_hint"
    case baiduConfig = "baidu_config"
    case baiduAppId = "baidu_appid"
    case baiduSecretKey = "baidu_secretkey"
    case baiduConfigHint = "baidu_config_hint"
    case baiduRegister = "baidu_register"
    case baiduNotConfigured = "baidu_not_configured"
    case engineAutoFallback = "engine_auto_fallback"
    
    // Speech settings
    case kokoroSpeech = "kokoro_speech"
    case modelStatus = "model_status"
    case reloadModel = "reload_model"
    case kokoroDesc = "kokoro_desc"
    case defaultVoiceSetting = "default_voice_setting"
    case defaultAccent = "default_accent"
    case americanEnglish = "american_english"
    case britishEnglish = "british_english"
    case voicePanelHint = "voice_panel_hint"
    
    // Status bar
    case noFile = "no_file"
    case pageInfo = "page_info"
    case analysisOn = "analysis_on"
    
    // Welcome view
    case welcomeTitle = "welcome_title"
    case welcomeSubtitle = "welcome_subtitle"
    case featureOCR = "feature_ocr"
    case featureToc = "feature_toc"
    case featureTTS = "feature_tts"
    case featureTranslate = "feature_translate"
    case featureGrammar = "feature_grammar"
    case openButton = "open_button"
    
    // Bookmarks & TOC
    case noBookmarks = "no_bookmarks"
    case addBookmarkHint = "add_bookmark_hint"
    case pageN = "page_n"
    case noToc = "no_toc"
    case noTocHint = "no_toc_hint"
    case noMatches = "no_matches"
    case searchPlaceholder = "search_placeholder"
    
    // Search
    case searchPdfPlaceholder = "search_pdf_placeholder"
    case searchNoResults = "search_no_results"
    case searchPrevious = "search_previous"
    case searchNext = "search_next"
    
    // Context menu
    case copyText = "copy_text"
    case translateText = "translate_text"
    case speakText = "speak_text"
    case analyzeText = "analyze_text"
    case bookmarkPage = "bookmark_page"
    case highlightHelp = "highlight_help"
    case clearAllHighlightsTitle = "clear_all_highlights_title"
    case clearAllHighlightsMessage = "clear_all_highlights_message"
    case clearAllHighlightsHelp = "clear_all_highlights_help"
    case clearButton = "clear_button"
    case cancelButton = "cancel_button"
    case noTextSelectedTitle = "no_text_selected_title"
    case noTextSelectedMessage = "no_text_selected_message"
    
    // File dialog
    case selectPdfFile = "select_pdf_file"
}

// MARK: - Localization System (ObservableObject)

class L10n: ObservableObject {
    static let shared = L10n()
    
    @Published var language: AppLanguage = .chinese
    
    func string(_ key: L10nKey) -> String {
        switch language {
        case .chinese:
            return zhStrings[key.rawValue] ?? key.rawValue
        case .english:
            return enStrings[key.rawValue] ?? key.rawValue
        }
    }
    
    // Convenience: use from Views (still works for non-reactive contexts)
    static func t(_ key: L10nKey) -> String {
        shared.string(key)
    }
    
    // MARK: - Chinese strings
    
    private let zhStrings: [String: String] = [
        // Toolbar help
        "open_pdf_help": "打开 PDF (⌘O)",
        "search": "搜索",
        "search_help": "搜索 PDF (⌘F)",
        "zoom_out_help": "缩小",
        "zoom_in_help": "放大",
        "reset_zoom_help": "重置缩放",
        "bookmark_help": "添加书签 (⌘D)",
        "ocr_help": "OCR 识别",
        "toggle_sidebar_help": "显示/隐藏目录",
        "toggle_analysis_help": "分析面板",
        "fullscreen_help": "全屏 (⌃⌘F)",
        "theme_help": "切换主题",
        "delete_bookmark": "删除书签",
        
        // Menu
        "open_pdf": "打开 PDF...",
        "fullscreen": "全屏",
        
        // Sidebar
        "toc_tab": "目录",
        "bookmarks_tab": "书签",
        
        // Analysis tabs
        "translation_tab": "翻译",
        "grammar_tab": "语法",
        "words_tab": "单词",
        "tts_tab": "朗读",
        
        // Translation
        "selected_text": "选中文本",
        "translating": "正在翻译...",
        "translation_loading": "翻译加载中...",
        "select_text_hint": "选中文字后将显示翻译",
        "translated_result": "中文翻译",
        "engine_label": "引擎",
        "google_engine": "Google 翻译",
        
        // Grammar
        "sentence_structure": "句子结构",
        "subject": "主语",
        "predicate": "谓语",
        "object": "宾语",
        "complement": "补语",
        "adverbial": "状语",
        "pos_tagging": "词性标注",
        "analyzing": "正在分析...",
        "analyze_hint": "选中文字后将显示语法分析",
        
        // Words
        "word_list": "单词列表",
        "word_count": "个单词",
        "words_hint": "选中文字后将显示单词列表",
        
        // TTS
        "voice_engine": "语音引擎",
        "speed": "语速",
        "slow": "慢",
        "fast": "快",
        "tts_hint": "选中文字后点击播放即可朗读",
        "tts_voice_hint": "带「⭐」标记的为 Kokoro AI 语音，纯 CoreML 离线引擎。",
        "speaking": "朗读中...",
        
        // Settings
        "general_settings": "通用",
        "translation_settings": "翻译",
        "speech_settings": "朗读",
        
        // General
        "language_setting": "语言",
        "interface_language": "界面语言",
        "language_restart_hint": "更改后立即生效",
        "appearance_setting": "外观",
        "theme_setting": "主题",
        "theme_light": "浅色",
        "theme_dark": "深色",
        "theme_system": "跟随系统",
        "ocr_auto_setting": "打开 PDF 时自动 OCR",
        "close_as_minimize_setting": "关闭窗口时最小化到 Dock（而非退出）",
        "cache_clear": "清除翻译缓存",
        "ocr_section": "OCR",
        
        // Translation settings
        "translation_engine": "翻译引擎",
        "select_engine": "选择引擎",
        "translation_hint": "Google 翻译无需配置；百度翻译需注册获取 API Key",
        "baidu_config": "百度翻译配置",
        "baidu_appid": "App ID",
        "baidu_secretkey": "密钥 (Secret Key)",
        "baidu_config_hint": "前往百度翻译开放平台注册，获取免费 API Key（每月 5~100万字符免费）",
        "baidu_register": "前往注册 →",
        "baidu_not_configured": "百度翻译未配置",
        "engine_auto_fallback": "翻译失败时自动切换引擎",
        
        // Speech
        "kokoro_speech": "Kokoro AI 语音",
        "model_status": "模型状态",
        "reload_model": "重新加载模型",
        "kokoro_desc": "Kokoro 是本地 AI 语音引擎，纯 CoreML 实现，完全离线运行。首次约 99MB，54 种声音。选择带「Kokoro AI ⭐」标记的声音即可使用。",
        "default_voice_setting": "默认语音",
        "default_accent": "默认发音",
        "american_english": "美式英语 (en-US)",
        "british_english": "英式英语 (en-GB)",
        "voice_panel_hint": "在分析面板可切换更多声音",
        
        // Status
        "no_file": "未打开文件",
        "page_info": "第 %d / %d 页",
        "analysis_on": "分析面板已开启",
        
        // Welcome
        "welcome_title": "X-Reader",
        "welcome_subtitle": "英文 PDF 智能阅读器",
        "feature_ocr": "自动识别扫描版 PDF 文字",
        "feature_toc": "自动生成章节目录",
        "feature_tts": "点击句子自动朗读英文",
        "feature_translate": "整句翻译 + 单词释义",
        "feature_grammar": "词性标注、句子结构拆解",
        "open_button": "打开 PDF 文件",
        
        // Bookmarks & TOC
        "no_bookmarks": "暂无书签",
        "add_bookmark_hint": "使用工具栏添加书签",
        "page_n": "第 %d 页",
        "no_toc": "无目录",
        "no_toc_hint": "部分 PDF 可能没有内嵌目录",
        "no_matches": "无匹配结果",
        "search_placeholder": "搜索目录...",
        
        // Search
        "search_pdf_placeholder": "搜索 PDF...",
        "search_no_results": "无结果",
        "search_previous": "上一个",
        "search_next": "下一个",
        
        // Context menu
        "copy_text": "复制",
        "translate_text": "翻译",
        "speak_text": "朗读",
        "analyze_text": "语法分析",
        "bookmark_page": "添加书签",
        
        // Highlight / Annotation
        "highlights_tab": "标注",
        "no_highlights": "暂无标注",
        "no_highlights_hint": "选中文本后点击荧光笔工具添加标注",
        "highlight_help": "荧光笔标注 (选中文字后自动添加)",
        "clear_all_highlights_title": "清除所有高亮",
        "clear_all_highlights_message": "确定要清除文档中的所有荧光笔标注吗？此操作无法撤销。",
        "clear_all_highlights_help": "清除所有荧光笔标注",
        "clear_button": "清除",
        "cancel_button": "取消",
        "no_text_selected_title": "未选中文字",
        "no_text_selected_message": "请先选中要高亮的文字，然后再选择颜色。",
        "select_color": "颜色：",

        // File dialog
        "select_pdf_file": "选择 PDF 文件",
    ]
    
    // MARK: - English strings
    
    private let enStrings: [String: String] = [
        // Toolbar help
        "open_pdf_help": "Open PDF (⌘O)",
        "search": "Search",
        "search_help": "Search PDF (⌘F)",
        "zoom_out_help": "Zoom Out",
        "zoom_in_help": "Zoom In",
        "reset_zoom_help": "Reset Zoom",
        "bookmark_help": "Bookmark (⌘D)",
        "ocr_help": "OCR",
        "toggle_sidebar_help": "Toggle Sidebar",
        "toggle_analysis_help": "Analysis Panel",
        "fullscreen_help": "Fullscreen (⌃⌘F)",
        "theme_help": "Theme",
        "delete_bookmark": "Delete Bookmark",
        
        // Menu
        "open_pdf": "Open PDF...",
        "fullscreen": "Fullscreen",
        
        // Sidebar
        "toc_tab": "TOC",
        "bookmarks_tab": "Bookmarks",
        
        // Analysis tabs
        "translation_tab": "Translate",
        "grammar_tab": "Grammar",
        "words_tab": "Words",
        "tts_tab": "Speech",
        
        // Translation
        "selected_text": "Selected Text",
        "translating": "Translating...",
        "translation_loading": "Translation loading...",
        "select_text_hint": "Select text to see translation",
        "translated_result": "Chinese Translation",
        "engine_label": "Engine",
        "google_engine": "Google Translate",
        
        // Grammar
        "sentence_structure": "Sentence Structure",
        "subject": "Subject",
        "predicate": "Predicate",
        "object": "Object",
        "complement": "Complement",
        "adverbial": "Adverbial",
        "pos_tagging": "POS Tags",
        "analyzing": "Analyzing...",
        "analyze_hint": "Select text to see grammar analysis",
        
        // Words
        "word_list": "Word List",
        "word_count": "words",
        "words_hint": "Select text to see word list",
        
        // TTS
        "voice_engine": "Voice Engine",
        "speed": "Speed",
        "slow": "Slow",
        "fast": "Fast",
        "tts_hint": "Select text then press play to listen",
        "tts_voice_hint": "⭐ marks Kokoro AI voices — CoreML offline engine.",
        "speaking": "Speaking...",
        
        // Settings
        "general_settings": "General",
        "translation_settings": "Translation",
        "speech_settings": "Speech",
        
        // General
        "language_setting": "Language",
        "interface_language": "Interface Language",
        "language_restart_hint": "Takes effect immediately",
        "appearance_setting": "Appearance",
        "theme_setting": "Theme",
        "theme_light": "Light",
        "theme_dark": "Dark",
        "theme_system": "System",
        "ocr_auto_setting": "Auto OCR when opening PDF",
        "close_as_minimize_setting": "Minimize to Dock when closing window (instead of quitting)",
        "cache_clear": "Clear Translation Cache",
        "ocr_section": "OCR",
        
        // Translation settings
        "translation_engine": "Translation Engine",
        "select_engine": "Select Engine",
        "translation_hint": "Google: no config needed; Baidu: requires API key registration",
        "baidu_config": "Baidu Translate Config",
        "baidu_appid": "App ID",
        "baidu_secretkey": "Secret Key",
        "baidu_config_hint": "Register at Baidu Translate Open Platform for free API Key (50K~1M chars/month free)",
        "baidu_register": "Register →",
        "baidu_not_configured": "Baidu not configured",
        "engine_auto_fallback": "Auto fallback on failure",
        
        // Speech
        "kokoro_speech": "Kokoro AI Speech",
        "model_status": "Model Status",
        "reload_model": "Reload Model",
        "kokoro_desc": "Kokoro is a local AI speech engine built on CoreML, fully offline. ~99MB first download, 54 voices. Select voices marked \"Kokoro AI ⭐\".",
        "default_voice_setting": "Default Voice",
        "default_accent": "Default Accent",
        "american_english": "American English (en-US)",
        "british_english": "British English (en-GB)",
        "voice_panel_hint": "More voices available in analysis panel",
        
        // Status
        "no_file": "No file open",
        "page_info": "Page %d / %d",
        "analysis_on": "Analysis panel active",
        
        // Welcome
        "welcome_title": "X-Reader",
        "welcome_subtitle": "Smart English PDF Reader",
        "feature_ocr": "OCR recognition for scanned PDFs",
        "feature_toc": "Auto-generate table of contents",
        "feature_tts": "Click sentences to read aloud",
        "feature_translate": "Full-sentence translation + definitions",
        "feature_grammar": "POS tagging, sentence structure breakdown",
        "open_button": "Open PDF File",
        
        // Bookmarks & TOC
        "no_bookmarks": "No bookmarks",
        "add_bookmark_hint": "Use toolbar to add bookmarks",
        "page_n": "Page %d",
        "no_toc": "No TOC",
        "no_toc_hint": "Some PDFs may not have embedded TOC",
        "no_matches": "No matches",
        "search_placeholder": "Search TOC...",
        
        // Search
        "search_pdf_placeholder": "Search PDF...",
        "search_no_results": "No results",
        "search_previous": "Previous",
        "search_next": "Next",
        
        // Context menu
        "copy_text": "Copy",
        "translate_text": "Translate",
        "speak_text": "Speak",
        "analyze_text": "Analyze",
        "bookmark_page": "Bookmark",
        "highlight_help": "Highlight selected text using color buttons",
        "clear_all_highlights_title": "Clear All Highlights",
        "clear_all_highlights_message": "Are you sure you want to clear all highlight annotations in this document? This action cannot be undone.",
        "clear_all_highlights_help": "Clear all highlight annotations",
        "clear_button": "Clear",
        "cancel_button": "Cancel",
        "no_text_selected_title": "No Text Selected",
        "no_text_selected_message": "Please select text first, then choose a highlight color.",
        
        // File dialog
        "select_pdf_file": "Select PDF File",
    ]
}

// MARK: - View modifier for reactive i18n

struct L10nReactive: ViewModifier {
    @ObservedObject var l10n = L10n.shared
    
    func body(content: Content) -> some View {
        content
            .id(l10n.language)  // Force re-render on language change
    }
}

extension View {
    /// Attach to any view to make it re-render when language changes
    func localized() -> some View {
        modifier(L10nReactive())
    }
}
