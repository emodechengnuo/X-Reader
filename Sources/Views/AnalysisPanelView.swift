//
//  AnalysisPanelView.swift
//  X-Reader
//
//  Right sidebar: Translation, Words, TTS
//


import SwiftUI
import Translation

struct AnalysisPanelView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @State private var selectedTab: AnalysisTab = .translation
    @AppStorage("speech_rate") private var speechRate: Float = 1.0
    // Apple Translation Session
    @State private var appleTranslationConfig: TranslationSession.Configuration?
    
    private func t(_ key: L10nKey) -> String { l10n.string(key) }
    
    enum AnalysisTab: String, CaseIterable {
        case translation = "translation"
        case words = "words"
        case tts = "tts"
        
        var icon: String {
            switch self {
            case .translation: return "character.book.closed"
            case .words: return "a.square"
            case .tts: return "speaker.wave.2"
            }
        }
        
        var l10nKey: L10nKey {
            switch self {
            case .translation: return .translationTab
            case .words: return .wordsTab
            case .tts: return .ttsTab
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(AnalysisTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(l10n.string(tab.l10nKey))
                                .font(.system(size: 11))
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(selectedTab == tab ? .white : .primary)
                        .background(
                            selectedTab == tab ? Color.accentColor : Color.clear
                        )
                        .cornerRadius(4)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !appState.selectedText.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t(.selectedText))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(appState.selectedText)
                                .font(.callout)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                                )
                        }
                    }
                    
                    switch selectedTab {
                    case .translation:
                        TranslationTabContent()
                    case .words:
                        WordsTabContent()
                    case .tts:
                        TTSTabContent(speechRate: $speechRate)
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .translationTask(appleTranslationConfig) { session in
            appState.translationService.setAppleSession(session)
        }
        .onAppear {
            // 初始化 Apple Translation session（英文→中文）
            appleTranslationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans")
            )
        }
    }
}

// MARK: - Translation Tab

struct TranslationTabContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @AppStorage("translation_engine") private var translationEngineRaw: String = "google"
    
    private func t(_ key: L10nKey) -> String { l10n.string(key) }
    
    private var engines: [TranslationService.Engine] { TranslationService.Engine.allCases }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            // ── 引擎快速切换 ──
            VStack(alignment: .leading, spacing: 4) {
                Text(t(.engineLabel))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    ForEach(engines) { engine in
                        let isSelected = translationEngineRaw == engine.rawValue
                        Button(action: {
                            translationEngineRaw = engine.rawValue
                            // 立刻用新引擎重新翻译
                            if !appState.selectedText.isEmpty {
                                Task { await appState.translateSelectedText() }
                            }
                        }) {
                            Text(engineShortName(engine))
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? .white : .primary)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity)
                                .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            
            // ── 翻译结果 ──
            if appState.isTranslating {
                HStack {
                    ProgressView()
                    Text(t(.translating))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if !appState.translatedText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "character.book.closed")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Text(t(.translatedResult))
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    
                    Text(appState.translatedText)
                        .font(.body)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .lineSpacing(4)
                    
                    // Show fallback note (e.g. "[谷歌在线 失败，已自动切换至 苹果本地]")
                    if !appState.translationError.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                            Text(appState.translationError)
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } else if !appState.translationError.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text(t(.translationError))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    
                    Text(appState.translationError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.05))
                        .cornerRadius(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if !appState.selectedText.isEmpty {
                Text(t(.translationLoading))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text(t(.selectTextHint))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }
    
    /// 面板切换按钮短名称（与设置页一致）
    private func engineShortName(_ engine: TranslationService.Engine) -> String {
        engine.displayName(lang: l10n.language)
    }
}

// MARK: - Words Tab

struct WordsTabContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    
    private func t(_ key: L10nKey) -> String { l10n.string(key) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "a.square")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(t(.wordList))
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(appState.wordAnalysis?.wordDetails.count ?? 0) \(t(.wordCount))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if let analysis = appState.wordAnalysis {
                ForEach(analysis.wordDetails.indices, id: \.self) { idx in
                    let word = analysis.wordDetails[idx]
                    WordCardView(
                        word: word,
                        onEditMeaning: { newMeaning in
                            // Update the meaning in the analysis
                            appState.wordAnalysis?.wordDetails[idx].meaning = newMeaning.isEmpty ? nil : newMeaning
                            // Persist to cache
                            if !newMeaning.isEmpty {
                                appState.wordTranslationCache.setTranslationForWord(newMeaning, for: word.word)
                            }
                        }
                    )
                }
            } else {
                Text(t(.wordsHint))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
    }
}

// MARK: - TTS Tab

struct TTSTabContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @Binding var speechRate: Float
    
    private func t(_ key: L10nKey) -> String { l10n.string(key) }
    
    private var availableVoices: [TTSService.VoiceOption] {
        TTSService.allVoices
    }
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(t(.voiceEngine))
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                
                Picker("", selection: Binding(
                    get: { appState.selectedVoiceId },
                    set: { newId in
                        appState.selectedVoiceId = newId
                        if let voice = availableVoices.first(where: { $0.id == newId }) {
                            appState.selectedVoiceName = voice.name
                        }
                    }
                )) {
                    ForEach(availableVoices) { voice in
                        HStack(spacing: 4) {
                            Text(voice.name)
                                .lineLimit(1)
                            Text(voice.quality)
                                .font(.system(size: 8))
                                .foregroundColor(voice.quality.contains("⭐") ? .orange : .secondary)
                        }
                        .tag(voice.id)
                    }
                }
                .labelsHidden()
                
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(t(.ttsVoiceHint))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "tortoise")
                        .font(.caption)
                    SpeedSliderFloat(value: $speechRate, range: 0.1...3.0)
                        .frame(maxWidth: .infinity)
                    Image(systemName: "hare")
                        .font(.caption)
                }
                HStack(spacing: 2) {
                    Text("语速")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1fx", speechRate))
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                        .monospacedDigit()
                }
            }
            
            if appState.selectedText.isEmpty {
                Text(t(.ttsHint))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }
}

// MARK: - Supporting Views

struct WordCardView: View {
    @State private var isEditing = false
    @State private var editedText: String = ""
    
    let word: WordDetail
    var onEditMeaning: ((String) -> Void)?
    
    private var tagColor: Color {
        switch word.pos {
        case "名词": return .blue
        case "动词": return .green
        case "形容词": return .orange
        case "副词": return .purple
        case "代词": return .red
        case "介词": return .cyan
        case "连词": return .indigo
        case "限定词": return .teal
        case "感叹词": return .pink
        case "助词": return .mint
        case "量词": return .brown
        case "习语": return .yellow
        case "引号", "左括号", "右括号", "破折号": return .gray
        default: return .gray
        }
    }
    
    private var shouldShowMeaning: Bool {
        guard let m = word.meaning, !m.isEmpty else { return false }
        // Don't show if it's just repeating the word/lemma
        return m.lowercased() != word.word.lowercased() &&
               m.lowercased() != word.lemma.lowercased()
    }
    
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.word)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                HStack(spacing: 6) {
                    // POS tag with color
                    Text(word.pos)
                        .font(.system(size: 9))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tagColor)
                        .cornerRadius(4)
                    
                    // Difficulty badge
                    Text(word.difficulty)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            // Meaning display / edit area
            if isEditing {
                TextField("编辑翻译", text: $editedText, onCommit: {
                    confirmEdit()
                })
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
                .frame(minWidth: 60, maxWidth: 150)
                .onAppear { editedText = word.meaning ?? "" }
            } else if shouldShowMeaning {
                Text(word.meaning ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .onTapGesture(count: 2) {
                        isEditing = true
                        editedText = word.meaning ?? ""
                    }
                    .contextMenu {
                        Button("编辑翻译") { isEditing = true; editedText = word.meaning ?? "" }
                        Divider()
                        Button(role: .destructive) {
                            onEditMeaning?("")
                            isEditing = false
                        } label: {
                            Label("清除翻译", systemImage: "trash")
                        }
                    }
            } else {
                // No translation yet — show placeholder with tap-to-edit
                Text("+ 添加翻译")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
                    .onTapGesture(count: 2) {
                        isEditing = true
                        editedText = ""
                    }
            }
            
            // Edit confirmation button (only visible while editing)
            if isEditing {
                Button(action: confirmEdit) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                Button(action: { isEditing = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isEditing ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isEditing ? 1.5 : 1)
        )
    }
    
    private func confirmEdit() {
        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        onEditMeaning?(trimmed)
        isEditing = false
    }
}

struct POSTagView: View {
    let word: String
    let pos: String
    let lemma: String
    
    private var tagColor: Color {
        switch pos {
        case "名词": return .blue
        case "动词": return .green
        case "形容词": return .orange
        case "副词": return .purple
        case "代词": return .red
        case "介词": return .cyan
        case "连词": return .indigo
        case "限定词": return .teal
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(spacing: 2) {
            Text(word)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack(spacing: 4) {
                Text(pos)
                    .font(.system(size: 9))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(tagColor)
                    .cornerRadius(3)
            }
            if lemma.lowercased() != word.lowercased() {
                Text(lemma)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(4)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(tagColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                 proposal: ProposedViewSize(result.sizes[index]))
        }
    }
    
    private struct LayoutResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var size: CGSize = .zero
    }
    
    private func layout(in width: CGFloat, subviews: Subviews) -> LayoutResult {
        var result = LayoutResult()
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = width == 0 ? .infinity : width
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            result.positions.append(CGPoint(x: currentX, y: currentY))
            result.sizes.append(size)
            
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        
        result.size = CGSize(width: maxWidth == .infinity ? currentX : maxWidth, height: currentY + lineHeight)
        return result
    }
}
