//
//  Sentence.swift
//  X-Reader
//
//  Word analysis models
//

import Foundation

struct Sentence {
    let text: String
    let startIndex: Int
    let endIndex: Int
    
    var words: [String] {
        text.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }
}

// MARK: - Word Analysis Result

struct GrammarResult {
    let originalText: String
    let partsOfSpeech: [POSResult]
    var wordDetails: [WordDetail]  // mutable — translations filled after analysis
}

// MARK: - Part of Speech Result

struct POSResult: Identifiable {
    let id = UUID()
    let word: String
    let pos: String       // e.g., "名词", "动词"
    let lemma: String     // base form
}

// MARK: - Word Detail

struct WordDetail: Identifiable {
    let id = UUID()
    let word: String
    let pos: String
    let lemma: String
    var meaning: String?      // Chinese meaning (mutable — filled by translation cache)
    let difficulty: String    // CEFR level
    let phonetic: String?     // Phonetic transcription
}
