import Foundation
import SwiftData

@MainActor
@Observable
final class DriveSyncService {
    private enum Key {
        static let folderId = "drive_folder_id_v1"
        static let didAttemptAutoRestore = "drive_did_attempt_auto_restore_v1"
    }

    var isConnected: Bool { auth.isConnected }
    var userEmail: String? { auth.userEmail }

    var isSyncing: Bool = false
    var lastSyncAt: Date? = nil
    var status: String? = nil
    var error: String? = nil

    private let defaults: UserDefaults
    private let auth: DriveAuthManager
    private let api: DriveAPIClient
    private let exporter = BackupExporter()
    private let importer = BackupImporter()

    init(defaults: UserDefaults = .standard, auth: DriveAuthManager = DriveAuthManager(), api: DriveAPIClient = DriveAPIClient()) {
        self.defaults = defaults
        self.auth = auth
        self.api = api
    }

    func connectAndMaybeAutoRestore(modelContext: ModelContext) async {
        error = nil
        status = "Connecting..."
        await auth.connect()
        guard auth.isConnected else {
            error = auth.lastError
            status = nil
            return
        }
        status = "Connected"

        // Auto restore only once, only if local data is empty.
        if !defaults.bool(forKey: Key.didAttemptAutoRestore) {
            defaults.set(true, forKey: Key.didAttemptAutoRestore)
            do {
                if try await isLocalEmpty(modelContext: modelContext) {
                    status = "Checking backups..."
                    try await auth.refreshTokenIfNeeded()
                    guard let token = auth.accessToken else { throw DriveAPIError.notAuthenticated }
                    let folderId = try await ensureFolderId(accessToken: token)
                    let backups = try await api.listBackups(inFolderId: folderId, accessToken: token)
                    if let latest = backups.first, let id = Optional(latest.id) {
                        status = "Restoring..."
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("drive-restore.zip", isDirectory: false)
                        try await api.downloadFile(fileId: id, to: tmp, accessToken: token)
                        try importer.importZip(from: tmp, modelContext: modelContext)
                        status = "Restored latest backup"
                    } else {
                        status = "No backups found"
                    }
                }
            } catch {
                self.error = error.localizedDescription
                self.status = nil
            }
        }
    }

    func disconnect() {
        auth.disconnect()
        status = nil
        error = nil
    }

    func syncNow(modelContext: ModelContext) async {
        error = nil
        guard auth.isConnected else {
            error = "Not connected"
            return
        }
        isSyncing = true
        status = "Preparing backup..."
        defer { isSyncing = false }

        do {
            try await auth.refreshTokenIfNeeded()
            guard let token = auth.accessToken else { throw DriveAPIError.notAuthenticated }
            let folderId = try await ensureFolderId(accessToken: token)

            let localURL = try exporter.exportZip(modelContext: modelContext)
            let name = localURL.lastPathComponent.hasPrefix("synapsnotes-backup-") ? localURL.lastPathComponent : "synapsnotes-backup-\(Int(Date().timeIntervalSince1970)).zip"
            let mime = localURL.pathExtension.lowercased() == "zip" ? "application/zip" : "application/json"
            status = "Uploading..."
            _ = try await api.uploadResumable(fileURL: localURL, fileName: name, mimeType: mime, folderId: folderId, accessToken: token)
            lastSyncAt = Date()
            status = "Sync complete"
        } catch {
            self.error = error.localizedDescription
            self.status = nil
        }
    }

    private func ensureFolderId(accessToken: String) async throws -> String {
        if let cached = defaults.string(forKey: Key.folderId), !cached.isEmpty {
            return cached
        }
        if let found = try await api.findFolderId(named: "Synaps Notes", accessToken: accessToken) {
            defaults.set(found, forKey: Key.folderId)
            return found
        }
        let created = try await api.createFolder(named: "Synaps Notes", accessToken: accessToken)
        defaults.set(created, forKey: Key.folderId)
        return created
    }

    private func isLocalEmpty(modelContext: ModelContext) async throws -> Bool {
        let notes = try modelContext.fetchCount(FetchDescriptor<Note>())
        let msgs = try modelContext.fetchCount(FetchDescriptor<ChatMessage>())
        if notes > 0 || msgs > 0 { return false }

        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let urls = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            if urls.contains(where: { !$0.hasDirectoryPath }) { return false }
        }
        return true
    }
}

