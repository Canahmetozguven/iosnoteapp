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
        let messages = try modelContext.fetch(FetchDescriptor<ChatMessage>())

        let payload = ExportPayloadV1(
            version: 1,
            exportedAt: Date(),
            notes: notes.map { n in
                ExportNoteV1(
                    id: n.id,
                    title: n.title,
                    content: n.content,
                    createdAt: n.createdAt,
                    updatedAt: n.updatedAt,
                    tags: n.tags,
                    embedding: n.embedding
                )
            },
            chatMessages: messages.map { m in
                ExportChatMessageV1(
                    id: m.id,
                    role: m.role,
                    content: m.content,
                    thoughtProcess: m.thoughtProcess,
                    sourceNoteIds: m.sourceNoteIds,
                    createdAt: m.createdAt
                )
            }
        )

        let manifest = ExportManifestV1(
            version: 1,
            createdAt: Date(),
            noteCount: notes.count,
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
            let urls = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
            for file in urls where !file.hasDirectoryPath {
                let entryPath = "Documents/\(file.lastPathComponent)"
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
}

