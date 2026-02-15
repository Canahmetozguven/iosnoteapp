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
        var id: String
        var kind: ModelKind
        var filename: String
        var sha256: String?
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
        guard let url = item.downloadURL else {
            Task { @MainActor in
                self.downloadsVM.setState(.failed(message: "Invalid URL"), for: item.id)
            }
            return
        }

        Task { @MainActor in
            self.downloadsVM.setState(.queued, for: item.id)
        }

        let request = URLRequest(url: url)
        let desc = Descriptor(id: item.id, kind: item.kind, filename: item.filename, sha256: item.sha256)
        let descString = (try? String(data: JSONEncoder().encode(desc), encoding: .utf8)) ?? item.id

        if let resumeData = loadResumeData(modelId: item.id) {
            let task = session.downloadTask(withResumeData: resumeData)
            task.taskDescription = descString
            taskToDescriptor[task.taskIdentifier] = desc
            task.resume()
            return
        }

        let task = session.downloadTask(with: request)
        task.taskDescription = descString
        taskToDescriptor[task.taskIdentifier] = desc
        task.resume()
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
                            self.saveResumeData(resumeData, modelId: modelId)
                            Task { @MainActor in
                                self.downloadsVM.setState(.paused(resumeAvailable: true), for: modelId)
                            }
                        } else {
                            self.deleteResumeData(modelId: modelId)
                            Task { @MainActor in
                                self.downloadsVM.setState(.notStarted, for: modelId)
                            }
                        }
                    }
                } else {
                    t.cancel()
                    self.deleteResumeData(modelId: modelId)
                    Task { @MainActor in
                        self.downloadsVM.setState(.notStarted, for: modelId)
                    }
                }
            }
        }
    }

    func deleteDownloaded(_ item: ModelCatalogItem) throws {
        try storage.delete(item)
        deleteResumeData(modelId: item.id)
        Task { @MainActor in
            self.downloadsVM.setState(.notStarted, for: item.id)
        }
    }

    // MARK: - Resume Data Persistence

    private func resumeFileURL(modelId: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("Models", isDirectory: true).appendingPathComponent(resumeDirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            storage.excludeFromBackup(dir)
        }
        return dir.appendingPathComponent("\(modelId).resume", isDirectory: false)
    }

    private func loadResumeData(modelId: String) -> Data? {
        guard let url = resumeFileURL(modelId: modelId) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func saveResumeData(_ data: Data, modelId: String) {
        guard let url = resumeFileURL(modelId: modelId) else { return }
        try? data.write(to: url, options: .atomic)
        storage.excludeFromBackup(url)
    }

    private func deleteResumeData(modelId: String) {
        guard let url = resumeFileURL(modelId: modelId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - SHA256

    private func verifySHA256IfNeeded(fileURL: URL, expected: String?) -> Bool {
        guard let expected, !expected.isEmpty else { return true }
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return hex.lowercased() == expected.lowercased()
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

        do {
            let dir = try storage.modelsDirectory(for: desc.kind)
            let destURL = dir.appendingPathComponent(desc.filename, isDirectory: false)

            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }

            try FileManager.default.moveItem(at: location, to: destURL)
            storage.excludeFromBackup(destURL)

            if !verifySHA256IfNeeded(fileURL: destURL, expected: desc.sha256) {
                try? FileManager.default.removeItem(at: destURL)
                Task { @MainActor in
                    self.downloadsVM.setState(.failed(message: "SHA256 mismatch"), for: desc.id)
                }
                return
            }

            deleteResumeData(modelId: desc.id)
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
