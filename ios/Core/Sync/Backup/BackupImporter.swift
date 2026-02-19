import Foundation
import SwiftData

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

final class BackupImporter {
    func importZip(from localURL: URL, modelContext: ModelContext) throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("synapsnotes-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        #if canImport(ZIPFoundation)
        guard let archive = Archive(url: localURL, accessMode: .read) else {
            throw BackupError.failedToCreateArchive
        }
        for entry in archive {
            let dest = tmpDir.appendingPathComponent(entry.path, isDirectory: false)
            let parent = dest.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: dest)
        }
        #else
        // Fallback: treat as export.json directly.
        let dest = tmpDir.appendingPathComponent("export.json", isDirectory: false)
        try FileManager.default.copyItem(at: localURL, to: dest)
        #endif

        let exportURL = tmpDir.appendingPathComponent("export.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: exportURL.path) else {
            throw BackupError.missingExportJSON
        }

        let data = try Data(contentsOf: exportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ExportPayloadV1.self, from: data)

        // Insert notes/messages. Caller should ensure local store is empty for auto-restore.
        for n in payload.notes {
            modelContext.insert(Note(
                id: n.id,
                title: n.title,
                content: n.content,
                createdAt: n.createdAt,
                updatedAt: n.updatedAt,
                tags: n.tags,
                embedding: n.embedding,
                embeddingModelId: n.embeddingModelId,
                embeddingUpdatedAt: n.embeddingUpdatedAt,
                embeddingContentHash: n.embeddingContentHash,
                titleNormalized: n.titleNormalized,
                contentTokenCount: n.contentTokenCount
            ))
        }

        var documentsById: [UUID: KnowledgeDocument] = [:]
        if let exportedDocuments = payload.knowledgeDocuments {
            for d in exportedDocuments {
                let document = KnowledgeDocument(
                    id: d.id,
                    title: d.title,
                    sourceType: d.sourceType,
                    mimeType: d.mimeType,
                    localRelativePath: d.localRelativePath,
                    driveFileId: d.driveFileId,
                    extractionStatus: d.extractionStatus,
                    extractionError: d.extractionError,
                    extractionEngine: d.extractionEngine,
                    contentHash: d.contentHash,
                    createdAt: d.createdAt,
                    updatedAt: d.updatedAt
                )
                modelContext.insert(document)
                documentsById[d.id] = document
            }
        }

        if let exportedChunks = payload.knowledgeChunks {
            for c in exportedChunks {
                modelContext.insert(KnowledgeChunk(
                    id: c.id,
                    chunkIndex: c.chunkIndex,
                    pageNumber: c.pageNumber,
                    text: c.text,
                    embedding: c.embedding,
                    embeddingModelId: c.embeddingModelId,
                    embeddingUpdatedAt: c.embeddingUpdatedAt,
                    embeddingContentHash: c.embeddingContentHash,
                    tokenCount: c.tokenCount,
                    charCount: c.charCount,
                    sectionHint: c.sectionHint,
                    documentTitleNormalized: c.documentTitleNormalized,
                    createdAt: c.createdAt,
                    updatedAt: c.updatedAt,
                    document: c.documentId.flatMap { documentsById[$0] }
                ))
            }
        }

        var sessionsById: [UUID: ChatSession] = [:]
        if let exportedSessions = payload.chatSessions, !exportedSessions.isEmpty {
            for s in exportedSessions {
                let session = ChatSession(
                    id: s.id,
                    title: s.title,
                    createdAt: s.createdAt,
                    updatedAt: s.updatedAt
                )
                modelContext.insert(session)
                sessionsById[s.id] = session
            }
        }

        var fallbackSession: ChatSession? = sessionsById.values.first
        if !payload.chatMessages.isEmpty && sessionsById.isEmpty {
            let legacy = ChatSession(title: "Legacy Chat")
            modelContext.insert(legacy)
            fallbackSession = legacy
        }

        for m in payload.chatMessages {
            let session = m.sessionId.flatMap { sessionsById[$0] } ?? fallbackSession
            modelContext.insert(ChatMessage(
                id: m.id,
                role: m.role,
                content: m.content,
                thoughtProcess: m.thoughtProcess,
                sourceNoteIds: m.sourceNoteIds,
                sourceKnowledgeChunkIds: m.sourceKnowledgeChunkIds ?? [],
                createdAt: m.createdAt,
                session: session
            ))
        }

        // Restore Documents files if present.
        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let restoredDocs = tmpDir.appendingPathComponent("Documents", isDirectory: true)
            if FileManager.default.fileExists(atPath: restoredDocs.path) {
                let files = recursiveFiles(in: restoredDocs)
                for src in files where !src.hasDirectoryPath {
                    let relative = src.path.replacingOccurrences(of: restoredDocs.path + "/", with: "")
                    let dest = docsDir.appendingPathComponent(relative, isDirectory: false)
                    try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try? FileManager.default.removeItem(at: dest)
                    }
                    try? FileManager.default.copyItem(at: src, to: dest)
                }
            }
        }
    }

    private func recursiveFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            files.append(url)
        }
        return files
    }
}
