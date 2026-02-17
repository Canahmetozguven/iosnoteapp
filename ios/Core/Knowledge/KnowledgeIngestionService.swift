import Foundation
import CryptoKit

struct IngestedKnowledgeDocument {
    var title: String
    var mimeType: String
    var relativePath: String
    var sourceType: KnowledgeSourceType
    var driveFileId: String?
    var extractionResult: DocumentExtractionResult
    var chunks: [String]
    var contentHash: String
}

final class KnowledgeIngestionService {
    private let storage = KnowledgeStorage()
    private let extractor = DocumentTextExtractionService()
    private let chunking = TextChunkingService()

    func ingestLocalFile(
        sourceURL: URL,
        sourceType: KnowledgeSourceType,
        driveFileId: String? = nil,
        llamaContext: LlamaContext?,
        preferOCRModel: Bool
    ) async throws -> IngestedKnowledgeDocument {
        let stored = try storage.storeImportedFile(from: sourceURL)
        let extraction = try await extractor.extractText(
            from: stored.absoluteURL,
            mimeType: stored.mimeType,
            llamaContext: llamaContext,
            preferOCRModel: preferOCRModel
        )
        let chunks: [String]
        if let pages = extraction.pages, !pages.isEmpty {
            chunks = chunking.chunkPages(pages, chunkSize: 800, overlap: 120)
        } else {
            chunks = chunking.chunk(text: extraction.text, chunkSize: 800, overlap: 120)
        }
        let hash = sha256(extraction.text)

        return IngestedKnowledgeDocument(
            title: stored.title.isEmpty ? sourceURL.lastPathComponent : stored.title,
            mimeType: stored.mimeType,
            relativePath: stored.relativePath,
            sourceType: sourceType,
            driveFileId: driveFileId,
            extractionResult: extraction,
            chunks: chunks,
            contentHash: hash
        )
    }

    func ingestImageData(
        _ data: Data,
        suggestedName: String,
        llamaContext: LlamaContext?,
        preferOCRModel: Bool
    ) async throws -> IngestedKnowledgeDocument {
        let stored = try storage.storeImageData(data, suggestedName: suggestedName)
        let extraction = try await extractor.extractText(
            from: stored.absoluteURL,
            mimeType: stored.mimeType,
            llamaContext: llamaContext,
            preferOCRModel: preferOCRModel
        )
        let chunks: [String]
        if let pages = extraction.pages, !pages.isEmpty {
            chunks = chunking.chunkPages(pages, chunkSize: 800, overlap: 120)
        } else {
            chunks = chunking.chunk(text: extraction.text, chunkSize: 800, overlap: 120)
        }
        let hash = sha256(extraction.text)

        return IngestedKnowledgeDocument(
            title: stored.title,
            mimeType: stored.mimeType,
            relativePath: stored.relativePath,
            sourceType: .photo,
            driveFileId: nil,
            extractionResult: extraction,
            chunks: chunks,
            contentHash: hash
        )
    }

    func resolveDocumentURL(relativePath: String) throws -> URL {
        try storage.resolve(relativePath: relativePath)
    }

    func deleteStoredFile(relativePath: String) {
        storage.delete(relativePath: relativePath)
    }

    private func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
