//
//  AnalysisPanelView.swift
//  X-Reader
//
//  Right sidebar: Translation, Words, TTS
//


import SwiftUI
import Translation

// MARK: - 自定义刻度滑块：刻度与滑轨底部齐平
struct SliderWithTicks: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var onChanged: ((Double) -> Void)? = nil

    private let tickCount = 8  // 刻度数
    private let trackHeight: CGFloat = 8
    private let tickLength: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumbX = normalizedValue * trackWidth

            ZStack(alignment: .leading) {
                // 滑轨背景
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: trackHeight)
                    .padding(.vertical, tickLength)  // 上下留出刻度空间

                // 刻度线
                ForEach(0..<tickCount, id: \.self) { i in
                    let t = Double(i) / Double(tickCount - 1)
                    let x = t * trackWidth - 0.5  // 0.5pt 线宽居中

                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 1, height: tickLength)
                        Spacer()
                    }
                    .frame(width: trackWidth, height: trackHeight + tickLength * 2)
                    .offset(x: x)
                }

                // 选中滑轨（左边填充）
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: thumbX, height: trackHeight)
                    .padding(.vertical, tickLength)

                // 滑块（thumb）
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .offset(x: thumbX - 7)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let clamped = min(max(gesture.location.x / trackWidth, 0), 1)
                                let raw = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                                // 按 step 吸附
                                let snapped = round(raw / step) * step
                                let newValue = min(max(snapped, range.lowerBound), range.upperBound)
                                if newValue != value {
                                    value = newValue
                                    onChanged?(newValue)
                                }
                            }
                    )
            }
        }
        .frame(height: 20 + tickLength * 2)
    }
}

struct AnalysisPanelView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @State private var selectedTab: AnalysisTab = .translation
    @State private var wordsSearchQuery: String = ""
    @State private var wordsMinimumLevel: CEFRLevel = .a1
    @State private var translationMinimumLevel: CEFRLevel = .a1
    @AppStorage("speech_rate") private var speechRate: Double = 1.0
    // Apple Translation session — uses Locale.Language(languageCode:) which is stable
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
                    if selectedTab != .words && !appState.selectedText.isEmpty {
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
                        TranslationTabContent(
                            minimumWordLevel: $translationMinimumLevel
                        )
                            .environmentObject(appState.translationService)
                    case .words:
                        WordsTabContent(
                            wordSearchQuery: $wordsSearchQuery,
                            minimumWordLevel: $wordsMinimumLevel
                        )
                    case .tts:
                        TTSTabContent(speechRate: $speechRate)
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(12)
            }
        }
        // Apple Translation: session init with correct Locale.Language(languageCode:) API
        .translationTask(appleTranslationConfig) { session in
            appState.translationService.setAppleSession(session)
        }
        .onAppear {
            appleTranslationConfig = TranslationSession.Configuration(
                source: Locale.Language(languageCode: .english),
                target: Locale.Language(languageCode: .chinese)
            )
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Translation Tab

struct TranslationTabContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var translationService: TranslationService
    @ObservedObject private var l10n = L10n.shared
    @Binding var minimumWordLevel: CEFRLevel
    
    private func t(_ key: L10nKey) -> String { l10n.string(key) }
    
    private var engines: [TranslationService.Engine] { Array(TranslationService.Engine.allCases) }
    
    /// Short display name for engine picker button
    private func engineShortName(_ engine: TranslationService.Engine) -> String {
        engine.fullDisplayName(lang: l10n.language)
    }

    private var filteredWords: [WordDetail] {
        guard let details = appState.wordAnalysis?.wordDetails else { return [] }
        return filterWords(details, query: "", minimumLevel: minimumWordLevel)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Engine picker
            HStack(spacing: 4) {
                ForEach(engines) { engine in
                    let isSelected = translationService.currentEngine == engine
                    Button(action: {
                        translationService.currentEngine = engine
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
                    }
                    .buttonStyle(.plain)
                }
            }
            
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
                        Image(systemName: "text.bubble")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Text(t(.translatedResult))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    Text(appState.translatedText)
                        .font(.body)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .lineSpacing(4)
                }
            } else if !appState.translationError.isEmpty {
                // Show translation error
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("翻译错误")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                    
                    Text(appState.translationError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.05))
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
                    .frame(maxWidth: .infinity, minHeight: 100)
            }

            if appState.wordAnalysis != nil {
                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "a.square")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Text(l10n.language == .chinese ? "句子单词" : "Sentence Words")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(filteredWords.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    WordFilterBar(
                        searchText: .constant(""),
                        minimumLevel: $minimumWordLevel,
                        showSearchField: false
                    )

                    if filteredWords.isEmpty {
                        Text(l10n.language == .chinese ? "当前筛选条件下暂无单词" : "No words match current filter")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(filteredWords) { word in
                            WordCardView(word: word)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Words Tab

struct WordsTabContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @Binding var wordSearchQuery: String
    @Binding var minimumWordLevel: CEFRLevel
    
    private func t(_ key: L10nKey) -> String { l10n.string(key) }

    private var filteredWords: [WordDetail] {
        guard let details = appState.wordAnalysis?.wordDetails else { return [] }
        return filterWords(details, query: wordSearchQuery, minimumLevel: minimumWordLevel)
    }
    
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
                Text("\(filteredWords.count) \(t(.wordCount))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            WordFilterBar(
                searchText: $wordSearchQuery,
                minimumLevel: $minimumWordLevel,
                showSearchField: true
            )
            
            if appState.wordAnalysis != nil {
                ForEach(filteredWords) { word in
                    WordCardView(
                        word: word,
                        onEditMeaning: { newMeaning in
                            // Update the meaning in the analysis (find by stable id)
                            if let idx = appState.wordAnalysis?.wordDetails.firstIndex(where: { $0.id == word.id }) {
                                appState.wordAnalysis?.wordDetails[idx].meaning = newMeaning.isEmpty ? nil : newMeaning
                            }
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
    @Binding var speechRate: Double
    
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
            
            // Play controls
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(t(.speed))
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                }
                
                HStack(spacing: 20) {
                    Button(action: {
                        if appState.isSpeaking {
                            appState.stopSpeaking()
                        } else {
                            appState.startSpeaking()
                        }
                    }) {
                        Image(systemName: appState.isSpeaking ? "stop.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.selectedText.isEmpty)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "tortoise")
                            .font(.caption)
                        Slider(value: $speechRate, in: 0.1...2.0, step: 0.05)
                            .frame(maxWidth: .infinity)
                        Image(systemName: "hare")
                            .font(.caption)
                        Text(String(format: "%.1fx", speechRate))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            
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

// MARK: - Word Filtering

enum CEFRLevel: String, CaseIterable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
    case c2 = "C2"

    var id: String { rawValue }

    var rank: Int {
        switch self {
        case .a1: return 1
        case .a2: return 2
        case .b1: return 3
        case .b2: return 4
        case .c1: return 5
        case .c2: return 6
        }
    }

    func label(language: AppLanguage) -> String {
        language == .chinese ? "\(rawValue)及以上" : "\(rawValue)+"
    }
}

private func parseCEFRLevel(from difficulty: String) -> CEFRLevel {
    let value = difficulty.uppercased()
    if value.contains("C1/C2") { return .c2 }
    if value.contains("C2") { return .c2 }
    if value.contains("C1") { return .c1 }
    if value.contains("B2") { return .b2 }
    if value.contains("B1") { return .b1 }
    if value.contains("A2") { return .a2 }
    return .a1
}

private func filterWords(_ words: [WordDetail], query: String, minimumLevel: CEFRLevel) -> [WordDetail] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return words.filter { word in
        let level = parseCEFRLevel(from: word.difficulty)
        guard level.rank >= minimumLevel.rank else { return false }
        if trimmed.isEmpty { return true }
        let q = trimmed.lowercased()
        return word.word.lowercased().contains(q)
            || word.lemma.lowercased().contains(q)
            || (word.meaning?.lowercased().contains(q) ?? false)
    }
}

struct WordFilterBar: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var searchText: String
    @Binding var minimumLevel: CEFRLevel
    let showSearchField: Bool

    var body: some View {
        VStack(spacing: 8) {
            if showSearchField {
                TextField(
                    l10n.language == .chinese ? "搜索已查单词" : "Search looked-up words",
                    text: $searchText
                )
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Text(l10n.language == .chinese ? "筛选等级" : "Level")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $minimumLevel) {
                    ForEach(CEFRLevel.allCases) { level in
                        Text(level.label(language: l10n.language)).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 130)
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
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
