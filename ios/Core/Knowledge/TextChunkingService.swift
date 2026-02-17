import Foundation

final class TextChunkingService {
    func chunk(text: String, chunkSize: Int = 800, overlap: Int = 120) -> [String] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }
        return chunkSingle(normalized, chunkSize: chunkSize, overlap: overlap)
    }

    // Page-first strategy: keep each page as an independent retrieval unit.
    // If a page is too long, split only within that page.
    func chunkPages(_ pages: [String], chunkSize: Int = 800, overlap: Int = 120) -> [String] {
        guard !pages.isEmpty else { return [] }

        var result: [String] = []
        for page in pages {
            let normalizedPage = normalize(page)
            guard !normalizedPage.isEmpty else { continue }
            let pageChunks = chunkSingle(normalizedPage, chunkSize: chunkSize, overlap: overlap)
            result.append(contentsOf: pageChunks)
        }
        return result
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chunkSingle(_ text: String, chunkSize: Int, overlap: Int) -> [String] {
        let chars = Array(text)
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
