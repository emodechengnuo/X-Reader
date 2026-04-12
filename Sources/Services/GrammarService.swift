//
//  GrammarService.swift
//  X-Reader
//
//  Word analysis using Apple NaturalLanguage framework (POS tagging + word details)
//


import Foundation
import NaturalLanguage

class GrammarService {
    
    func analyze(text: String) -> GrammarResult {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        
        let posResults = extractPOS(tagger: tagger, text: text)
        let wordDetails = extractWordDetails(tagger: tagger, text: text)
        
        return GrammarResult(
            originalText: text,
            partsOfSpeech: posResults,
            wordDetails: wordDetails
        )
    }
    
    // MARK: - Part of Speech
    
    private func extractPOS(tagger: NLTagger, text: String) -> [POSResult] {
        var results: [POSResult] = []
        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            guard let tag = tag else { return true }
            
            let word = String(text[tokenRange])
            let lemma = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? word
            
            results.append(POSResult(
                word: word,
                pos: posDisplayName(tag),
                lemma: lemma
            ))
            
            return true
        }
        
        return results
    }
    
    // MARK: - Word Details
    
    private func extractWordDetails(tagger: NLTagger, text: String) -> [WordDetail] {
        var details: [WordDetail] = []
        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            guard let tag = tag else { return true }
            
            let word = String(text[tokenRange])
            let lemma = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? word
            let posTags = posCandidates(tagger: tagger, tokenRange: tokenRange, fallbackTag: tag)
            let posName = posTags.first ?? posDisplayName(tag)
            let difficulty = estimateDifficulty(word: word, lemma: lemma)
            
            details.append(WordDetail(
                word: word,
                pos: posName,
                posTags: posTags,
                lemma: lemma,
                meaning: nil, // Will be filled by TranslationService with caching
                difficulty: difficulty,
                phonetic: nil
            ))
            
            return true
        }
        
        return details
    }
    
    // MARK: - Helpers
    
    private func posDisplayName(_ tag: NLTag) -> String {
        switch tag {
        case .noun: return "名词"
        case .verb: return "动词"
        case .adjective: return "形容词"
        case .adverb: return "副词"
        case .pronoun: return "代词"
        case .determiner: return "限定词"
        case .preposition: return "介词"
        case .conjunction: return "连词"
        case .interjection: return "感叹词"
        case .particle: return "助词"
        case .classifier: return "量词"
        case .idiom: return "习语"
        case .openQuote: return "引号"
        case .closeQuote: return "引号"
        case .openParenthesis: return "左括号"
        case .closeParenthesis: return "右括号"
        case .dash: return "破折号"
        case .otherWord: return ""
        default: return tag.rawValue
        }
    }

    private func posCandidates(tagger: NLTagger, tokenRange: Range<String.Index>, fallbackTag: NLTag) -> [String] {
        let (hypotheses, _) = tagger.tagHypotheses(
            at: tokenRange.lowerBound,
            unit: .word,
            scheme: .lexicalClass,
            maximumCount: 4
        )

        var candidates: [String] = hypotheses
            .keys
            .compactMap { NLTag(rawValue: $0) }
            .map(posDisplayName)
            .filter { !$0.isEmpty }

        // If a generic tag appears together with real tags, hide the generic one.
        if candidates.count > 1 {
            candidates.removeAll { $0 == "未知" || $0 == "词" || $0.lowercased() == "otherword" }
        }

        if candidates.isEmpty {
            let fallback = posDisplayName(fallbackTag)
            if !fallback.isEmpty {
                candidates = [fallback]
            }
        }

        // Keep stable order and remove duplicates.
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }
    
    private func estimateDifficulty(word: String, lemma: String) -> String {
        // CEFR-J (A1-B2) + Octanove (C1/C2) wordlists:
        // unknown words are treated as C2 by product decision.
        let band = CEFRVocabularyService.shared.lookupBand(word: word, lemma: lemma) ?? .c2
        switch band {
        case .a1: return "A1 入门"
        case .a2: return "A2 基础"
        case .b1: return "B1 中级"
        case .b2: return "B2 中高级"
        case .c1: return "C1 高级"
        case .c2: return "C2 精通"
        }
    }
}
