//
//  SettingsView.swift
//  X-Reader
//
//  Settings window
//


import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @AppStorage("app_language") private var appLanguage: String = AppLanguage.chinese.rawValue
    @AppStorage("speech_rate") private var speechRate: Double = 1.0
    @AppStorage("default_voice") private var defaultVoice = "american"
    @AppStorage("auto_ocr") private var autoOCR = false
    @AppStorage("close_as_minimize") private var closeAsMinimize = false
    
    // Translation engine & Baidu config — bind directly to UserDefaults
    @AppStorage("translation_engine") private var translationEngineRaw: String = "google"
    @AppStorage("baidu_app_id") private var baiduAppId: String = ""
    @AppStorage("baidu_secret_key") private var baiduSecretKey: String = ""
    
    // Baidu test state
    @State private var isTestingBaidu: Bool = false
    @State private var baiduTestResult: String = ""
    
    private let engines = TranslationService.Engine.allCases
    
    private func t(_ key: L10nKey) -> String { l10n.string(key) }
    
    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label(t(.generalSettings), systemImage: "gear")
                }
            
            translationSettings
                .tabItem {
                    Label(t(.translationSettings), systemImage: "character.book.closed")
                }
            
            speechSettings
                .tabItem {
                    Label(t(.speechSettings), systemImage: "speaker.wave.2")
                }
        }
        .frame(width: 480, height: 520)
        .onAppear {
            syncLanguage()
        }
        .onChange(of: appLanguage) { _, _ in
            syncLanguage()
        }
    }
    
    private func syncLanguage() {
        let lang = AppLanguage(rawValue: appLanguage) ?? .chinese
        if L10n.shared.language != lang {
            // Save current page before language change to prevent jump-to-page-1
            let savedPage = appState.currentPage
            appState.saveHiddenBookmark()

            withAnimation(.easeInOut(duration: 0.2)) {
                L10n.shared.language = lang
            }

            // Restore page position after SwiftUI finishes re-rendering
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard appState.document != nil else { return }
                appState.goToPage(savedPage)
            }
        }
    }
    
    // MARK: - General Settings
    
    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // --- Language ---
                VStack(alignment: .leading, spacing: 8) {
                    Text(t(.languageSetting))
                        .font(.headline)
                    
                    Picker("", selection: $appLanguage) {
                        Text("中文").tag(AppLanguage.chinese.rawValue)
                        Text("English").tag(AppLanguage.english.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }
                
                Divider()
                
                // --- Theme ---
                VStack(alignment: .leading, spacing: 8) {
                    Text(t(.appearanceSetting))
                        .font(.headline)
                    
                    HStack(spacing: 6) {
                        ForEach(AppState.ThemeMode.allCases, id: \.self) { mode in
                            Button(action: { appState.setThemeMode(mode) }) {
                                VStack(spacing: 4) {
                                    Image(systemName: mode.icon)
                                        .font(.title3)
                                    Text(t(themeKey(for: mode)))
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(appState.themeMode == mode ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                .foregroundColor(appState.themeMode == mode ? .white : .primary)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(appState.themeMode == mode ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Divider()
                
                // --- OCR ---
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(t(.ocrAutoSetting), isOn: $autoOCR)
                }
                
                Divider()
                
                // --- Close button ---
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(t(.closeAsMinimizeSetting), isOn: $closeAsMinimize)
                }
                
                Divider()
                
                // --- Cache ---
                Button {
                    appState.cacheManager.clearCache()
                    appState.wordTranslationCache.clearCache()
                } label: {
                    Label(t(.cacheClear), systemImage: "trash")
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Translation Settings (NEW)

    private var translationSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // --- Engine picker ---
                VStack(alignment: .leading, spacing: 8) {
                    Text(t(.selectEngine))
                        .font(.headline)
                    
                    Picker("", selection: $translationEngineRaw) {
                        ForEach(engines) { engine in
                            Text(engine.fullDisplayName(lang: l10n.language)).tag(engine.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                    
                    Text(t(.translationHint))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // --- Google 翻译说明 ---
                if translationEngineRaw == "google" {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(t(.googleEngine))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text(t(.googleEngineHint))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // --- Apple 翻译说明 ---
                if translationEngineRaw == "apple" {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(t(.appleEngine))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text(t(.appleEngineHint))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // --- Baidu configuration ---
                if translationEngineRaw == "baidu" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(t(.baiduConfig))
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(t(.baiduAppId))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("", text: $baiduAppId)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(t(.baiduSecretKey))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            SecureField("", text: $baiduSecretKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack(spacing: 8) {
                            Button(action: testBaiduAPI) {
                                HStack(spacing: 4) {
                                    if isTestingBaidu {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .frame(width: 12, height: 12)
                                    } else {
                                        Image(systemName: "checkmark.circle")
                                    }
                                    Text(l10n.language == .chinese ? "测试连接" : "Test Connection")
                                }
                            }
                            .disabled(baiduAppId.isEmpty || baiduSecretKey.isEmpty || isTestingBaidu)
                            
                            if !baiduTestResult.isEmpty {
                                Text(baiduTestResult)
                                    .font(.caption)
                                    .foregroundColor(baiduTestResult.contains("成功") || baiduTestResult.contains("OK") ? .green : .red)
                                    .lineLimit(2)
                            }
                        }
                        
                        HStack {
                            Text(t(.baiduConfigHint))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Link(t(.baiduRegister), destination: URL(string: "https://fanyi-api.baidu.com/")!)
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Speech Settings
    
    private var speechSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // --- Kokoro TTS model status ---
                VStack(alignment: .leading, spacing: 8) {
                    Text(t(.kokoroSpeech))
                        .font(.headline)
                    
                    HStack {
                        Label(t(.modelStatus), systemImage: "cpu")
                        Spacer()
                        Text(appState.ttsService.kokoroStatus)
                            .font(.caption)
                            .foregroundColor(appState.ttsService.isKokoroReady ? .green : .secondary)
                    }
                    
                    if !appState.ttsService.isKokoroReady && appState.ttsService.kokoroStatus.contains("加载中") {
                        ProgressView(value: appState.ttsService.kokoroProgress)
                            .tint(.accentColor)
                    }
                    
                    if !appState.ttsService.isKokoroReady {
                        Button(t(.reloadModel)) {
                            Task {
                                await appState.ttsService.loadKokoroModel()
                            }
                        }
                    }
                    
                    Text(t(.kokoroDesc))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // --- Speed ---
                VStack(alignment: .leading, spacing: 8) {
                    Text(t(.speed))
                        .font(.headline)
                    
                    HStack {
                        Text(t(.slow))
                        Slider(value: $speechRate, in: 0.1...2.0, step: 0.05)
                        Text(t(.fast))
                        Text(String(format: "%.1fx", speechRate))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                
                Divider()
                
                // --- Default voice accent ---
                VStack(alignment: .leading, spacing: 8) {
                    Text(t(.defaultVoiceSetting))
                        .font(.headline)
                    
                    Picker(t(.defaultAccent), selection: $defaultVoice) {
                        Text(t(.americanEnglish)).tag("american")
                        Text(t(.britishEnglish)).tag("british")
                    }
                    .pickerStyle(.segmented)
                    
                    Text(t(.voicePanelHint))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
        }
    }
    
    private func themeKey(for mode: AppState.ThemeMode) -> L10nKey {
        switch mode {
        case .light: return .themeLight
        case .dark: return .themeDark
        case .system: return .themeSystem
        }
    }
    
    private func testBaiduAPI() {
        isTestingBaidu = true
        baiduTestResult = ""
        
        // Sync UserDefaults first
        appState.translationService.baiduAppId = baiduAppId
        appState.translationService.baiduSecretKey = baiduSecretKey
        
        Task {
            let result = await appState.translationService.translateWithFeedback("hello")
            await MainActor.run {
                isTestingBaidu = false
                let isChinese = L10n.shared.language == .chinese
                if let error = result.error {
                    baiduTestResult = isChinese ? "失败: \(error)" : "Failed: \(error)"
                } else if !result.text.isEmpty {
                    baiduTestResult = isChinese ? "成功! hello → \(result.text)" : "OK! hello → \(result.text)"
                } else {
                    baiduTestResult = isChinese ? "失败: 无翻译结果" : "Failed: empty result"
                }
            }
        }
    }
}

// MARK: - Speed Slider with Default Tick Mark
