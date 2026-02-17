import Foundation
import Vision
import UIKit

struct OCRResult {
    var text: String
    var confidence: Float
}

final class OCRService {
    func recognizeText(from image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "OCRService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRResult(text: "", confidence: 0))
                    return
                }

                var lines: [String] = []
                var confidenceTotal: Float = 0
                var confidenceCount: Float = 0
                for observation in observations {
                    guard let top = observation.topCandidates(1).first else { continue }
                    let candidate = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        lines.append(candidate)
                        confidenceTotal += top.confidence
                        confidenceCount += 1
                    }
                }

                let text = lines.joined(separator: "\n")
                let confidence = confidenceCount > 0 ? confidenceTotal / confidenceCount : 0
                continuation.resume(returning: OCRResult(text: text, confidence: confidence))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.01

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
