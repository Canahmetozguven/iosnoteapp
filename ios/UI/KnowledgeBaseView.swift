import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct KnowledgeBaseView: View {
    @Environment(GlobalViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KnowledgeDocument.updatedAt, order: .reverse) private var documents: [KnowledgeDocument]
    @Query private var chunks: [KnowledgeChunk]

    @State private var showingFileImporter = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var driveFiles: [DriveFile] = []
    @State private var driveError: String?
    @State private var loadingDrive = false

    var body: some View {
        List {
            Section("Import") {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import from Files", systemImage: "doc.badge.plus")
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Label("Import from Photos", systemImage: "photo.badge.plus")
                }

                if let status = vm.knowledgeImportStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Drive Import") {
                if !vm.driveSync.isConnected {
                    Text("Connect Google Drive in Settings to import docs from Synaps Notes folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if loadingDrive {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading Drive files...")
                            .foregroundStyle(.secondary)
                    }
                } else if let driveError {
                    Text(driveError)
                        .font(.caption)
                        .foregroundStyle(AppTheme.redError)
                } else if driveFiles.isEmpty {
                    Text("No importable Drive files found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(driveFiles, id: \.id) { file in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name ?? "Drive File")
                                if let mime = file.mimeType {
                                    Text(mime)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Import") {
                                vm.importKnowledgeDriveFile(file, modelContext: modelContext)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("Documents") {
                if documents.isEmpty {
                    ContentUnavailableView(
                        "No Knowledge Documents",
                        systemImage: "book.closed",
                        description: Text("Import PDFs, images, and text files to build your on-device knowledge base.")
                    )
                } else {
                    ForEach(documents) { document in
                        NavigationLink {
                            KnowledgeDocumentDetailView(document: document)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : document.title)
                                    .font(.body)
                                HStack(spacing: 8) {
                                    Text(document.extractionStatus.capitalized)
                                    Text(document.mimeType)
                                    Text(document.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                vm.deleteKnowledgeDocument(document, modelContext: modelContext)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Knowledge Base")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") {
                    refreshDriveFiles()
                }
                .disabled(loadingDrive)
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .text],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                vm.importKnowledgeFiles(urls: urls, sourceType: .localFile, modelContext: modelContext)
            case .failure(let error):
                vm.knowledgeImportStatus = "Import failed: \(error.localizedDescription)"
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), !data.isEmpty {
                    await MainActor.run {
                        vm.importKnowledgeImageData(data, suggestedName: "photo.jpg", modelContext: modelContext)
                    }
                } else {
                    await MainActor.run {
                        vm.knowledgeImportStatus = "Unable to load selected photo"
                    }
                }
            }
        }
        .refreshable {
            refreshDriveFiles()
        }
        .onAppear {
            refreshDriveFiles()
            vm.startAutoIndexKnowledgeIfNeeded(chunks: chunks, modelContext: modelContext)
        }
        .onChange(of: vm.isEmbeddingModelLoaded) {
            if vm.isEmbeddingModelLoaded {
                vm.startAutoIndexKnowledgeIfNeeded(chunks: chunks, modelContext: modelContext)
            }
        }
    }

    private func refreshDriveFiles() {
        guard vm.driveSync.isConnected else {
            driveFiles = []
            driveError = nil
            return
        }
        loadingDrive = true
        Task { @MainActor in
            defer { loadingDrive = false }
            do {
                let files = try await vm.driveSync.listFilesInSynapsFolder()
                driveFiles = files.filter { file in
                    let mime = (file.mimeType ?? "").lowercased()
                    if mime.contains("pdf") || mime.hasPrefix("image/") || mime.hasPrefix("text/") {
                        return true
                    }
                    let ext = URL(fileURLWithPath: file.name ?? "").pathExtension.lowercased()
                    return ["pdf", "txt", "md", "png", "jpg", "jpeg", "heic", "webp"].contains(ext)
                }
                driveError = nil
            } catch {
                driveFiles = []
                driveError = "Failed to load Drive files: \(error.localizedDescription)"
            }
        }
    }
}

private struct KnowledgeDocumentDetailView: View {
    let document: KnowledgeDocument
    @Query private var chunks: [KnowledgeChunk]

    init(document: KnowledgeDocument) {
        self.document = document
        let id = document.id
        _chunks = Query(
            filter: #Predicate<KnowledgeChunk> { $0.document?.id == id },
            sort: [SortDescriptor(\KnowledgeChunk.chunkIndex, order: .forward)]
        )
    }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Status", value: document.extractionStatus.capitalized)
                LabeledContent("Source", value: document.sourceType)
                LabeledContent("Type", value: document.mimeType)
                LabeledContent("Engine", value: document.extractionEngine ?? "N/A")
                LabeledContent("Updated", value: document.updatedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Chunks", value: "\(chunks.count)")
                if let error = document.extractionError, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(AppTheme.redError)
                        .font(.caption)
                }
            }

            Section("Extracted Content") {
                if chunks.isEmpty {
                    Text("No extracted text chunks")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(chunks, id: \.id) { chunk in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Chunk \(chunk.chunkIndex + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(chunk.text)
                                .font(.body)
                                .textSelection(.enabled)
                                .lineLimit(8)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
