//
//  WordTranslationCache.swift
//  X-Reader
//
//  File-based word translation cache with translation engine integration.
//  Strategy: Check local file cache first → if miss, call TranslationService → save to cache.
//

import Foundation

/// Manages cached Chinese translations for English words using a JSON file on disk.
class WordTranslationCache {
    
    // MARK: - Singleton
    
    static let shared = WordTranslationCache()
    
    // MARK: - Properties

    private struct Entry: Codable {
        var meaning: String
        var isManual: Bool
        var autoFetchedOnce: Bool
    }
    
    private let cacheURL: URL
    private var memoryCache: [String: Entry] = [:]
    private let fileQueue = DispatchQueue(label: "com.xreader.wordcache", qos: .utility)
    private let translationService: TranslationService?
    
    /// Words currently being translated (prevent duplicate API calls)
    private var pendingTranslations: Set<String> = []
    
    // MARK: - Init
    
    init(cacheFileName: String = "word_translation_cache.json", 
         translationService: TranslationService? = nil) {
        // Store in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("X-Reader", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        self.cacheURL = appDir.appendingPathComponent(cacheFileName)
        self.translationService = translationService
        
        // Load existing cache into memory (fast lookups)
        loadCache()
        
        print("[WordTranslationCache] Cache loaded: \(memoryCache.count) words from \(cacheURL.path)")
    }
    
    // MARK: - Public API
    
    /// Get Chinese translation for a word.
    /// Returns immediately if cached; otherwise returns nil and starts async translation.
    func getTranslation(for word: String) -> String? {
        let key = normalizeKey(word)
        
        // 1. Check memory cache first (fastest)
        if let cached = memoryCache[key] {
            let value = cached.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        
        return nil
    }
    
    /// Manually set/save a user-edited translation for a word.
    func setTranslationForWord(_ meaning: String, for word: String) {
        let key = normalizeKey(word)
        let trimmed = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            memoryCache.removeValue(forKey: key)
            fileQueue.async { [weak self] in
                self?.saveCache()
            }
            return
        }
        setEntry(
            Entry(
                meaning: trimmed,
                isManual: true,
                autoFetchedOnce: true
            ),
            for: key
        )
    }

    /// If user manually edited this word, automatic updates must not overwrite it.
    func isManualLocked(_ word: String) -> Bool {
        let key = normalizeKey(word)
        return memoryCache[key]?.isManual == true
    }

    /// Auto lookup should only happen once for non-manual words.
    func shouldFetchAutoTranslation(for word: String) -> Bool {
        let key = normalizeKey(word)
        guard let entry = memoryCache[key] else { return true }
        if entry.isManual { return false }
        return !entry.autoFetchedOnce
    }
    
    /// Get or fetch translation asynchronously.
    /// Calls completion handler with the translated string when available.
    func getOrFetchTranslation(for word: String, 
                               engine: TranslationService?,
                               completion: @escaping (String?) -> Void) {
        let key = normalizeKey(word)
        
        // 1. Check memory cache first
        if let cached = memoryCache[key] {
            completion(cached.meaning)
            return
        }
        
        // 2. Already being fetched? Don't call API again.
        guard !pendingTranslations.contains(key) else {
            // Will be available soon — retry after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let result = self?.memoryCache[key] {
                    let value = result.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(value.isEmpty ? nil : value)
                } else {
                    completion(nil) // Give up after one retry
                }
            }
            return
        }
        
        // 3. Call translation engine
        guard let translator = engine ?? self.translationService else {
            completion(nil)
            return
        }
        
        pendingTranslations.insert(key)
        
        Task { [weak self] in
            let translated = await translator.translate(word.lowercased())
            
            await MainActor.run {
                defer {
                    self?.pendingTranslations.remove(key)
                }
                
                if !translated.isEmpty {
                    self?.setAutoTranslationOnce(translated, for: key)
                    completion(translated)
                } else {
                    self?.markAutoFetchAttempted(for: key)
                    completion(nil)
                }
            }
        }
    }
    
    /// Batch translate multiple words one-by-one (safer than combined text).
    /// Returns a dictionary of word → translation for all successfully translated words.
    func batchTranslate(_ words: [String], 
                        engine: TranslationService?) async -> [String: String] {
        var results: [String: String] = [:]
        let translator = engine ?? self.translationService
        
        guard let translator else { return results }
        
        for word in words {
            let key = normalizeKey(word)

            guard shouldFetchAutoTranslation(for: word) else {
                if let cached = memoryCache[key]?.meaning {
                    results[word] = cached
                }
                continue
            }
            
            // Double-check cache (might have been filled by another call)
            if let cached = memoryCache[key]?.meaning {
                results[word] = cached
                continue
            }
            
            // Translate this single word — guaranteed 1:1 mapping
            let translated = await translator.translate(word.lowercased())
            
            if !translated.isEmpty {
                // Validate: translated text should be reasonably short for a single word
                // If it's suspiciously long (>30 chars), it might be a sentence translation error
                let cleanTranslation = translated.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if cleanTranslation.count <= 30 {
                    setAutoTranslationOnce(cleanTranslation, for: key)
                    results[word] = cleanTranslation
                } else {
                    print("[WordTranslationCache] Suspiciously long translation for '\(word)': '\(cleanTranslation)' — skipping")
                    markAutoFetchAttempted(for: key)
                }
            } else {
                markAutoFetchAttempted(for: key)
            }
            
            // Small delay between API calls to avoid rate limiting
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms per word
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    private func setEntry(_ entry: Entry, for key: String) {
        memoryCache[key] = entry
        
        // Save to disk asynchronously (don't block UI)
        fileQueue.async { [weak self] in
            self?.saveCache()
        }
    }

    private func setAutoTranslationOnce(_ translation: String, for key: String) {
        let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = memoryCache[key], existing.isManual {
            return
        }
        setEntry(
            Entry(
                meaning: trimmed,
                isManual: false,
                autoFetchedOnce: true
            ),
            for: key
        )
    }

    private func markAutoFetchAttempted(for key: String) {
        if let existing = memoryCache[key] {
            if existing.isManual || existing.autoFetchedOnce { return }
            setEntry(
                Entry(
                    meaning: existing.meaning,
                    isManual: false,
                    autoFetchedOnce: true
                ),
                for: key
            )
            return
        }
        setEntry(
            Entry(
                meaning: "",
                isManual: false,
                autoFetchedOnce: true
            ),
            for: key
        )
    }
    
    private func normalizeKey(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - File I/O
    
    private func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            memoryCache = [:]
            return
        }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            if let decodedV2 = try? JSONDecoder().decode([String: Entry].self, from: data) {
                memoryCache = decodedV2
                return
            }

            // Backward-compatibility for legacy cache: [String: String]
            if let decodedV1 = try? JSONDecoder().decode([String: String].self, from: data) {
                memoryCache = decodedV1.reduce(into: [:]) { partialResult, pair in
                    partialResult[pair.key] = Entry(
                        meaning: pair.value,
                        isManual: false,
                        autoFetchedOnce: true
                    )
                }
                return
            }

            memoryCache = [:]
        } catch {
            print("[WordTranslationCache] Error loading cache: \(error)")
            memoryCache = [:]
        }
    }
    
    private func saveCache() {
        do {
            let data = try JSONEncoder().encode(memoryCache)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("[WordTranslationCache] Error saving cache: \(error)")
        }
    }
    
    // MARK: - Management
    
    var cacheCount: Int {
        memoryCache.count
    }
    
    func clearCache() {
        memoryCache.removeAll()
        try? FileManager.default.removeItem(at: cacheURL)
        print("[WordTranslationCache] Cache cleared")
    }
}
