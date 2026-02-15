import Foundation

enum ModelStorageError: Error {
    case failedToCreateDirectory
    case missingDownloadURL
}

final class ModelStorage {
    static let shared = ModelStorage()

    private init() {}

    private func baseURL() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ModelStorageError.failedToCreateDirectory
        }
        let url = base.appendingPathComponent("Models", isDirectory: true)
        try ensureDirectory(url)
        return url
    }

    func modelsDirectory(for kind: ModelKind) throws -> URL {
        let dir = try baseURL().appendingPathComponent(kind.rawValue, isDirectory: true)
        try ensureDirectory(dir)
        return dir
    }

    func fileURL(for item: ModelCatalogItem) throws -> URL {
        let dir = try modelsDirectory(for: item.kind)
        let url = dir.appendingPathComponent(item.filename, isDirectory: false)
        return url
    }

    func exists(_ item: ModelCatalogItem) -> Bool {
        do {
            let url = try fileURL(for: item)
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            return false
        }
    }

    func fileSize(_ item: ModelCatalogItem) -> Int64? {
        do {
            let url = try fileURL(for: item)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? NSNumber { return size.int64Value }
            return nil
        } catch {
            return nil
        }
    }

    func delete(_ item: ModelCatalogItem) throws {
        let url = try fileURL(for: item)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }

    private func ensureDirectory(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ModelStorageError.failedToCreateDirectory
        }
        excludeFromBackup(url)
    }
}

