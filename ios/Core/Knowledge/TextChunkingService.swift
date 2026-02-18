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
        let safeSize = max(200, chunkSize)
        let safeOverlap = max(0, min(overlap, safeSize - 1))
        let units = semanticUnits(from: text, unitMaxLength: safeSize)
        guard !units.isEmpty else { return [] }

        var baseChunks: [String] = []
        var current = ""

        for unit in units {
            if current.isEmpty {
                current = unit
                continue
            }

            let separator = "\n\n"
            let candidate = current + separator + unit
            if candidate.count <= safeSize {
                current = candidate
            } else {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    baseChunks.append(trimmed)
                }
                current = unit
            }
        }

        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            baseChunks.append(trailing)
        }
        if safeOverlap == 0 || baseChunks.count < 2 {
            return baseChunks
        }
        return applyOverlap(baseChunks, overlap: safeOverlap, maxLength: safeSize)
    }

    private func semanticUnits(from text: String, unitMaxLength: Int) -> [String] {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var units: [String] = []
        for paragraph in paragraphs {
            if paragraph.count <= unitMaxLength {
                units.append(paragraph)
                continue
            }

            let sentenceUnits = splitIntoSentences(paragraph)
            var sentenceBuffer = ""
            for sentence in sentenceUnits {
                if sentenceBuffer.isEmpty {
                    sentenceBuffer = sentence
                } else if sentenceBuffer.count + 1 + sentence.count <= unitMaxLength {
                    sentenceBuffer += " " + sentence
                } else {
                    appendOrSplit(sentenceBuffer, into: &units, maxLength: unitMaxLength)
                    sentenceBuffer = sentence
                }
            }

            if !sentenceBuffer.isEmpty {
                appendOrSplit(sentenceBuffer, into: &units, maxLength: unitMaxLength)
            }
        }

        if units.isEmpty {
            appendOrSplit(text, into: &units, maxLength: unitMaxLength)
        }
        return units
    }

    private func appendOrSplit(_ text: String, into units: inout [String], maxLength: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.count <= maxLength {
            units.append(trimmed)
            return
        }

        var start = trimmed.startIndex
        while start < trimmed.endIndex {
            let end = trimmed.index(start, offsetBy: maxLength, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            let part = String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty {
                units.append(part)
            }
            start = end
        }
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        let pattern = #"(?<=[\.\!\?])\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }

        let range = NSRange(text.startIndex..., in: text)
        var start = text.startIndex
        var sentences: [String] = []

        for match in regex.matches(in: text, options: [], range: range) {
            guard let boundary = Range(match.range, in: text) else { continue }
            let sentence = String(text[start..<boundary.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            start = boundary.upperBound
        }

        let trailing = String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            sentences.append(trailing)
        }
        return sentences.isEmpty ? [text] : sentences
    }

    private func applyOverlap(_ chunks: [String], overlap: Int, maxLength: Int) -> [String] {
        guard chunks.count > 1 else { return chunks }
        var result: [String] = []
        result.reserveCapacity(chunks.count)

        for index in chunks.indices {
            if index == 0 {
                result.append(chunks[index])
                continue
            }

            let previousTail = String(chunks[index - 1].suffix(overlap)).trimmingCharacters(in: .whitespacesAndNewlines)
            var merged = previousTail.isEmpty ? chunks[index] : "\(previousTail)\n\(chunks[index])"
            if merged.count > maxLength {
                merged = String(merged.prefix(maxLength))
            }
            merged = merged.trimmingCharacters(in: .whitespacesAndNewlines)
            if merged.isEmpty {
                merged = chunks[index]
            }
            result.append(merged)
        }

        return result
    }
}
