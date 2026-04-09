//
//  PDFService.swift
//  X-Reader
//
//  PDF loading and rendering service
//

import Foundation
import PDFKit

class PDFService {
    
    func loadDocument(from url: URL) -> PDFDocument? {
        PDFDocument(url: url)
    }
    
    func extractText(from page: PDFPage) -> String {
        page.string ?? ""
    }
    
    func extractFullText(from document: PDFDocument) -> String {
        var fullText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                fullText += page.string ?? ""
                fullText += "\n\n--- Page \(i + 1) ---\n\n"
            }
        }
        return fullText
    }
    
    func renderPage(_ page: PDFPage, scale: CGFloat = 2.0) -> NSImage? {
        let rect = page.bounds(for: .mediaBox)
        let scaledRect = NSRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        let image = NSImage(size: scaledRect.size)
        image.lockFocus()
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }
        
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        
        page.draw(with: .mediaBox, to: context)
        
        context.restoreGState()
        image.unlockFocus()
        
        return image
    }
    
    func getPageInfo(_ document: PDFDocument, at index: Int) -> PageInfo? {
        guard let page = document.page(at: index) else { return nil }
        let rect = page.bounds(for: .mediaBox)
        return PageInfo(
            index: index,
            width: rect.width,
            height: rect.height,
            text: page.string ?? ""
        )
    }
}

struct PageInfo {
    let index: Int
    let width: CGFloat
    let height: CGFloat
    let text: String
}
