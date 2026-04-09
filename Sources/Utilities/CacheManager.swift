//
//  CacheManager.swift
//  X-Reader
//
//  Translation and analysis result caching
//

import Foundation

class CacheManager {
    private let userDefaults = UserDefaults.standard
    private let translationCacheKey = "translation_cache"
    private let maxCacheSize = 1000
    
    // MARK: - Translation Cache
    
    func getCachedTranslation(for text: String) -> String? {
        var cache = loadTranslationCache()
        let key = cacheKey(from: text)
        return cache[key]
    }
    
    func cacheTranslation(key text: String, value: String) {
        var cache = loadTranslationCache()
        let key = cacheKey(from: text)
        
        // Limit cache size
        if cache.count >= maxCacheSize {
            cache.removeAll()
        }
        
        cache[key] = value
        saveTranslationCache(cache)
    }
    
    // MARK: - Cache Helpers
    
    private func cacheKey(from text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func loadTranslationCache() -> [String: String] {
        if let data = userDefaults.data(forKey: translationCacheKey),
           let cache = try? JSONDecoder().decode([String: String].self, from: data) {
            return cache
        }
        return [:]
    }
    
    private func saveTranslationCache(_ cache: [String: String]) {
        if let data = try? JSONEncoder().encode(cache) {
            userDefaults.set(data, forKey: translationCacheKey)
        }
    }
    
    func clearCache() {
        userDefaults.removeObject(forKey: translationCacheKey)
    }
}
