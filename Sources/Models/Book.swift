//
//  Book.swift
//  X-Reader
//
//  Book model
//

import Foundation
import PDFKit

struct Book: Identifiable, Codable {
    let id: UUID
    let title: String
    let filePath: String
    let pageCount: Int
    let lastPage: Int
    let addedDate: Date
    
    init(url: URL, pageCount: Int) {
        self.id = UUID()
        self.title = url.deletingPathExtension().lastPathComponent
        self.filePath = url.path
        self.pageCount = pageCount
        self.lastPage = 0
        self.addedDate = Date()
    }
    
    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }
}
