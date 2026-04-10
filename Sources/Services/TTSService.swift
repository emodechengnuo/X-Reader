//
//  TTSService.swift
//  X-Reader
//
//  Text-to-Speech using Kokoro CoreML (local, no API key, no MLX)
//  Falls back to AVSpeechSynthesis if model not loaded yet.
//

import Foundation
import AVFoundation
import KokoroCoreML

class TTSService: NSObject, ObservableObject {

    // MARK: - Properties

    /// Separate delegate class to avoid @preconcurrency AVFoundation conformance issues
    private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
        var onStarted: (() -> Void)?
        var onFinished: (() -> Void)?
        var onWord: ((NSRange, String) -> Void)?
        private var utteranceText: String = ""
        private var wordsList: [String] = []

        func configure(text: String, words: [String]) {
            utteranceText = text
            wordsList = words
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
            utteranceText = utterance.speechString
            onStarted?()
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            onFinished?()
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            onFinished?()
        }

        func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            willSpeakRange speechRange: NSRange,
            characterRange utteranceRange: NSRange,
            of utterance: AVSpeechUtterance
        ) {
            let nsText = (utteranceText as NSString)
            let currentChars = nsText.substring(with: speechRange)
            var wordIndex = 0
            if let idx = wordsList.firstIndex(where: { $0.lowercased().hasPrefix(currentChars.lowercased()) }) {
                wordIndex = idx
            }
            onWord?(speechRange, utteranceText)
        }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let speechDelegate = SpeechDelegate()
    private var speakingCallback: ((Bool, Int) -> Void)?
    private var words: [String] = []
    private var currentWordIndex: Int = 0
    private var currentUtteranceText: String = ""
    private var currentPlaybackRate: Float = 1.0

    /// Kokoro TTS engine (loaded lazily)
    private var kokoroEngine: KokoroEngine?

    /// Whether the Kokoro model is currently being loaded/downloaded (published for UI observation)
    @Published var isKokoroLoading: Bool = false
    /// Timer to auto-release Kokoro model after idle
    private var kokoroReleaseTimer: Timer?
    /// How long to keep Kokoro in memory after last use (seconds)
    private let kokoroIdleTimeout: TimeInterval = 120

    /// Audio engine for Kokoro playback
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?

    var isSpeaking: Bool {
        return (audioEngine?.isRunning ?? false) || synthesizer.isSpeaking
    }

    /// Whether Kokoro TTS is ready
    var isKokoroReady: Bool {
        kokoroEngine != nil
    }

    /// Model loading status for UI
    @Published var kokoroStatus: String = "未加载"
    @Published var kokoroProgress: Double = 0

    // MARK: - Voice options

    struct VoiceOption: Identifiable, Hashable {
        let id: String
        let name: String
        let quality: String
        let language: String
        let isKokoro: Bool

        var displayName: String { name }

        var priority: Int {
            if isKokoro { return 0 }
            switch quality {
            case "Siri *": return 1
            case "Premium": return 2
            case "Enhanced": return 3
            case "Default": return 4
            default: return 5
            }
        }
    }

    /// Kokoro English voices
    private static let kokoroEnglishVoices: [(id: String, name: String)] = [
        ("kokoro:af_heart", "Kokoro — Heart (Female, Warm)"),
        ("kokoro:af_sky", "Kokoro — Sky (Female, Gentle)"),
        ("kokoro:af_bella", "Kokoro — Bella (Female, Sweet)"),
        ("kokoro:af_nicole", "Kokoro — Nicole (Female, Professional)"),
        ("kokoro:af_sarah", "Kokoro — Sarah (Female, Friendly)"),
        ("kokoro:am_adam", "Kokoro — Adam (Male, Calm)"),
        ("kokoro:am_michael", "Kokoro — Michael (Male, Deep)"),
        ("kokoro:bf_emma", "Kokoro — Emma (British Female)"),
        ("kokoro:bf_isabella", "Kokoro — Isabella (British Female)"),
        ("kokoro:bm_george", "Kokoro — George (British Male)"),
        ("kokoro:bm_lewis", "Kokoro — Lewis (British Male)"),
    ]

    /// All available voices: Kokoro (preferred) + system English voices
    static let allVoices: [VoiceOption] = {
        var voices: [VoiceOption] = []

        // Kokoro voices first
        for voice in kokoroEnglishVoices {
            voices.append(VoiceOption(
                id: voice.id,
                name: voice.name,
                quality: "Kokoro AI ⭐",
                language: voice.id.contains("bf_") || voice.id.contains("bm_") ? "en-GB" : "en-US",
                isKokoro: true
            ))
        }

        // System voices as fallback
        let systemVoices = AVSpeechSynthesisVoice.speechVoices()
        let englishVoices = systemVoices.filter { $0.language.hasPrefix("en") }

        let noveltyKeywords = [
            "bad news", "bahh", "boing", "bubbles", "cellos",
            "deranged", "good news", "hysterical", "junior",
            "kathy", "princess", "ralph", "sandy", "whisper",
            "zarvox", "albert", "fred", "bruce", "vicki",
            "trinoids", "pipe organ", "bells", "flushed",
            "freaky", "wobble", "superstar"
        ]

        let filtered = englishVoices
            .filter { voice in
                let id = voice.identifier.lowercased()
                let name = voice.name.lowercased()
                let isNovelty = noveltyKeywords.contains { keyword in
                    name.contains(keyword) || id.contains(keyword)
                }
                return !isNovelty
            }
            .map { voice -> VoiceOption in
                let quality: String
                let identifier = voice.identifier.lowercased()

                if identifier.contains("siri") {
                    quality = "Siri *"
                } else if identifier.contains("premium") {
                    quality = "Premium"
                } else if identifier.contains("enhanced") {
                    quality = "Enhanced"
                } else {
                    quality = "Default"
                }

                return VoiceOption(
                    id: voice.identifier,
                    name: voice.name + " (" + voice.language + ")",
                    quality: quality,
                    language: voice.language,
                    isKokoro: false
                )
            }

        voices.append(contentsOf: filtered)

        return voices.sorted { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.name < b.name
        }
    }()

    // MARK: - Init

    override init() {
        super.init()
        synthesizer.delegate = speechDelegate
        speechDelegate.onStarted = { [weak self] in
            self?.speakingCallback?(true, 0)
        }
        speechDelegate.onFinished = { [weak self] in
            self?.speakingCallback?(false, 0)
        }
        speechDelegate.onWord = { [weak self] _, text in
            guard let self = self else { return }
            let nsText = text as NSString
            // Notify progress with current word index
            self.speakingCallback?(true, self.currentWordIndex)
        }
    }

    // MARK: - Load Kokoro Model

    nonisolated func loadKokoroModel() async {
        // Check state before starting
        var alreadyLoading: Bool = false
        var engineExists: KokoroEngine?
        await MainActor.run {
            engineExists = self.kokoroEngine
            alreadyLoading = self.isKokoroLoading
        }
        guard engineExists == nil, !alreadyLoading else { return }

        await MainActor.run { self.isKokoroLoading = true }
        await MainActor.run { self.kokoroStatus = L10n.shared.string(.kokoroDownloading) }
        await MainActor.run { self.kokoroProgress = 0 }

        // Run blocking download + model init on a background thread via Task.detached
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task.detached(priority: .userInitiated) { [weak self] in
                let modelDir = KokoroEngine.defaultModelDirectory

                // Download (synchronous, blocking)
                if !KokoroEngine.isDownloaded(at: modelDir) {
                    do {
                        try KokoroEngine.download(to: modelDir) { progress in
                            Task { @MainActor in
                                self?.kokoroProgress = progress * 0.8
                                self?.kokoroStatus = L10n.shared.string(.kokoroDownloading) + " \(Int(progress * 100))%"
                            }
                        }
                    } catch {
                        Task { @MainActor in
                            self?.kokoroStatus = "下载 Kokoro 语音引擎失败"
                            self?.isKokoroLoading = false
                        }
                        print("[TTSService] Kokoro download failed: \(error)")
                        continuation.resume()
                        return
                    }
                }

                // Load engine (CPU-intensive: CoreML model compilation — synchronous/blocking)
                Task { @MainActor in
                    self?.kokoroStatus = L10n.shared.string(.kokoroLoading)
                }
                do {
                    let engine = try KokoroEngine(modelDirectory: modelDir)
                    Task { @MainActor in
                        self?.kokoroEngine = engine
                        self?.kokoroStatus = "已就绪 ✓"
                        self?.kokoroProgress = 1.0
                        self?.isKokoroLoading = false
                    }
                    print("[TTSService] Kokoro model loaded successfully")
                } catch {
                    Task { @MainActor in
                        self?.kokoroStatus = "加载失败: \(error.localizedDescription)"
                        self?.isKokoroLoading = false
                    }
                    print("[TTSService] Kokoro model load failed: \(error)")
                }

                continuation.resume()
            }
        }
    }

    /// Release Kokoro model from memory to save ~300-500MB.
    /// Model will be lazily reloaded on next speak() call.
    @MainActor
    func unloadKokoroModel() {
        guard kokoroEngine != nil else { return }
        stop()
        kokoroEngine = nil
        kokoroReleaseTimer?.invalidate()
        kokoroReleaseTimer = nil
        kokoroStatus = "未加载"
        kokoroProgress = 0
        isKokoroLoading = false
        print("[TTSService] Kokoro model unloaded to free memory")
    }

    /// Schedule automatic release after idle timeout
    private func scheduleKokoroRelease() {
        kokoroReleaseTimer?.invalidate()
        kokoroReleaseTimer = Timer.scheduledTimer(withTimeInterval: kokoroIdleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.unloadKokoroModel()
            }
        }
    }

    // MARK: - Speak

    func speak(
        _ text: String,
        rate: Float? = nil,
        voiceIdentifier: String? = nil,
        onProgress: ((Bool, Int) -> Void)? = nil
    ) {
        stop()
        speakingCallback = onProgress

        // Read rate from UserDefaults if not provided
        let actualRate: Float
        if let rate = rate {
            actualRate = rate
        } else {
            let saved = UserDefaults.standard.double(forKey: "speech_rate")
            actualRate = saved > 0 ? Float(saved) : 1.0
        }

        currentPlaybackRate = actualRate

        // Check if using Kokoro voice
        if let voiceId = voiceIdentifier, voiceId.hasPrefix("kokoro:") {
            speakWithKokoro(text: text, voiceId: voiceId)
            return
        }

        // Fall back to AVSpeechSynthesis
        speakWithSystemVoice(text: text, voiceIdentifier: voiceIdentifier, rate: actualRate)
    }

    /// Speak using Kokoro TTS
    private func speakWithKokoro(text: String, voiceId: String) {
        guard let engine = kokoroEngine else {
            print("[TTSService] Kokoro model not ready, falling back to system voice")
            speakWithSystemVoice(text: text, voiceIdentifier: nil, rate: currentPlaybackRate)
            return
        }

        // Extract voice name from "kokoro:af_heart" format
        let voiceName = voiceId.replacingOccurrences(of: "kokoro:", with: "")

        Task { @MainActor in
            do {
                let result = try engine.synthesize(text: text, voice: voiceName)
                speakingCallback?(true, 0)

                // Play audio samples with rate control
                try playAudioSamples(result.samples, rate: currentPlaybackRate)

                speakingCallback?(false, 0)
                // Schedule model release after idle period
                scheduleKokoroRelease()
            } catch {
                print("[TTSService] Kokoro synthesis failed: \(error)")
                // Fall back to system voice
                speakWithSystemVoice(text: text, voiceIdentifier: nil, rate: currentPlaybackRate)
            }
        }
    }

    /// Speak using AVSpeechSynthesis (fallback)
    private func speakWithSystemVoice(text: String, voiceIdentifier: String?, rate: Float) {
        words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        currentWordIndex = 0

        speechDelegate.configure(text: text, words: words)
        speechDelegate.onWord = { [weak self] range, _ in
            guard let self = self else { return }
            let nsText = (text as NSString)
            let currentChars = nsText.substring(with: range)
            if let idx = self.words.firstIndex(where: { $0.lowercased().hasPrefix(currentChars.lowercased()) }) {
                self.currentWordIndex = idx
            }
            self.speakingCallback?(true, self.currentWordIndex)
        }

        let utterance = AVSpeechUtterance(string: text)
        // Slider range: 0.1~2.0, default 1.0
        // 0.5 = half speed (AVSpeechDefaultSpeechRate ≈ 0.5)
        // 1.0 = normal speed (AVSpeechDefaultSpeechRate ≈ 0.5)
        // 2.0 = double speed (AVSpeechMaximumSpeechRate ≈ 1.0)
        // Linear map: [0.5, 2.0] → [AVSpeechMinimum, AVSpeechMaximum]
        let factor = Float((AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) / (2.0 - 0.5))
        let mappedRate = min(AVSpeechUtteranceMaximumSpeechRate,
                             max(AVSpeechUtteranceMinimumSpeechRate,
                                 AVSpeechUtteranceMinimumSpeechRate + (rate - 0.5) * factor))
        utterance.rate = mappedRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        if let voiceId = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        currentUtterance = utterance
        currentUtteranceText = text
        synthesizer.speak(utterance)
    }

    /// Play audio samples through AVAudioEngine with rate control
    private func playAudioSamples(_ samples: [Float], rate: Float) throws {
        // Stop any existing audio engine
        stopAudioEngine()

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()

        // Kokoro outputs audio at ~2x speed internally (24000Hz content at 48000Hz).
        // Slider 0.5 = half speed → timePitch.rate 0.5
        // Slider 1.0 = normal speed → timePitch.rate 1.0
        // Slider 2.0 = double speed → timePitch.rate 2.0
        let kokoroRate = rate
        let clampedRate = max(0.5, min(4.0, kokoroRate))
        timePitch.rate = clampedRate

        engine.attach(playerNode)
        engine.attach(timePitch)

        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        try engine.start()

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(buffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)

        playerNode.scheduleBuffer(buffer)
        playerNode.play()

        self.audioEngine = engine
        self.audioPlayerNode = playerNode
    }

    private func stopAudioEngine() {
        audioPlayerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        audioPlayerNode = nil
    }

    // MARK: - Stop / Pause / Resume

    func stop() {
        stopAudioEngine()
        synthesizer.stopSpeaking(at: .immediate)
        speakingCallback = nil
        currentWordIndex = 0
    }

    func pause() {
        audioPlayerNode?.pause()
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
        }
    }

    func resume() {
        if #available(macOS 15.0, *) {
            audioPlayerNode?.play()
        }
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    private var currentUtterance: AVSpeechUtterance?
}
