import SwiftUI

struct FilesView: View {
    @Environment(GlobalViewModel.self) private var vm

    @State private var localFiles: [URL] = []
    @State private var driveFiles: [DriveFile] = []
    @State private var driveError: String?
    @State private var isRefreshing = false

    var body: some View {
        List {
            Section("Drive Files") {
                if !vm.driveSync.isConnected {
                    Text("Connect Google Drive in Settings to see files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isRefreshing && driveFiles.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading Drive files...")
                            .foregroundStyle(.secondary)
                    }
                } else if let driveError {
                    Text(driveError)
                        .font(.caption)
                        .foregroundStyle(AppTheme.redError)
                } else if driveFiles.isEmpty {
                    ContentUnavailableView(
                        "No Drive Files",
                        systemImage: "icloud.slash",
                        description: Text("No files found in your Synaps Notes Drive folder.")
                    )
                } else {
                    ForEach(driveFiles, id: \.id) { file in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name ?? "Unnamed file")
                                .font(.body)
                            HStack(spacing: 8) {
                                if let sizeText = formatSize(file.size) {
                                    Text(sizeText)
                                }
                                if let created = file.createdTime {
                                    Text(formatDriveDate(created))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Local Files") {
                if localFiles.isEmpty {
                    ContentUnavailableView(
                        "No Local Files",
                        systemImage: "folder",
                        description: Text("Import files into the app Documents folder to use them in notes.")
                    )
                } else {
                    ForEach(localFiles, id: \.absoluteString) { file in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.lastPathComponent)
                                .font(.body)
                            Text(file.pathExtension.uppercased())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Files")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") {
                    refresh()
                }
                .disabled(isRefreshing)
            }
        }
        .refreshable {
            refresh()
        }
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        isRefreshing = true
        refreshLocalFiles()

        Task { @MainActor in
            defer { isRefreshing = false }
            driveError = nil
            if vm.driveSync.isConnected {
                do {
                    driveFiles = try await vm.driveSync.listFilesInSynapsFolder()
                } catch {
                    driveFiles = []
                    driveError = "Failed to load Drive files: \(error.localizedDescription)"
                }
            } else {
                driveFiles = []
            }
        }
    }

    private func refreshLocalFiles() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let documents else {
            localFiles = []
            return
        }

        do {
            localFiles = try FileManager.default.contentsOfDirectory(
                at: documents,
                includingPropertiesForKeys: nil
            )
            .filter { !$0.hasDirectoryPath }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            localFiles = []
        }
    }

    private func formatSize(_ sizeString: String?) -> String? {
        guard let sizeString, let bytes = Int64(sizeString) else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDriveDate(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return raw
    }
}
