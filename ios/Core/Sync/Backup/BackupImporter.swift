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
                embedding: n.embedding
            ))
        }
        for m in payload.chatMessages {
            modelContext.insert(ChatMessage(
                id: m.id,
                role: m.role,
                content: m.content,
                thoughtProcess: m.thoughtProcess,
                sourceNoteIds: m.sourceNoteIds,
                createdAt: m.createdAt
            ))
        }

        // Restore Documents files if present.
        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let restoredDocs = tmpDir.appendingPathComponent("Documents", isDirectory: true)
            if FileManager.default.fileExists(atPath: restoredDocs.path) {
                let files = (try? FileManager.default.contentsOfDirectory(at: restoredDocs, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for src in files where !src.hasDirectoryPath {
                    let dest = uniqueDestination(for: src.lastPathComponent, in: docsDir)
                    try? FileManager.default.copyItem(at: src, to: dest)
                }
            }
        }
    }

    private func uniqueDestination(for filename: String, in dir: URL) -> URL {
        let base = dir.appendingPathComponent(filename, isDirectory: false)
        if !FileManager.default.fileExists(atPath: base.path) {
            return base
        }
        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        var i = 1
        while true {
            let candidateName = ext.isEmpty ? "\(stem)-restored-\(i)" : "\(stem)-restored-\(i).\(ext)"
            let candidate = dir.appendingPathComponent(candidateName, isDirectory: false)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}

