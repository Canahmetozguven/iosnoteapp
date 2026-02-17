import Foundation

final class TextChunkingService {
    func chunk(text: String, chunkSize: Int = 800, overlap: Int = 120) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let chars = Array(normalized)
        let safeSize = max(200, chunkSize)
        let safeOverlap = max(0, min(overlap, safeSize - 1))
        let step = max(1, safeSize - safeOverlap)

        var result: [String] = []
        var start = 0
        while start < chars.count {
            let end = min(chars.count, start + safeSize)
            let chunk = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                result.append(chunk)
            }
            if end == chars.count {
                break
            }
            start += step
        }
        return result
    }
}
