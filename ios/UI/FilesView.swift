import SwiftUI

struct FilesView: View {
    @State private var files: [URL] = []

    var body: some View {
        List {
            if files.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "folder",
                    description: Text("Import files into the app Documents folder to use them in notes.")
                )
            } else {
                ForEach(files, id: \.absoluteString) { file in
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
        .navigationTitle("Files")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") {
                    refreshFiles()
                }
            }
        }
        .onAppear {
            refreshFiles()
        }
    }

    private func refreshFiles() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let documents else {
            files = []
            return
        }

        do {
            files = try FileManager.default.contentsOfDirectory(
                at: documents,
                includingPropertiesForKeys: nil
            )
            .filter { !$0.hasDirectoryPath }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            files = []
        }
    }
}

