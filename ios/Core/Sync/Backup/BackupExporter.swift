import Foundation
import SwiftData

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

enum BackupError: Error {
    case failedToCreateArchive
    case missingDocumentsDirectory
    case missingExportJSON
}

final class BackupExporter {
    func exportZip(modelContext: ModelContext) throws -> URL {
        let notes = try modelContext.fetch(FetchDescriptor<Note>())
        let documents = try modelContext.fetch(FetchDescriptor<KnowledgeDocument>())
        let chunks = try modelContext.fetch(FetchDescriptor<KnowledgeChunk>())
        let sessions = try modelContext.fetch(FetchDescriptor<ChatSession>())
        let messages = try modelContext.fetch(FetchDescriptor<ChatMessage>())

        let payload = ExportPayloadV1(
            version: 4,
            exportedAt: Date(),
            notes: notes.map { n in
                ExportNoteV1(
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
                )
            },
            knowledgeDocuments: documents.map { d in
                ExportKnowledgeDocumentV1(
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
            },
            knowledgeChunks: chunks.map { c in
                ExportKnowledgeChunkV1(
                    id: c.id,
                    documentId: c.document?.id,
                    chunkIndex: c.chunkIndex,
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
                    updatedAt: c.updatedAt
                )
            },
            chatSessions: sessions.map { s in
                ExportChatSessionV1(
                    id: s.id,
                    title: s.title,
                    createdAt: s.createdAt,
                    updatedAt: s.updatedAt
                )
            },
            chatMessages: messages.map { m in
                ExportChatMessageV1(
                    id: m.id,
                    role: m.role,
                    content: m.content,
                    thoughtProcess: m.thoughtProcess,
                    sourceNoteIds: m.sourceNoteIds,
                    sourceKnowledgeChunkIds: m.sourceKnowledgeChunkIds,
                    createdAt: m.createdAt,
                    sessionId: m.session?.id
                )
            }
        )

        let manifest = ExportManifestV1(
            version: 4,
            createdAt: Date(),
            noteCount: notes.count,
            knowledgeDocumentCount: documents.count,
            knowledgeChunkCount: chunks.count,
            chatSessionCount: sessions.count,
            chatMessageCount: messages.count,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let exportData = try encoder.encode(payload)
        let manifestData = try encoder.encode(manifest)

        let tmp = FileManager.default.temporaryDirectory
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        let zipURL = tmp.appendingPathComponent("synapsnotes-backup-\(stamp).zip", isDirectory: false)
        try? FileManager.default.removeItem(at: zipURL)

        #if canImport(ZIPFoundation)
        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            throw BackupError.failedToCreateArchive
        }

        try archive.addEntry(
            with: "export.json",
            type: .file,
            uncompressedSize: UInt32(exportData.count),
            compressionMethod: .deflate,
            provider: { pos, size in
                let start = Int(pos)
                let end = min(exportData.count, start + Int(size))
                return exportData.subdata(in: start..<end)
            }
        )

        try archive.addEntry(
            with: "manifest.json",
            type: .file,
            uncompressedSize: UInt32(manifestData.count),
            compressionMethod: .deflate,
            provider: { pos, size in
                let start = Int(pos)
                let end = min(manifestData.count, start + Int(size))
                return manifestData.subdata(in: start..<end)
            }
        )

        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let urls = recursiveDocumentFiles(in: docs)
            for file in urls where !file.hasDirectoryPath {
                let relative = file.path.replacingOccurrences(of: docs.path + "/", with: "")
                let entryPath = "Documents/\(relative)"
                _ = try? archive.addEntry(with: entryPath, fileURL: file, compressionMethod: .deflate)
            }
        }

        return zipURL
        #else
        // Fallback: write JSON only (no zip) so sync can still function.
        let jsonURL = tmp.appendingPathComponent("synapsnotes-export-\(stamp).json", isDirectory: false)
        try exportData.write(to: jsonURL, options: .atomic)
        return jsonURL
        #endif
    }

    private func recursiveDocumentFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            files.append(url)
        }
        return files
    }
}
