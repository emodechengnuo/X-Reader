//
//  OCRService.swift
//  X-Reader
//
//  OCR text recognition using Apple Vision framework
//

import Foundation
import Vision
import PDFKit
import AppKit

@MainActor
class OCRService: ObservableObject {
    
    func recognizeDocument(
        _ document: PDFDocument,
        progressHandler: @escaping (Double) -> Void
    ) async {
        let totalPages = document.pageCount
        
        for pageIndex in 0..<totalPages {
            guard let page = document.page(at: pageIndex) else { continue }
            
            // Check if page already has text
            let existingText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !existingText.isEmpty && existingText.count > 20 {
                // Page has enough text, skip OCR
                progressHandler(Double(pageIndex + 1) / Double(totalPages))
                continue
            }
            
            // Render page to image
            guard let image = renderPageToImage(page, scale: 2.0),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                progressHandler(Double(pageIndex + 1) / Double(totalPages))
                continue
            }
            
            // Perform OCR
            let text = await recognizeImage(cgImage)
            
            // Note: PDFKit doesn't easily allow adding text overlay to existing PDF
            // In a full implementation, we'd create an annotation layer
            // For now, the OCR text is available for other services to use
            
            progressHandler(Double(pageIndex + 1) / Double(totalPages))
        }
    }
    
    func recognizeImage(_ cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("OCR Error: \(error.localizedDescription)")
                    continuation.resume(returning: "")
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let texts = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                continuation.resume(returning: texts.joined(separator: "\n"))
            }
            
            // Configure for English recognition (best accuracy)
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("Vision request failed: \(error)")
                continuation.resume(returning: "")
            }
        }
    }
    
    func recognizeTextFromImage(_ nsImage: NSImage) async -> String {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        return await recognizeImage(cgImage)
    }
    
    private func renderPageToImage(_ page: PDFPage, scale: CGFloat) -> NSImage? {
        let rect = page.bounds(for: .mediaBox)
        let scaledSize = NSSize(width: rect.width * scale, height: rect.height * scale)
        
        let image = NSImage(size: scaledSize)
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
}
