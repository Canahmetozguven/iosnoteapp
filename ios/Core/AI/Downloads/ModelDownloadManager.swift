import Foundation
import CryptoKit

final class ModelDownloadManager: NSObject {
    static let shared = ModelDownloadManager()

    private let storage = ModelStorage.shared
    private let downloadsVM: ModelDownloadsViewModel

    // Background URLSession completion callback (owned by AppDelegate).
    var backgroundSessionCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.synapsnotes.ios.model-downloads")
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    struct Descriptor: Codable {
        enum Stage: String, Codable {
            case primary
            case auxiliary
        }

        var id: String
        var kind: ModelKind
        var filename: String
        var sha256: String?
        var url: String
        var stage: Stage
        var auxiliaryFilename: String?
        var auxiliaryURL: String?
        var auxiliarySha256: String?

        var resumeKey: String {
            "\(id)__\(filename)"
        }
    }

    // taskId -> descriptor mapping (best-effort; taskDescription is source of truth across restarts)
    private var taskToDescriptor: [Int: Descriptor] = [:]
    private let resumeDirName = "_resume"

    private override init() {
        self.downloadsVM = ModelDownloadsViewModel()
        super.init()
        restorePendingTasks()
    }

    func viewModel() -> ModelDownloadsViewModel {
        downloadsVM
    }

    func restorePendingTasks() {
        session.getAllTasks { tasks in
            Task { @MainActor in
                for task in tasks {
                    guard
                        let s = task.taskDescription,
                        let data = s.data(using: .utf8),
                        let desc = try? JSONDecoder().decode(Descriptor.self, from: data)
                    else { continue }
                    self.taskToDescriptor[task.taskIdentifier] = desc
                    if task.state == .running || task.state == .suspended {
                        self.downloadsVM.setState(.queued, for: desc.id)
                    }
                }
            }
        }
    }

    func startDownload(_ item: ModelCatalogItem) {
        guard item.downloadURL != nil else {
            Task { @MainActor in
                self.downloadsVM.setState(.failed(message: "Invalid URL"), for: item.id)
            }
            return
        }

        Task { @MainActor in
            self.downloadsVM.setState(.queued, for: item.id)
        }

        let hasAuxiliary = (item.auxiliaryFilename?.isEmpty == false) && (item.auxiliaryURL?.isEmpty == false)
        let primaryExists = fileExists(kind: item.kind, filename: item.filename)
        let auxiliaryExists = hasAuxiliary ? fileExists(kind: item.kind, filename: item.auxiliaryFilename ?? "") : true

        if primaryExists && auxiliaryExists {
            Task { @MainActor in
                self.downloadsVM.setState(.completed, for: item.id)
            }
            return
        }

        if primaryExists && hasAuxiliary {
            guard let auxDesc = makeAuxiliaryDescriptor(from: item) else {
                Task { @MainActor in
                    self.downloadsVM.setState(.failed(message: "Invalid auxiliary model URL"), for: item.id)
                }
                return
            }
            enqueueDownload(auxDesc)
            return
        }

        guard let primaryDesc = makePrimaryDescriptor(from: item) else {
            Task { @MainActor in
                self.downloadsVM.setState(.failed(message: "Invalid model URL"), for: item.id)
            }
            return
        }
        enqueueDownload(primaryDesc)
    }

    func cancelDownload(modelId: String) {
        session.getAllTasks { tasks in
            for t in tasks {
                guard
                    let s = t.taskDescription,
                    let data = s.data(using: .utf8),
                    let desc = try? JSONDecoder().decode(Descriptor.self, from: data),
                    desc.id == modelId
                else { continue }
                if let dt = t as? URLSessionDownloadTask {
                    dt.cancel { resumeData in
                        if let resumeData {
                            self.saveResumeData(resumeData, key: desc.resumeKey)
                            Task { @MainActor in
                                self.downloadsVM.setState(.paused(resumeAvailable: true), for: modelId)
                            }
                        } else {
                            self.deleteResumeData(key: desc.resumeKey)
                            Task { @MainActor in
                                self.downloadsVM.setState(.notStarted, for: modelId)
                            }
                        }
                    }
                } else {
                    t.cancel()
                    self.deleteResumeData(key: desc.resumeKey)
                    Task { @MainActor in
                        self.downloadsVM.setState(.notStarted, for: modelId)
                    }
                }
            }
        }
    }

    func deleteDownloaded(_ item: ModelCatalogItem) throws {
        try storage.delete(item)
        deleteAllResumeData(modelId: item.id)
        Task { @MainActor in
            self.downloadsVM.setState(.notStarted, for: item.id)
        }
    }

    // MARK: - Resume Data Persistence

    private func resumeFileURL(key: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("Models", isDirectory: true).appendingPathComponent(resumeDirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            storage.excludeFromBackup(dir)
        }
        return dir.appendingPathComponent("\(key).resume", isDirectory: false)
    }

    private func loadResumeData(key: String) -> Data? {
        guard let url = resumeFileURL(key: key) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func saveResumeData(_ data: Data, key: String) {
        guard let url = resumeFileURL(key: key) else { return }
        try? data.write(to: url, options: .atomic)
        storage.excludeFromBackup(url)
    }

    private func deleteResumeData(key: String) {
        guard let url = resumeFileURL(key: key) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func deleteAllResumeData(modelId: String) {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let dir = base.appendingPathComponent("Models", isDirectory: true).appendingPathComponent(resumeDirName, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        for entry in entries where entry.lastPathComponent.hasPrefix("\(modelId)__") {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    // MARK: - SHA256

    private func verifySHA256IfNeeded(fileURL: URL, expected: String?) -> Bool {
        guard let expected, !expected.isEmpty else { return true }
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return hex.lowercased() == expected.lowercased()
    }

    private func fileExists(kind: ModelKind, filename: String) -> Bool {
        guard !filename.isEmpty else { return false }
        do {
            let dir = try storage.modelsDirectory(for: kind)
            let url = dir.appendingPathComponent(filename, isDirectory: false)
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            return false
        }
    }

    private func makePrimaryDescriptor(from item: ModelCatalogItem) -> Descriptor? {
        guard let url = item.downloadURL else { return nil }
        return Descriptor(
            id: item.id,
            kind: item.kind,
            filename: item.filename,
            sha256: item.sha256,
            url: url.absoluteString,
            stage: .primary,
            auxiliaryFilename: item.auxiliaryFilename,
            auxiliaryURL: item.auxiliaryURL,
            auxiliarySha256: item.auxiliarySha256
        )
    }

    private func makeAuxiliaryDescriptor(from item: ModelCatalogItem) -> Descriptor? {
        guard let filename = item.auxiliaryFilename, !filename.isEmpty,
              let url = item.auxiliaryURL, URL(string: url) != nil else {
            return nil
        }
        return Descriptor(
            id: item.id,
            kind: item.kind,
            filename: filename,
            sha256: item.auxiliarySha256,
            url: url,
            stage: .auxiliary,
            auxiliaryFilename: nil,
            auxiliaryURL: nil,
            auxiliarySha256: nil
        )
    }

    private func makeAuxiliaryDescriptor(from primary: Descriptor) -> Descriptor? {
        guard let filename = primary.auxiliaryFilename, !filename.isEmpty,
              let auxURL = primary.auxiliaryURL, URL(string: auxURL) != nil else {
            return nil
        }
        return Descriptor(
            id: primary.id,
            kind: primary.kind,
            filename: filename,
            sha256: primary.auxiliarySha256,
            url: auxURL,
            stage: .auxiliary,
            auxiliaryFilename: nil,
            auxiliaryURL: nil,
            auxiliarySha256: nil
        )
    }

    private func enqueueDownload(_ desc: Descriptor) {
        guard let url = URL(string: desc.url) else {
            Task { @MainActor in
                self.downloadsVM.setState(.failed(message: "Invalid download URL"), for: desc.id)
            }
            return
        }

        let descString = (try? String(data: JSONEncoder().encode(desc), encoding: .utf8)) ?? desc.id
        if let resumeData = loadResumeData(key: desc.resumeKey) {
            let task = session.downloadTask(withResumeData: resumeData)
            task.taskDescription = descString
            taskToDescriptor[task.taskIdentifier] = desc
            task.resume()
            return
        }

        let task = session.downloadTask(with: URLRequest(url: url))
        task.taskDescription = descString
        taskToDescriptor[task.taskIdentifier] = desc
        task.resume()
    }
}

extension ModelDownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let desc = descriptor(for: downloadTask) else { return }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let progress: Double
        if let total {
            progress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(total)))
        } else {
            progress = 0
        }
        Task { @MainActor in
            self.downloadsVM.setState(.downloading(progress: progress, bytesWritten: totalBytesWritten, totalBytes: total), for: desc.id)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let desc = descriptor(for: downloadTask) else { return }
        Task { @MainActor in
            self.downloadsVM.setState(.queued, for: desc.id)
        }

        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            deleteResumeData(key: desc.resumeKey)
            Task { @MainActor in
                self.downloadsVM.setState(.failed(message: "HTTP \(http.statusCode) while downloading model"), for: desc.id)
            }
            return
        }

        do {
            let dir = try storage.modelsDirectory(for: desc.kind)
            let destURL = dir.appendingPathComponent(desc.filename, isDirectory: false)

            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }

            try FileManager.default.moveItem(at: location, to: destURL)
            storage.excludeFromBackup(destURL)

            if desc.filename.lowercased().hasSuffix(".gguf"), !isGGUFFile(fileURL: destURL) {
                try? FileManager.default.removeItem(at: destURL)
                Task { @MainActor in
                    self.downloadsVM.setState(.failed(message: "Downloaded file is not a valid GGUF model"), for: desc.id)
                }
                return
            }

            if !verifySHA256IfNeeded(fileURL: destURL, expected: desc.sha256) {
                try? FileManager.default.removeItem(at: destURL)
                Task { @MainActor in
                    self.downloadsVM.setState(.failed(message: "SHA256 mismatch"), for: desc.id)
                }
                return
            }

            deleteResumeData(key: desc.resumeKey)

            if desc.stage == .primary, let auxDesc = makeAuxiliaryDescriptor(from: desc), !fileExists(kind: auxDesc.kind, filename: auxDesc.filename) {
                Task { @MainActor in
                    self.downloadsVM.setState(.queued, for: desc.id)
                }
                enqueueDownload(auxDesc)
                return
            }

            Task { @MainActor in
                self.downloadsVM.setState(.completed, for: desc.id)
            }
        } catch {
            Task { @MainActor in
                self.downloadsVM.setState(.failed(message: error.localizedDescription), for: desc.id)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let desc = descriptor(for: task) else { return }
        if let error = error as? URLError, error.code == .cancelled {
            return
        }
        if let error {
            Task { @MainActor in
                self.downloadsVM.setState(.failed(message: error.localizedDescription), for: desc.id)
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundSessionCompletionHandler?()
            self.backgroundSessionCompletionHandler = nil
        }
    }
}

private extension ModelDownloadManager {
    func isGGUFFile(fileURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), let data, data.count == 4 else { return false }
        return data == Data([0x47, 0x47, 0x55, 0x46]) // "GGUF"
    }

    func descriptor(for task: URLSessionTask) -> Descriptor? {
        if let cached = taskToDescriptor[task.taskIdentifier] {
            return cached
        }
        guard
            let s = task.taskDescription,
            let data = s.data(using: .utf8),
            let desc = try? JSONDecoder().decode(Descriptor.self, from: data)
        else { return nil }
        taskToDescriptor[task.taskIdentifier] = desc
        return desc
    }
}
