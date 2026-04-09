//
//  OutlineItem.swift
//  X-Reader
//
//  Table of contents outline item
//

import Foundation
import PDFKit

struct OutlineItem: Identifiable {
    let id = UUID()
    let title: String
    let page: Int
    let level: Int
    let children: [OutlineItem]
    
    init(title: String, page: Int, level: Int = 0, children: [OutlineItem] = []) {
        self.title = title
        self.page = page
        self.level = level
        self.children = children
    }
    
    // Extract outline from PDFDocument outline
    static func from(_ outline: PDFOutline?, level: Int = 0) -> [OutlineItem] {
        guard let outline = outline else { return [] }
        var items: [OutlineItem] = []
        
        let childCount = outline.numberOfChildren
        for i in 0..<childCount {
            guard let child = outline.child(at: i) else { continue }
            
            let title = child.label ?? "Untitled"
            var page = 0
            if let destination = child.destination, let pageRef = destination.page {
                page = pageRef.pageRef?.pageNumber ?? 0
            }
            
            let children = from(child, level: level + 1)
            items.append(OutlineItem(title: title, page: page, level: level, children: children))
        }
        
        return items
    }
}
