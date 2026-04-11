import Foundation

enum CEFRBand: String, CaseIterable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
    case c2 = "C2"

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

    static func from(raw: String) -> CEFRBand? {
        CEFRBand(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }
}

final class CEFRVocabularyService {
    static let shared = CEFRVocabularyService()

    private var table: [String: CEFRBand] = [:]
    private var loaded = false
    private let lock = NSLock()

    private init() {}

    func lookupBand(word: String, lemma: String?) -> CEFRBand? {
        ensureLoaded()
        let candidates = normalizedCandidates(word: word, lemma: lemma)
        for token in candidates {
            if let band = table[token] {
                return band
            }
        }
        return nil
    }

    private func ensureLoaded() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true

        loadCSV(named: "cefrj-vocabulary-profile-1.5", defaultBand: nil)
        loadCSV(named: "octanove-vocabulary-profile-c1c2-1.0", defaultBand: nil)
    }

    private func loadCSV(named name: String, defaultBand: CEFRBand?) {
        let url =
            Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "CEFR")
            ?? Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "Resources/CEFR")
            ?? Bundle.module.url(forResource: name, withExtension: "csv")
        guard let url,
              let data = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        let rows = data.split(whereSeparator: \.isNewline)
        guard rows.count > 1 else { return }

        for row in rows.dropFirst() {
            let cols = parseCSVLine(String(row))
            guard cols.count >= 3 else { continue }
            let rawHeadword = cols[0]
            let rawBand = cols[2]
            let band = CEFRBand.from(raw: rawBand) ?? defaultBand
            guard let band else { continue }

            for token in explodeHeadword(rawHeadword) {
                upsert(token: token, band: band)
            }
        }
    }

    private func upsert(token: String, band: CEFRBand) {
        guard !token.isEmpty else { return }
        if let existing = table[token], existing.rank >= band.rank {
            return
        }
        table[token] = band
    }

    private func explodeHeadword(_ raw: String) -> [String] {
        let separators = CharacterSet(charactersIn: "/,;")
        return raw.components(separatedBy: separators)
            .map { normalizeToken($0) }
            .filter { !$0.isEmpty }
    }

    private func normalizedCandidates(word: String, lemma: String?) -> [String] {
        var result: [String] = []
        let w = normalizeToken(word)
        if !w.isEmpty { result.append(w) }
        if let lemma {
            let l = normalizeToken(lemma)
            if !l.isEmpty && !result.contains(l) {
                result.append(l)
            }
        }
        return result
    }

    private func normalizeToken(_ s: String) -> String {
        let lowered = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lowered.isEmpty { return "" }
        let filtered = lowered.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar) || scalar == "'"
        }
        return String(String.UnicodeScalarView(filtered))
    }

    // Minimal CSV parser (handles quoted commas and escaped quotes).
    private func parseCSVLine(_ line: String) -> [String] {
        var cols: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                let next = line.index(after: i)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    i = next
                } else {
                    inQuotes.toggle()
                }
            } else if ch == ",", !inQuotes {
                cols.append(current)
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(ch)
            }
            i = line.index(after: i)
        }

        cols.append(current)
        return cols
    }
}
