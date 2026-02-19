import Foundation

struct ChunkedTextUnit: Hashable {
    var text: String
    var pageNumber: Int?
}

final class TextChunkingService {
    func chunk(text: String, chunkSize: Int = 800, overlap: Int = 120) -> [String] {
        chunkWithMetadata(text: text, chunkSize: chunkSize, overlap: overlap).map(\.text)
    }

    func chunkWithMetadata(text: String, chunkSize: Int = 800, overlap: Int = 120) -> [ChunkedTextUnit] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }
        return chunkSingle(normalized, chunkSize: chunkSize, overlap: overlap).map {
            ChunkedTextUnit(text: $0, pageNumber: nil)
        }
    }

    // Page-first strategy: keep each page as an independent retrieval unit.
    // If a page is too long, split only within that page.
    func chunkPages(_ pages: [String], chunkSize: Int = 800, overlap: Int = 120) -> [String] {
        chunkPagesWithMetadata(pages, chunkSize: chunkSize, overlap: overlap).map(\.text)
    }

    func chunkPagesWithMetadata(_ pages: [String], chunkSize: Int = 800, overlap: Int = 120) -> [ChunkedTextUnit] {
        guard !pages.isEmpty else { return [] }

        var result: [ChunkedTextUnit] = []
        for (pageIndex, page) in pages.enumerated() {
            let normalizedPage = normalize(page)
            guard !normalizedPage.isEmpty else { continue }
            let pageChunks = chunkSingle(normalizedPage, chunkSize: chunkSize, overlap: overlap)
            result.append(contentsOf: pageChunks.map {
                ChunkedTextUnit(text: $0, pageNumber: pageIndex + 1)
            })
        }
        return result
    }

    private let knownAbbreviations: Set<String> = [
        "mr.", "mrs.", "ms.", "dr.", "prof.", "sr.", "jr.", "st.", "mt.",
        "vs.", "etc.", "e.g.", "i.e.", "u.s.", "u.k.", "u.s.a.",
        "inc.", "ltd.", "co.", "corp.", "no.", "fig.", "al."
    ]

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
            let rawEnd = trimmed.index(start, offsetBy: maxLength, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            var end = rawEnd
            if rawEnd < trimmed.endIndex {
                let adjusted = alignBackwardToWordBoundary(in: trimmed, from: rawEnd, lowerBound: start)
                if adjusted > start {
                    end = adjusted
                }
            }
            let part = String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty {
                units.append(part)
            }
            if end >= trimmed.endIndex {
                break
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
            if shouldIgnoreSentenceBoundary(in: text, boundaryStart: boundary.lowerBound) {
                continue
            }
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

            let previousTail = overlapTail(from: chunks[index - 1], overlap: overlap)
            var merged = previousTail.isEmpty ? chunks[index] : "\(previousTail)\n\(chunks[index])"
            if merged.count > maxLength {
                merged = trimToWordBoundary(merged, maxLength: maxLength)
            }
            merged = merged.trimmingCharacters(in: .whitespacesAndNewlines)
            if merged.isEmpty {
                merged = chunks[index]
            }
            result.append(merged)
        }

        return result
    }

    private func shouldIgnoreSentenceBoundary(in text: String, boundaryStart: String.Index) -> Bool {
        guard boundaryStart > text.startIndex else { return false }
        let punctuationIndex = text.index(before: boundaryStart)
        guard text[punctuationIndex] == "." else { return false }

        let token = trailingToken(in: text, upTo: punctuationIndex).lowercased()
        if token.isEmpty {
            return false
        }
        if knownAbbreviations.contains(token) {
            return true
        }
        if token.range(of: #"^(?:[a-z]\.){2,}[a-z]?\.$"#, options: .regularExpression) != nil {
            return true
        }

        if token.range(of: #"^[a-z]\.$"#, options: .regularExpression) != nil,
           let next = firstNonWhitespaceCharacter(in: text, from: boundaryStart),
           next.isLowercase {
            return true
        }

        return false
    }

    private func trailingToken(in text: String, upTo end: String.Index) -> String {
        var start = end
        while start > text.startIndex {
            let prev = text.index(before: start)
            let ch = text[prev]
            if ch.isWhitespace || ch.isNewline {
                break
            }
            start = prev
        }
        return String(text[start...end])
    }

    private func firstNonWhitespaceCharacter(in text: String, from index: String.Index) -> Character? {
        var cursor = index
        while cursor < text.endIndex {
            let ch = text[cursor]
            if !(ch.isWhitespace || ch.isNewline) {
                return ch
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private func overlapTail(from text: String, overlap: Int) -> String {
        guard overlap > 0, !text.isEmpty else { return "" }
        guard text.count > overlap else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let rawStart = text.index(text.endIndex, offsetBy: -overlap)
        let alignedStart = alignForwardToWordBoundary(in: text, from: rawStart, upperBound: text.endIndex)
        if alignedStart < text.endIndex {
            return String(text[alignedStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(text[rawStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trimToWordBoundary(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else {
            return text
        }
        let rawEnd = text.index(text.startIndex, offsetBy: maxLength)
        let alignedEnd = alignBackwardToWordBoundary(in: text, from: rawEnd, lowerBound: text.startIndex)
        let end = alignedEnd > text.startIndex ? alignedEnd : rawEnd
        return String(text[..<end])
    }

    private func alignForwardToWordBoundary(in text: String, from index: String.Index, upperBound: String.Index) -> String.Index {
        guard index < upperBound else { return upperBound }
        var cursor = index

        if cursor > text.startIndex {
            let prev = text[text.index(before: cursor)]
            let current = text[cursor]
            if isWordCharacter(prev) && isWordCharacter(current) {
                while cursor < upperBound, isWordCharacter(text[cursor]) {
                    cursor = text.index(after: cursor)
                }
                while cursor < upperBound, !isWordCharacter(text[cursor]) {
                    cursor = text.index(after: cursor)
                }
            }
        }
        return cursor
    }

    private func alignBackwardToWordBoundary(in text: String, from index: String.Index, lowerBound: String.Index) -> String.Index {
        guard index > lowerBound else { return lowerBound }
        guard index < text.endIndex else { return index }
        let prev = text[text.index(before: index)]
        let current = text[index]
        guard isWordCharacter(prev), isWordCharacter(current) else {
            return index
        }

        var cursor = index
        while cursor > lowerBound, isWordCharacter(text[text.index(before: cursor)]) {
            cursor = text.index(before: cursor)
        }
        return cursor
    }

    private func isWordCharacter(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}
