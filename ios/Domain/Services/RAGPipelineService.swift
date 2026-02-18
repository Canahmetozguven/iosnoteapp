import Foundation

enum RAGRetrievalProfile: String, CaseIterable, Codable, Identifiable {
    case fastRecommended
    case balanced
    case deepSearch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fastRecommended:
            return "Fast (Recommended)"
        case .balanced:
            return "Balanced"
        case .deepSearch:
            return "Deep Search"
        }
    }

    var description: String {
        switch self {
        case .fastRecommended:
            return "Usually answers quickest using the most relevant notes and documents."
        case .balanced:
            return "Takes a little longer to check more sources for stronger accuracy."
        case .deepSearch:
            return "Checks the most context for best grounding, but may be slower."
        }
    }

    fileprivate var maxCandidates: Int {
        switch self {
        case .fastRecommended: return 20
        case .balanced: return 40
        case .deepSearch: return 80
        }
    }

    fileprivate var maxResults: Int {
        switch self {
        case .fastRecommended: return 3
        case .balanced: return 4
        case .deepSearch: return 5
        }
    }

    fileprivate var semanticWeight: Float {
        switch self {
        case .fastRecommended: return 0.78
        case .balanced: return 0.75
        case .deepSearch: return 0.70
        }
    }

    fileprivate var lexicalWeight: Float { 1 - semanticWeight }

    fileprivate var minimumFusedScore: Float {
        switch self {
        case .fastRecommended: return 0.42
        case .balanced: return 0.34
        case .deepSearch: return 0.28
        }
    }

    fileprivate var maxChunksPerDocument: Int {
        switch self {
        case .fastRecommended: return 1
        case .balanced: return 2
        case .deepSearch: return 2
        }
    }
}

enum RetrievalConfidence: String, Codable {
    case none
    case low
    case medium
    case high

    var summaryText: String {
        switch self {
        case .none: return "none"
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }
}

struct CitationRef: Hashable, Codable {
    enum SourceType: String, Codable {
        case note
        case knowledgeChunk
    }

    var id: String
    var sourceType: SourceType
    var title: String
    var chunkIndex: Int?
    var noteId: UUID?
    var chunkId: UUID?
    var snippet: String
}

struct RetrievalResult {
    var selectedNotes: [Note]
    var selectedChunks: [KnowledgeChunk]
    var citations: [CitationRef]
    var confidence: RetrievalConfidence
    var usedEmbeddings: Bool
    var topScore: Float?

    var selectedCount: Int {
        selectedNotes.count + selectedChunks.count
    }

    static let empty = RetrievalResult(
        selectedNotes: [],
        selectedChunks: [],
        citations: [],
        confidence: .none,
        usedEmbeddings: false,
        topScore: nil
    )
}

final class RAGPipelineService {
    private enum CandidateSource {
        case note(Note)
        case chunk(KnowledgeChunk)
    }

    private struct ScoredCandidate {
        var source: CandidateSource
        var fusedScore: Float
        var lexicalScore: Float
        var usedSemantic: Bool
        var fingerprint: String
        var documentId: UUID?
    }

    private let vectorSearchService = VectorSearchService()
    private let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from",
        "how", "i", "in", "is", "it", "me", "my", "of", "on", "or", "our", "that",
        "the", "their", "there", "they", "this", "to", "was", "we", "what", "when",
        "where", "which", "who", "why", "with", "you", "your"
    ]

    func retrieveContext(
        queryText: String,
        queryEmbedding: [Float]?,
        notes: [Note],
        chunks: [KnowledgeChunk],
        noteBoosts: [UUID: Float] = [:],
        chunkBoosts: [UUID: Float] = [:],
        semanticNoteIds: Set<UUID> = [],
        semanticChunkIds: Set<UUID> = [],
        profile: RAGRetrievalProfile
    ) -> RetrievalResult {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .empty }

        let queryTokens = tokenize(query)
        let normalizedQuery = normalizeText(query)
        var candidates: [ScoredCandidate] = []
        candidates.reserveCapacity(notes.count + chunks.count)
        let embeddingEnabled = (queryEmbedding?.isEmpty == false)

        for note in notes {
            let semantic = semanticScore(
                for: note,
                queryEmbedding: queryEmbedding,
                semanticNoteIds: semanticNoteIds
            )
            let lexical = lexicalScore(
                queryTokens: queryTokens,
                normalizedQuery: normalizedQuery,
                title: note.title,
                body: note.content
            )
            guard let fused = fusedScore(
                semantic: semantic,
                lexical: lexical,
                profile: profile
            ) else { continue }
            let adjustedScore = adjustedFusedScore(fused, boost: noteBoosts[note.id] ?? 0)

            let fingerprint = fingerprintKey(
                sourceTitle: note.title,
                sourceText: note.content
            )
            candidates.append(
                ScoredCandidate(
                    source: .note(note),
                    fusedScore: adjustedScore,
                    lexicalScore: lexical,
                    usedSemantic: semantic != nil,
                    fingerprint: fingerprint,
                    documentId: nil
                )
            )
        }

        for chunk in chunks {
            let semantic = semanticScore(
                for: chunk,
                queryEmbedding: queryEmbedding,
                semanticChunkIds: semanticChunkIds
            )
            let title = chunk.document?.title ?? ""
            let lexical = lexicalScore(
                queryTokens: queryTokens,
                normalizedQuery: normalizedQuery,
                title: title,
                body: chunk.text
            )
            guard let fused = fusedScore(
                semantic: semantic,
                lexical: lexical,
                profile: profile
            ) else { continue }
            let adjustedScore = adjustedFusedScore(fused, boost: chunkBoosts[chunk.id] ?? 0)

            let fingerprint = fingerprintKey(
                sourceTitle: title,
                sourceText: chunk.text
            )
            candidates.append(
                ScoredCandidate(
                    source: .chunk(chunk),
                    fusedScore: adjustedScore,
                    lexicalScore: lexical,
                    usedSemantic: semantic != nil,
                    fingerprint: fingerprint,
                    documentId: chunk.document?.id
                )
            )
        }

        guard !candidates.isEmpty else {
            return .empty
        }

        let ranked = candidates
            .sorted { lhs, rhs in
                if lhs.fusedScore == rhs.fusedScore {
                    return lhs.lexicalScore > rhs.lexicalScore
                }
                return lhs.fusedScore > rhs.fusedScore
            }
            .prefix(profile.maxCandidates)

        let filtered = ranked.filter { candidate in
            candidate.fusedScore >= profile.minimumFusedScore
        }
        let activeCandidates: [ScoredCandidate]
        if filtered.isEmpty {
            guard let top = ranked.first else {
                return .empty
            }
            let relaxedThreshold = profile.minimumFusedScore * 0.75
            if top.fusedScore < relaxedThreshold && (!top.usedSemantic || top.lexicalScore < 0.45) {
                return .empty
            }
            activeCandidates = [top]
        } else {
            activeCandidates = Array(filtered)
        }
        let selected = diversifyAndBalance(activeCandidates, profile: profile)
        guard !selected.isEmpty else { return .empty }

        let topScore = selected.first?.fusedScore
        let confidence = confidenceLevel(topScore: topScore, count: selected.count)
        let ordered = selected.sorted { $0.fusedScore > $1.fusedScore }

        var selectedNotes: [Note] = []
        var selectedChunks: [KnowledgeChunk] = []
        var citations: [CitationRef] = []
        citations.reserveCapacity(ordered.count)

        for (index, candidate) in ordered.enumerated() {
            let citationId = "S\(index + 1)"
            switch candidate.source {
            case .note(let note):
                selectedNotes.append(note)
                let snippet = contextSnippet(from: note.content)
                let title = resolvedNoteTitle(note)
                citations.append(
                    CitationRef(
                        id: citationId,
                        sourceType: .note,
                        title: title,
                        chunkIndex: nil,
                        noteId: note.id,
                        chunkId: nil,
                        snippet: snippet
                    )
                )

            case .chunk(let chunk):
                selectedChunks.append(chunk)
                let snippet = contextSnippet(from: chunk.text)
                let rawTitle = chunk.document?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = rawTitle.isEmpty ? "Document" : rawTitle
                citations.append(
                    CitationRef(
                        id: citationId,
                        sourceType: .knowledgeChunk,
                        title: title,
                        chunkIndex: chunk.chunkIndex + 1,
                        noteId: nil,
                        chunkId: chunk.id,
                        snippet: snippet
                    )
                )
            }
        }

        return RetrievalResult(
            selectedNotes: selectedNotes,
            selectedChunks: selectedChunks,
            citations: citations,
            confidence: confidence,
            usedEmbeddings: embeddingEnabled,
            topScore: topScore
        )
    }

    private func semanticScore(
        for note: Note,
        queryEmbedding: [Float]?,
        semanticNoteIds: Set<UUID>
    ) -> Float? {
        guard semanticNoteIds.contains(note.id) else {
            return nil
        }
        guard let queryEmbedding,
              let embedding = note.embedding,
              embedding.count == queryEmbedding.count else {
            return nil
        }
        return vectorSearchService.scoreEmbedding(queryEmbedding: queryEmbedding, candidateEmbedding: embedding)
    }

    private func semanticScore(
        for chunk: KnowledgeChunk,
        queryEmbedding: [Float]?,
        semanticChunkIds: Set<UUID>
    ) -> Float? {
        guard semanticChunkIds.contains(chunk.id) else {
            return nil
        }
        guard let queryEmbedding,
              let embedding = chunk.embedding,
              embedding.count == queryEmbedding.count else {
            return nil
        }
        return vectorSearchService.scoreEmbedding(queryEmbedding: queryEmbedding, candidateEmbedding: embedding)
    }

    private func fusedScore(
        semantic: Float?,
        lexical: Float,
        profile: RAGRetrievalProfile
    ) -> Float? {
        if let semantic {
            return max(0, (semantic * profile.semanticWeight) + (lexical * profile.lexicalWeight))
        }
        guard lexical > 0 else { return nil }
        return lexical * 0.65
    }

    private func lexicalScore(
        queryTokens: Set<String>,
        normalizedQuery: String,
        title: String,
        body: String
    ) -> Float {
        guard !queryTokens.isEmpty else { return 0 }
        let normalizedTitle = normalizeText(title)
        let normalizedBody = normalizeText(body)
        let titleTokens = tokenize(normalizedTitle)
        let bodyTokens = tokenize(normalizedBody)
        let titleOverlap = queryTokens.intersection(titleTokens).count
        let bodyOverlap = queryTokens.intersection(bodyTokens).count
        if titleOverlap == 0 && bodyOverlap == 0 {
            return 0
        }

        let tokenDenominator = Float(max(1, queryTokens.count))
        var score = (Float(bodyOverlap) / tokenDenominator) * 0.7
        score += (Float(titleOverlap) / tokenDenominator) * 0.5

        if normalizedQuery.count >= 8,
           (!normalizedTitle.isEmpty && normalizedTitle.contains(normalizedQuery) ||
            !normalizedBody.isEmpty && normalizedBody.contains(normalizedQuery)) {
            score += 0.15
        }

        return min(1.0, score)
    }

    private func diversifyAndBalance(
        _ candidates: [ScoredCandidate],
        profile: RAGRetrievalProfile
    ) -> [ScoredCandidate] {
        guard !candidates.isEmpty else { return [] }

        var selected: [ScoredCandidate] = []
        var selectedFingerprints: Set<String> = []
        var chunkPerDocumentCount: [UUID: Int] = [:]

        let bestNote = candidates.first(where: {
            if case .note = $0.source { return true }
            return false
        })
        let bestChunk = candidates.first(where: {
            if case .chunk = $0.source { return true }
            return false
        })

        if let bestNote {
            selected.append(bestNote)
            selectedFingerprints.insert(bestNote.fingerprint)
        }
        if let bestChunk {
            if let top = selected.first {
                let scoreGap = abs(top.fusedScore - bestChunk.fusedScore)
                if scoreGap <= 0.18, selected.count < profile.maxResults {
                    selected.append(bestChunk)
                    selectedFingerprints.insert(bestChunk.fingerprint)
                    if let docId = bestChunk.documentId {
                        chunkPerDocumentCount[docId] = 1
                    }
                }
            } else {
                selected.append(bestChunk)
                selectedFingerprints.insert(bestChunk.fingerprint)
                if let docId = bestChunk.documentId {
                    chunkPerDocumentCount[docId] = 1
                }
            }
        }

        for candidate in candidates {
            guard selected.count < profile.maxResults else { break }
            if selected.contains(where: { sameSource($0, candidate) }) { continue }
            if selectedFingerprints.contains(candidate.fingerprint) { continue }

            if case .chunk = candidate.source,
               let docId = candidate.documentId,
               (chunkPerDocumentCount[docId] ?? 0) >= profile.maxChunksPerDocument {
                continue
            }

            selected.append(candidate)
            selectedFingerprints.insert(candidate.fingerprint)
            if case .chunk = candidate.source, let docId = candidate.documentId {
                chunkPerDocumentCount[docId, default: 0] += 1
            }
        }

        return selected
    }

    private func sameSource(_ lhs: ScoredCandidate, _ rhs: ScoredCandidate) -> Bool {
        switch (lhs.source, rhs.source) {
        case (.note(let left), .note(let right)):
            return left.id == right.id
        case (.chunk(let left), .chunk(let right)):
            return left.id == right.id
        default:
            return false
        }
    }

    private func confidenceLevel(topScore: Float?, count: Int) -> RetrievalConfidence {
        guard let topScore, count > 0 else { return .none }
        if topScore >= 0.74 || (topScore >= 0.66 && count >= 2) {
            return .high
        }
        if topScore >= 0.54 {
            return .medium
        }
        if topScore >= 0.40 {
            return .low
        }
        return .none
    }

    private func adjustedFusedScore(_ score: Float, boost: Float) -> Float {
        let clampedBoost = max(-0.2, min(0.2, boost))
        return max(0, min(1.2, score + clampedBoost))
    }

    private func contextSnippet(from text: String, maxLength: Int = 550) -> String {
        String(text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedNoteTitle(_ note: Note) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled Note" : title
    }

    private func fingerprintKey(sourceTitle: String, sourceText: String) -> String {
        let merged = normalizeText(sourceTitle + " " + sourceText)
        return String(merged.prefix(180))
    }

    private func tokenize(_ text: String) -> Set<String> {
        let normalized = normalizeText(text)
        let components = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let tokens = components.filter { token in
            token.count >= 2 && !stopWords.contains(token)
        }
        return Set(tokens)
    }

    private func normalizeText(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
