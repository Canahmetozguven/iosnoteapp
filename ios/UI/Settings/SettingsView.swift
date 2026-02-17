import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(GlobalViewModel.self) var vm
    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [Note]
    @Query private var knowledgeChunks: [KnowledgeChunk]
    @AppStorage(OnboardingState.completionKey) private var hasCompletedOnboarding = false

    @State private var showingAddCustomModel = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Cloud Backup") {
                    if vm.driveSync.isConnected {
                        if let email = vm.driveSync.userEmail {
                            Text("Connected: \(email)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let last = vm.driveSync.lastSyncAt {
                            Text("Last sync: \(last.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if vm.driveSync.isSyncing {
                            ProgressView()
                        }

                        if let status = vm.driveSync.status {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let error = vm.driveSync.error {
                            Text("Error: \(error)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.redError)
                        }

                        Button("Sync Now") {
                            Task { await vm.driveSync.syncNow(modelContext: modelContext) }
                        }
                        .disabled(vm.driveSync.isSyncing)

                        Button(role: .destructive) {
                            vm.driveSync.disconnect()
                        } label: {
                            Text("Disconnect")
                        }
                    } else {
                        if let status = vm.driveSync.status {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let error = vm.driveSync.error {
                            Text("Error: \(error)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.redError)
                        }

                        Button("Connect Google Drive") {
                            Task { await vm.driveSync.connectAndMaybeAutoRestore(modelContext: modelContext) }
                        }

                        Text("On first connect, the app auto-restores the latest backup if local data is empty.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Status") {
                    HStack {
                        Text("Chat Model")
                        Spacer()
                        Text(vm.displayName(for: vm.currentChatModelId))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Embedding Model")
                        Spacer()
                        Text(vm.displayName(for: vm.currentEmbeddingModelId))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Vision Model")
                        Spacer()
                        Text(vm.displayName(for: vm.currentOCRModelId))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("OCR Backend")
                        Spacer()
                        Text(vm.useModelOCRForImports ? "Vision Model" : "Apple Vision")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Chats")
                        Spacer()
                        Text("\(vm.sessions.count)")
                            .foregroundStyle(.secondary)
                    }
                    if let error = vm.modelError {
                        Text("Error: \(error)")
                            .foregroundStyle(AppTheme.redError)
                            .font(.caption)
                    }
                }

                Section("Chat Models") {
                    let items = vm.catalogStore.items(kind: .chat)
                    if items.isEmpty {
                        Text("No models in catalog.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            ModelRow(
                                item: item,
                                isActive: vm.currentChatModelId == item.id && vm.isChatModelLoaded,
                                isInstalled: vm.isInstalled(item),
                                downloadState: vm.downloads.state(for: item.id),
                                isBusy: vm.isBusy,
                                isEnabled: true,
                                onGet: { vm.startDownload(item) },
                                onCancel: { vm.cancelDownload(modelId: item.id) },
                                onLoad: { vm.loadChatModel(item: item) },
                                onReload: { vm.reloadChatModel(item: item) },
                                onOffload: { vm.offloadAllModels() },
                                onDelete: { vm.deleteDownloaded(item) }
                            )
                        }
                    }
                }

                Section("Embedding Models") {
                    let items = vm.catalogStore.items(kind: .embedding)
                    if items.isEmpty {
                        Text("No models in catalog.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            ModelRow(
                                item: item,
                                isActive: vm.currentEmbeddingModelId == item.id && vm.isEmbeddingModelLoaded,
                                isInstalled: vm.isInstalled(item),
                                downloadState: vm.downloads.state(for: item.id),
                                isBusy: vm.isBusy,
                                isEnabled: true,
                                onGet: { vm.startDownload(item) },
                                onCancel: { vm.cancelDownload(modelId: item.id) },
                                onLoad: { vm.loadEmbeddingModel(item: item) },
                                onReload: { vm.reloadEmbeddingModel(item: item) },
                                onOffload: { vm.offloadAllModels() },
                                onDelete: { vm.deleteDownloaded(item) }
                            )
                        }
                    }
                }

                Section("Vision Models (OCR/VL)") {
                    Toggle("Use Vision Model For OCR Imports", isOn: Bindable(vm).useModelOCRForImports)

                    let items = (vm.catalogStore.items(kind: .ocr) + vm.catalogStore.items(kind: .vl))
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    if items.isEmpty {
                        Text("No vision models in catalog. Add one in Custom Models.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            ModelRow(
                                item: item,
                                isActive: vm.currentOCRModelId == item.id && vm.isOCRModelLoaded,
                                isInstalled: vm.isInstalled(item),
                                downloadState: vm.downloads.state(for: item.id),
                                isBusy: vm.isBusy,
                                isEnabled: vm.useModelOCRForImports,
                                onGet: { vm.startDownload(item) },
                                onCancel: { vm.cancelDownload(modelId: item.id) },
                                onLoad: { vm.loadOCRModel(item: item) },
                                onReload: { vm.reloadOCRModel(item: item) },
                                onOffload: { vm.offloadAllModels() },
                                onDelete: { vm.deleteDownloaded(item) }
                            )
                        }
                    }

                    Text("Default OCR uses Apple Vision. Enable the toggle above to use the selected local OCR/VL model for imports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !vm.useModelOCRForImports {
                        Text("Vision model actions are locked while Apple Vision OCR is active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("When enabled, vision models load only during import and auto-offload after use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Custom Models") {
                    Button {
                        showingAddCustomModel = true
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Custom Model")
                        }
                    }

                    Text("Tip: paste a Hugging Face direct .gguf link (resolve/main/...).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Performance") {
                    Toggle("Low Power Mode", isOn: Bindable(vm).isLowPowerMode)
                    Text("Forces CPU usage and reduces context size (2048). Recommended for resource-constrained environments.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("RAG") {
                    let indexedCount = vm.indexedCountForActiveEmbedding(notes: notes)
                    let indexedChunkCount = vm.indexedKnowledgeChunkCountForActiveEmbedding(chunks: knowledgeChunks)

                    HStack {
                        Text("Fresh embeddings")
                        Spacer()
                        Text("\(indexedCount)/\(notes.count) indexed")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Knowledge chunks")
                        Spacer()
                        Text("\(indexedChunkCount)/\(knowledgeChunks.count) indexed")
                            .foregroundStyle(.secondary)
                    }

                    if vm.indexingProgress > 0 && vm.indexingProgress < 1.0 {
                        ProgressView(value: vm.indexingProgress)
                    }

                    if let status = vm.indexingStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Indexing is automatic. Notes and Knowledge Base chunks are re-embedded when chat needs fresh context.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Reindex Knowledge Base") {
                        vm.reindexKnowledgeBase(chunks: knowledgeChunks, modelContext: modelContext)
                    }
                    .disabled(!vm.isEmbeddingModelLoaded || vm.isIndexing || knowledgeChunks.isEmpty)
                }

                Section("Help") {
                    Button {
                        hasCompletedOnboarding = false
                    } label: {
                        Label("Show Onboarding Again", systemImage: "list.bullet.rectangle.portrait")
                    }

                    Text("Replay the quick guide for notes, model setup, chat workflow, and backup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [Color(.systemGroupedBackground), Color(.secondarySystemGroupedBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Settings")
            .onAppear {
                vm.bootstrapIfNeeded(modelContext: modelContext)
                vm.startAutoIndexIfNeeded(notes: notes, modelContext: modelContext)
                vm.startAutoIndexKnowledgeIfNeeded(chunks: knowledgeChunks, modelContext: modelContext)
            }
            .sheet(isPresented: $showingAddCustomModel) {
                AddCustomModelSheet(vm: vm)
            }
        }
    }
}

private struct ModelRow: View {
    let item: ModelCatalogItem
    let isActive: Bool
    let isInstalled: Bool
    let downloadState: DownloadState
    let isBusy: Bool
    let isEnabled: Bool

    let onGet: () -> Void
    let onCancel: () -> Void
    let onLoad: () -> Void
    let onReload: () -> Void
    let onOffload: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteConfirm = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusIndicator

            Menu {
                actionMenuContent
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .disabled(!isEnabled)
            .buttonStyle(.bordered)
        }
        .opacity(isEnabled ? 1.0 : 0.45)
        .alert("Delete Model?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will remove \(item.name) from local storage.")
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch downloadState {
        case .downloading(let progress, _, _):
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .queued:
            Text("Queued")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(isActive ? AppTheme.greenSuccess : AppTheme.primary)
                    .accessibilityLabel(isActive ? "Loaded model" : "Downloaded model")
            }
        }
    }

    @ViewBuilder
    private var actionMenuContent: some View {
        switch downloadState {
        case .downloading(let progress, _, _):
            Button("Cancel Download (\(Int(progress * 100))%)") { onCancel() }

        case .queued:
            Button("Cancel Download") { onCancel() }

        case .paused:
            Button("Resume Download") { onGet() }

        case .failed:
            Button("Retry Download") { onGet() }

        case .completed, .notStarted:
            if isInstalled {
                if !isActive {
                    Button("Load Model") { onLoad() }
                        .disabled(isBusy)
                }
                Button("Reload Model") { onReload() }
                    .disabled(isBusy)
                Section {
                    Button("Offload") { onOffload() }
                        .disabled(isBusy)
                }
                Section {
                    Button("Delete Model", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                    .disabled(isBusy)
                }
            } else {
                Button("Get Model") { onGet() }
                    .disabled(isBusy)
            }
        }
    }
}

private struct AddCustomModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: GlobalViewModel

    @State private var kind: ModelKind = .chat
    @State private var name: String = ""
    @State private var subtitle: String = ""
    @State private var url: String = ""
    @State private var filename: String = ""
    @State private var id: String = ""
    @State private var sha256: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $kind) {
                    Text("Chat").tag(ModelKind.chat)
                    Text("Embedding").tag(ModelKind.embedding)
                    Text("OCR").tag(ModelKind.ocr)
                    Text("VL").tag(ModelKind.vl)
                }

                TextField("Name", text: $name)
                TextField("Subtitle (optional)", text: $subtitle)
                TextField("URL", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Filename", text: $filename)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("ID", text: $id)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("SHA256 (optional)", text: $sha256)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text("IDs must be unique. Filenames must end in .gguf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Add Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: url) { _, newValue in
                if filename.isEmpty, let suggested = suggestedFilename(from: newValue) {
                    filename = suggested
                }
                if id.isEmpty, let suggested = suggestedId(from: newValue) {
                    id = suggested
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        url.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("http") &&
        filename.lowercased().hasSuffix(".gguf") &&
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let item = ModelCatalogItem(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : subtitle,
            filename: filename.trimmingCharacters(in: .whitespacesAndNewlines),
            auxiliaryFilename: nil,
            auxiliaryURL: nil,
            auxiliarySha256: nil,
            modality: kind == .ocr ? "vision_ocr" : (kind == .vl ? "vision" : nil),
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            sizeBytes: nil,
            sha256: sha256.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sha256
        )
        vm.catalogStore.addCustom(item)
        dismiss()
    }

    private func suggestedFilename(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let last = url.pathComponents.last
        guard let last, last.lowercased().hasSuffix(".gguf") else { return nil }
        return last
    }

    private func suggestedId(from urlString: String) -> String? {
        guard let f = suggestedFilename(from: urlString) else { return nil }
        return f
            .replacingOccurrences(of: ".gguf", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}
