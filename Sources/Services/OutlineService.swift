//
//  OutlineService.swift
//  X-Reader
//
//  Extract or auto-generate table of contents
//

import Foundation
import PDFKit

class OutlineService {
    
    // MARK: - Extract from PDF bookmarks
    
    func extractOutline(from document: PDFDocument) -> [OutlineItem] {
        // Try PDF outline first
        if let outline = document.outlineRoot {
            let items = OutlineItem.from(outline)
            if !items.isEmpty {
                return items
            }
        }
        
        // Fallback: auto-generate from page content
        return autoGenerateOutline(from: document)
    }
    
    // MARK: - Auto-generate outline
    
    private func autoGenerateOutline(from document: PDFDocument) -> [OutlineItem] {
        var items: [OutlineItem] = []
        let pageCount = document.pageCount
        
        for pageIdx in 0..<pageCount {
            guard let page = document.page(at: pageIdx),
                  let text = page.string else { continue }
            
            // Strategy 1: Look for chapter patterns
            let lines = text.components(separatedBy: .newlines)
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                // Common chapter patterns
                if isChapterHeading(trimmed) {
                    items.append(OutlineItem(
                        title: trimmed,
                        page: pageIdx + 1,
                        level: 0
                    ))
                }
                // Section patterns (indented)
                else if isSectionHeading(trimmed) {
                    items.append(OutlineItem(
                        title: trimmed,
                        page: pageIdx + 1,
                        level: 1
                    ))
                }
            }
        }
        
        return items
    }
    
    // MARK: - Heading Detection
    
    private func isChapterHeading(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        let lowerText = trimmedText.lowercased()
        
        // English patterns
        // Chapter X
        if lowerText.hasPrefix("chapter") && trimmedText.count < 80 {
            return true
        }
        // CHAPTER X: Title
        if trimmedText.range(of: #"^Chapter\s+\d+[:.]?\s*.+"#, options: .regularExpression) != nil {
            return true
        }
        // Part X
        if trimmedText.range(of: #"^Part\s+[IVXLCDM]+[:.]?\s*.+"#, options: .regularExpression) != nil {
            return true
        }
        // Unit X
        if trimmedText.range(of: #"^Unit\s+\d+[:.]?\s*.+"#, options: .regularExpression) != nil {
            return true
        }
        
        // Chinese patterns
        // 第X章, 第X节, 第X篇, 第X讲
        if trimmedText.range(of: #"^第[零一二三四五六七八九十百千万\d]+\s*[章节篇讲]"#, options: .regularExpression) != nil && trimmedText.count < 80 {
            return true
        }
        // 第一章, 第一节 (with optional punctuation)
        if trimmedText.range(of: #"^[第]?[零一二三四五六七八九十百千万\d]+\s*[章节篇讲][:：]?\s*.+"#, options: .regularExpression) != nil && trimmedText.count < 80 {
            return true
        }
        // 一、, 二、 (Chinese numbering with Chinese punctuation)
        if trimmedText.range(of: #"^[零一二三四五六七八九十百千万]+[、.]\s*.+"#, options: .regularExpression) != nil && trimmedText.count < 80 {
            return true
        }
        
        // All uppercase short lines (likely headings)
        if trimmedText.count > 3 && trimmedText.count < 60 && trimmedText == trimmedText.uppercased() && trimmedText.allSatisfy({ $0.isLetter || $0.isWhitespace }) {
            return true
        }
        // All uppercase with subtitle
        if let colonRange = trimmedText.range(of: ":") {
            let prefix = String(trimmedText[trimmedText.startIndex..<colonRange.lowerBound])
            if prefix == prefix.uppercased() && !prefix.isEmpty && trimmedText.count < 80 {
                return true
            }
        }
        // Chinese uppercase with colon
        if let colonRange = trimmedText.range(of: "：") {
            let prefix = String(trimmedText[trimmedText.startIndex..<colonRange.lowerBound])
            if prefix == prefix.uppercased() && !prefix.isEmpty && trimmedText.count < 80 {
                return true
            }
        }
        
        // Additional patterns: Roman numerals
        if trimmedText.range(of: #"^[IVXLCDM]+\s*[:.]\s*.+"#, options: .regularExpression) != nil && trimmedText.count < 80 {
            return true
        }
        
        return false
    }
    
    private func isSectionHeading(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        
        // English patterns
        // Section X.Y
        if trimmedText.range(of: #"^\d+\.\d+\s*.+"#, options: .regularExpression) != nil && trimmedText.count < 80 {
            return true
        }
        // X.Y Title
        if trimmedText.range(of: #"^\d+\.\d+\s+[A-Z]"#, options: .regularExpression) != nil && trimmedText.count < 60 {
            return true
        }
        // Section X
        if trimmedText.range(of: #"^Section\s+\d+[:.]?\s*.+"#, options: .regularExpression) != nil && trimmedText.count < 80 {
            return true
        }
        
        // Chinese patterns
        // X.Y中文标题
        if trimmedText.range(of: #"^\d+\.\d+\s*[\u4e00-\u9fff]"#, options: .regularExpression) != nil && trimmedText.count < 80 {
            return true
        }
        // 第X.Y节
        if trimmedText.range(of: #"^第\d+\.\d+\s*[节]"#, options: .regularExpression) != nil && trimmedText.count < 80 {
            return true
        }
        // (一), (二) etc.
        if trimmedText.range(of: #"^（[零一二三四五六七八九十百千万]+）"#, options: .regularExpression) != nil && trimmedText.count < 80 {
            return true
        }
        // 1.1.1 sub-section
        if trimmedText.range(of: #"^\d+\.\d+\.\d+\s*.+"#, options: .regularExpression) != nil && trimmedText.count < 80 {
            return true
        }
        
        return false
    }
}

// MARK: - String Extension

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
