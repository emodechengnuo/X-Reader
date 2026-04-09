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
    
    private let cacheURL: URL
    private var memoryCache: [String: String] = [:]
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
            return cached
        }
        
        return nil
    }
    
    /// Manually set/save a user-edited translation for a word.
    func setTranslationForWord(_ meaning: String, for word: String) {
        let key = normalizeKey(word)
        setTranslation(meaning, for: key)
    }
    
    /// Get or fetch translation asynchronously.
    /// Calls completion handler with the translated string when available.
    func getOrFetchTranslation(for word: String, 
                               engine: TranslationService?,
                               completion: @escaping (String?) -> Void) {
        let key = normalizeKey(word)
        
        // 1. Check memory cache first
        if let cached = memoryCache[key] {
            completion(cached)
            return
        }
        
        // 2. Already being fetched? Don't call API again.
        guard !pendingTranslations.contains(key) else {
            // Will be available soon — retry after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let result = self?.memoryCache[key] {
                    completion(result)
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
                    self?.setTranslation(translated, for: key)
                    completion(translated)
                } else {
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
            
            // Double-check cache (might have been filled by another call)
            if let cached = memoryCache[key] {
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
                    setTranslation(cleanTranslation, for: key)
                    results[word] = cleanTranslation
                } else {
                    print("[WordTranslationCache] Suspiciously long translation for '\(word)': '\(cleanTranslation)' — skipping")
                }
            }
            
            // Small delay between API calls to avoid rate limiting
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms per word
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    private func setTranslation(_ translation: String, for key: String) {
        memoryCache[key] = translation
        
        // Save to disk asynchronously (don't block UI)
        fileQueue.async { [weak self] in
            self?.saveCache()
        }
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
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            memoryCache = decoded
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
