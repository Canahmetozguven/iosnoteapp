import Foundation
import PDFKit
import UIKit

struct DocumentExtractionResult {
    var text: String
    var engine: String
    var pages: [String]? = nil
}

final class DocumentTextExtractionService {
    private let ocrService = OCRService()

    func extractText(
        from fileURL: URL,
        mimeType: String,
        llamaContext: LlamaContext?,
        preferOCRModel: Bool
    ) async throws -> DocumentExtractionResult {
        if mimeType.hasPrefix("text/") || fileURL.pathExtension.lowercased() == "md" || fileURL.pathExtension.lowercased() == "txt" {
            let data = try Data(contentsOf: fileURL)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return DocumentExtractionResult(text: text, engine: "plain_text")
        }

        if mimeType == "application/pdf" || fileURL.pathExtension.lowercased() == "pdf" {
            return try await extractPDFText(from: fileURL, llamaContext: llamaContext, preferOCRModel: preferOCRModel)
        }

        if mimeType.hasPrefix("image/") || isImageExtension(fileURL.pathExtension) {
            let data = try Data(contentsOf: fileURL)
            guard let image = UIImage(data: data) else {
                throw NSError(domain: "DocumentTextExtractionService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to decode image"])
            }
            return try await extractFromImage(
                image: image,
                imageData: data,
                llamaContext: llamaContext,
                preferOCRModel: preferOCRModel
            )
        }

        let data = try Data(contentsOf: fileURL)
        let fallback = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return DocumentExtractionResult(text: fallback, engine: "plain_text")
    }

    private func extractPDFText(
        from fileURL: URL,
        llamaContext: LlamaContext?,
        preferOCRModel: Bool
    ) async throws -> DocumentExtractionResult {
        guard let pdf = PDFDocument(url: fileURL) else {
            throw NSError(domain: "DocumentTextExtractionService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to open PDF"])
        }

        var sections: [String] = []
        var usedOCR = false
        var usedModelOCR = false

        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            let textLayer = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !textLayer.isEmpty {
                sections.append(textLayer)
                continue
            }

            guard let image = renderPDFPage(page) else { continue }
            let data = image.jpegData(compressionQuality: 0.9) ?? Data()
            let ocr = try await extractFromImage(
                image: image,
                imageData: data,
                llamaContext: llamaContext,
                preferOCRModel: preferOCRModel
            )
            if !ocr.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append(ocr.text)
                usedOCR = true
                usedModelOCR = usedModelOCR || ocr.engine == "ocr_model"
            }
        }

        let text = sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let engine: String
        if usedModelOCR {
            engine = "ocr_model"
        } else if usedOCR {
            engine = "vision_ocr"
        } else {
            engine = "pdf_text"
        }

        return DocumentExtractionResult(text: text, engine: engine, pages: sections)
    }

    private func extractFromImage(
        image: UIImage,
        imageData: Data,
        llamaContext: LlamaContext?,
        preferOCRModel: Bool
    ) async throws -> DocumentExtractionResult {
        if preferOCRModel, let llamaContext {
            do {
                let modelText = try await llamaContext.extractTextFromImageData(imageData)
                let trimmed = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 20 {
                    return DocumentExtractionResult(text: trimmed, engine: "ocr_model")
                }
            } catch {
                // Fall through to Vision OCR.
            }
        }

        let vision = try await ocrService.recognizeText(from: image)
        if preferOCRModel, let llamaContext {
            do {
                let refined = try await llamaContext.refineOCRText(vision.text)
                let cleaned = refined.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.count >= max(10, vision.text.count / 3) {
                    return DocumentExtractionResult(text: cleaned, engine: "ocr_model")
                }
            } catch {
                // Keep Vision result if OCR model cleanup fails.
            }
        }
        return DocumentExtractionResult(text: vision.text, engine: "vision_ocr")
    }

    private func renderPDFPage(_ page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        let targetWidth: CGFloat = 1600
        let scale = targetWidth / max(bounds.width, 1)
        let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            ctx.cgContext.saveGState()
            ctx.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }
        return image
    }

    private func isImageExtension(_ ext: String) -> Bool {
        let value = ext.lowercased()
        return ["png", "jpg", "jpeg", "webp", "heic", "bmp", "gif", "tiff"].contains(value)
    }
}
