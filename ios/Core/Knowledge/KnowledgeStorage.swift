import Foundation
import UniformTypeIdentifiers

enum KnowledgeSourceType: String, CaseIterable {
    case localFile = "local_file"
    case photo = "photo"
    case drive = "drive"
}

struct StoredKnowledgeFile {
    var title: String
    var mimeType: String
    var relativePath: String
    var absoluteURL: URL
}

final class KnowledgeStorage {
    private let baseDirName = "KnowledgeBase"

    func storeImportedFile(from sourceURL: URL, preferredTitle: String? = nil) throws -> StoredKnowledgeFile {
        let ext = sourceURL.pathExtension.lowercased()
        let fileName = "\(UUID().uuidString).\(ext.isEmpty ? "bin" : ext)"
        let destination = try baseDirectory().appendingPathComponent(fileName, isDirectory: false)

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let type = UTType(filenameExtension: ext)
        let mimeType = type?.preferredMIMEType ?? "application/octet-stream"
        let title = preferredTitle ?? sourceURL.deletingPathExtension().lastPathComponent

        return StoredKnowledgeFile(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sourceURL.lastPathComponent : title,
            mimeType: mimeType,
            relativePath: fileName,
            absoluteURL: destination
        )
    }

    func storeImageData(_ data: Data, suggestedName: String = "photo.jpg") throws -> StoredKnowledgeFile {
        let ext = URL(fileURLWithPath: suggestedName).pathExtension.lowercased()
        let fileName = "\(UUID().uuidString).\(ext.isEmpty ? "jpg" : ext)"
        let destination = try baseDirectory().appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: destination, options: .atomic)

        let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "image/jpeg"
        let title = URL(fileURLWithPath: suggestedName).deletingPathExtension().lastPathComponent

        return StoredKnowledgeFile(
            title: title.isEmpty ? "Imported Image" : title,
            mimeType: mime,
            relativePath: fileName,
            absoluteURL: destination
        )
    }

    func resolve(relativePath: String) throws -> URL {
        try baseDirectory().appendingPathComponent(relativePath, isDirectory: false)
    }

    func delete(relativePath: String) {
        guard let url = try? resolve(relativePath: relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func baseDirectory() throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "KnowledgeStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Documents directory"])
        }
        let dir = docs.appendingPathComponent(baseDirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
