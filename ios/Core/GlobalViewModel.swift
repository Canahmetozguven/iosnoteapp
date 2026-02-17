import Foundation
import SwiftUI
import SwiftData
import CryptoKit
import UniformTypeIdentifiers

@MainActor
@Observable
class GlobalViewModel {
    let catalogStore = ModelCatalogStore()
    let downloads = ModelDownloadManager.shared.viewModel()
    private let downloadManager = ModelDownloadManager.shared
    let driveSync = DriveSyncService()
    private let knowledgeIngestionService = KnowledgeIngestionService()
    var llamaContext = LlamaContext()
    let vectorSearchService = VectorSearchService()

    private enum PreferenceKey {
        static let activeChatModelId = "active_chat_model_id"
        static let activeEmbeddingModelId = "active_embedding_model_id"
        static let activeOCRModelId = "active_ocr_model_id"
        static let useModelOCRForImports = "use_model_ocr_for_imports"
        static let lowPowerMode = "low_power_mode"
        static let activeChatSessionId = "active_chat_session_id"
    }

    private enum SessionDefaults {
        static let legacyTitle = "Legacy Chat"
        static let newChatTitle = "New Chat"
    }

    enum RAGStatus: Equatable {
        case ready
        case disabledNoEmbeddingModel
        case preparingModel
        case preparingIndex
        case timedOut
        case noIndexedNotes
        case usedContext(count: Int)
        case failed(String)
    }

    private let defaults = UserDefaults.standard

    var isChatModelLoaded = false
    var isEmbeddingModelLoaded = false
    var isOCRModelLoaded = false
    var isChatModelLoading = false
    var isEmbeddingModelLoading = false
    var isOCRModelLoading = false
    var isGenerating = false
    var isIndexing = false
    var isImportingKnowledge = false

    var isBusy: Bool {
        isChatModelLoading || isEmbeddingModelLoading || isOCRModelLoading || isGenerating || isIndexing || isImportingKnowledge
    }

    var hasLoadedModels: Bool {
        isChatModelLoaded || isEmbeddingModelLoaded || isOCRModelLoaded
    }

    var currentChatModelId: String? = nil
    var currentEmbeddingModelId: String? = nil
    var currentOCRModelId: String? = nil

    var modelError: String? = nil
    var ragStatus: RAGStatus = .ready
    var retrievedContext: [Note] = []
    var retrievedKnowledgeContext: [KnowledgeChunk] = []
    var lastRAGPreparedNotesCount: Int = 0
    var lastRAGPreparedChunksCount: Int = 0
    var lastRAGEligibleNotesCount: Int = 0
    var lastRAGEligibleChunksCount: Int = 0
    var lastRAGRetrievedCount: Int = 0
    var lastRAGRetrievedTitles: [String] = []
    var lastRAGRetrievedDocumentTitles: [String] = []
    var knowledgeImportStatus: String? = nil

    // Chat state (session-aware and persisted in SwiftData).
    var sessions: [ChatSession] = []
    var activeSessionId: UUID? = nil
    var chatMessages: [ChatMessage] = []

    // Defaults:
    // - Simulator: true (no practical Metal acceleration for this app flow)
    // - Physical devices: false (prefer GPU/Metal)
    var isLowPowerMode: Bool = false {
        didSet {
            defaults.set(isLowPowerMode, forKey: PreferenceKey.lowPowerMode)
        }
    }

    // Default OCR backend for imports is Apple Vision.
    // Local OCR/VL model is opt-in via Settings.
    var useModelOCRForImports: Bool = false {
        didSet {
            defaults.set(useModelOCRForImports, forKey: PreferenceKey.useModelOCRForImports)
        }
    }

    // Progress for indexing (0.0 to 1.0)
    var indexingProgress: Double = 0.0
    var indexingStatus: String? = nil

    private var hasBootstrappedData = false
    private var isModelRehydrateInProgress = false
    private var generationTask: Task<Void, Never>?
    private var pendingAutoIndexTasks: [UUID: Task<Void, Never>] = [:]
    private var ocrAutoUnloadTask: Task<Void, Never>?
    private var ocrLastUsedAt: Date?

    init() {
        if defaults.object(forKey: PreferenceKey.lowPowerMode) != nil {
            isLowPowerMode = defaults.bool(forKey: PreferenceKey.lowPowerMode)
        } else {
            #if targetEnvironment(simulator)
            isLowPowerMode = true
            #else
            isLowPowerMode = false
            #endif
            defaults.set(isLowPowerMode, forKey: PreferenceKey.lowPowerMode)
        }
        currentChatModelId = defaults.string(forKey: PreferenceKey.activeChatModelId)
        currentEmbeddingModelId = defaults.string(forKey: PreferenceKey.activeEmbeddingModelId)
        currentOCRModelId = defaults.string(forKey: PreferenceKey.activeOCRModelId)
        if defaults.object(forKey: PreferenceKey.useModelOCRForImports) != nil {
            useModelOCRForImports = defaults.bool(forKey: PreferenceKey.useModelOCRForImports)
        } else {
            useModelOCRForImports = false
            defaults.set(false, forKey: PreferenceKey.useModelOCRForImports)
        }
        if let rawSessionId = defaults.string(forKey: PreferenceKey.activeChatSessionId) {
            activeSessionId = UUID(uuidString: rawSessionId)
        }
    }

    // MARK: - Bootstrap and Session Management

    func bootstrapIfNeeded(modelContext: ModelContext) {
        guard !hasBootstrappedData else { return }
        hasBootstrappedData = true

        do {
            try migrateUngroupedMessagesIntoLegacySession(modelContext: modelContext)
            try ensureAtLeastOneSession(modelContext: modelContext)
            try refreshSessions(modelContext: modelContext)
            if let selected = restoreSelectedSession() {
                selectSession(selected, modelContext: modelContext)
            } else if let first = sessions.first {
                selectSession(first, modelContext: modelContext)
            }
        } catch {
            modelError = "Failed to bootstrap chat history: \(error.localizedDescription)"
        }
    }

    func createNewChatSession(modelContext: ModelContext) {
        let session = ChatSession(title: SessionDefaults.newChatTitle)
        modelContext.insert(session)
        try? modelContext.save()
        try? refreshSessions(modelContext: modelContext)
        selectSession(session, modelContext: modelContext)
    }

    func renameChatSession(_ session: ChatSession, title: String, modelContext: ModelContext) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.title = trimmed
        session.updatedAt = Date()
        try? modelContext.save()
        try? refreshSessions(modelContext: modelContext)
    }

    func deleteChatSession(_ session: ChatSession, modelContext: ModelContext) {
        if activeSessionId == session.id {
            stopGeneration()
        }

        modelContext.delete(session)
        try? modelContext.save()
        try? refreshSessions(modelContext: modelContext)

        if sessions.isEmpty {
            createNewChatSession(modelContext: modelContext)
            return
        }

        if activeSessionId == session.id, let first = sessions.first {
            selectSession(first, modelContext: modelContext)
        }
    }

    func selectSession(_ session: ChatSession, modelContext: ModelContext) {
        activeSessionId = session.id
        defaults.set(session.id.uuidString, forKey: PreferenceKey.activeChatSessionId)
        loadMessages(for: session, modelContext: modelContext)
    }

    func activeSession() -> ChatSession? {
        sessions.first(where: { $0.id == activeSessionId })
    }

    // MARK: - Model Handling

    func displayName(for modelId: String?) -> String {
        guard let modelId else { return "None" }
        return catalogStore.items.first(where: { $0.id == modelId })?.name ?? modelId
    }

    func isInstalled(_ item: ModelCatalogItem) -> Bool {
        ModelStorage.shared.exists(item)
    }

    func startDownload(_ item: ModelCatalogItem) {
        downloadManager.startDownload(item)
    }

    func cancelDownload(modelId: String) {
        downloadManager.cancelDownload(modelId: modelId)
    }

    func deleteDownloaded(_ item: ModelCatalogItem) {
        do {
            if currentChatModelId == item.id { unloadChatModel() }
            if currentEmbeddingModelId == item.id { unloadEmbeddingModel() }
            if currentOCRModelId == item.id { unloadOCRModel() }
            try downloadManager.deleteDownloaded(item)
        } catch {
            modelError = error.localizedDescription
        }
    }

    func loadChatModel(item: ModelCatalogItem) {
        Task { @MainActor in
            await loadChatModelAsync(item: item, persistSelection: true)
        }
    }

    func loadEmbeddingModel(item: ModelCatalogItem) {
        Task { @MainActor in
            await loadEmbeddingModelAsync(item: item, persistSelection: true)
        }
    }

    func loadOCRModel(item: ModelCatalogItem) {
        Task { @MainActor in
            await loadOCRModelAsync(item: item, persistSelection: true)
        }
    }

    func reloadChatModel(item: ModelCatalogItem) {
        Task { @MainActor in
            await unloadChatModelAsync(clearSelection: false)
            await loadChatModelAsync(item: item, persistSelection: true)
        }
    }

    func reloadEmbeddingModel(item: ModelCatalogItem) {
        Task { @MainActor in
            await unloadEmbeddingModelAsync(clearSelection: false)
            await loadEmbeddingModelAsync(item: item, persistSelection: true)
        }
    }

    func reloadOCRModel(item: ModelCatalogItem) {
        Task { @MainActor in
            await unloadOCRModelAsync(clearSelection: false)
            await loadOCRModelAsync(item: item, persistSelection: true)
        }
    }

    func unloadChatModel() {
        Task { @MainActor in
            await unloadChatModelAsync(clearSelection: true)
        }
    }

    func unloadEmbeddingModel() {
        Task { @MainActor in
            await unloadEmbeddingModelAsync(clearSelection: true)
        }
    }

    func unloadOCRModel() {
        Task { @MainActor in
            await unloadOCRModelAsync(clearSelection: true)
        }
    }

    func offloadAllModels() {
        Task { @MainActor in
            await unloadChatModelAsync(clearSelection: false)
            await unloadEmbeddingModelAsync(clearSelection: false)
            await unloadOCRModelAsync(clearSelection: false)
        }
    }

    func handleSceneDidBecomeActive() {
        downloadManager.restorePendingTasks()

        Task { @MainActor in
            guard !isModelRehydrateInProgress else { return }
            isModelRehydrateInProgress = true
            defer { isModelRehydrateInProgress = false }

            if !isChatModelLoaded,
               let id = currentChatModelId,
               let item = findItem(id: id),
               modelPathIfInstalled(item) != nil {
                await loadChatModelAsync(item: item, persistSelection: false)
            }

            if !isEmbeddingModelLoaded,
               let id = currentEmbeddingModelId,
               let item = findItem(id: id),
               modelPathIfInstalled(item) != nil {
                await loadEmbeddingModelAsync(item: item, persistSelection: false)
            }

        }
    }

    func handleSceneDidEnterBackground() {
        stopGeneration()
        Task {
            await llamaContext.unload()
        }
        isChatModelLoaded = false
        isEmbeddingModelLoaded = false
        isOCRModelLoaded = false
        isChatModelLoading = false
        isEmbeddingModelLoading = false
        isOCRModelLoading = false
    }

    // MARK: - Chat

    func sendMessage(
        text: String,
        notes: [Note] = [],
        knowledgeChunks: [KnowledgeChunk] = [],
        modelContext: ModelContext
    ) {
        guard isChatModelLoaded, !isGenerating else { return }
        bootstrapIfNeeded(modelContext: modelContext)

        guard let session = ensureActiveSession(modelContext: modelContext) else { return }

        let userMessageText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessageText.isEmpty else { return }

        let shouldAutoTitle = chatMessages.isEmpty && session.title == SessionDefaults.newChatTitle
        if shouldAutoTitle {
            session.title = autoTitle(from: userMessageText)
        }
        session.updatedAt = Date()

        let userMessage = ChatMessage(role: "user", content: userMessageText, session: session)
        modelContext.insert(userMessage)
        chatMessages.append(userMessage)
        try? modelContext.save()

        isGenerating = true
        ragStatus = .ready
        retrievedContext = []
        retrievedKnowledgeContext = []
        lastRAGPreparedNotesCount = notes.count
        lastRAGPreparedChunksCount = knowledgeChunks.count
        lastRAGEligibleNotesCount = 0
        lastRAGEligibleChunksCount = 0
        lastRAGRetrievedCount = 0
        lastRAGRetrievedTitles = []
        lastRAGRetrievedDocumentTitles = []

        generationTask = Task { @MainActor in
            var ragNoteContext: [Note] = []
            var ragChunkContext: [KnowledgeChunk] = []
            let keywordNoteFallback: () -> [Note] = {
                self.vectorSearchService.findKeywordMatches(
                    queryText: userMessageText,
                    notes: notes,
                    topK: 3
                )
            }
            let keywordChunkFallback: () -> [KnowledgeChunk] = {
                self.vectorSearchService.findKeywordMatchesInChunks(
                    queryText: userMessageText,
                    chunks: knowledgeChunks,
                    topK: 3
                )
            }

            if !notes.isEmpty || !knowledgeChunks.isEmpty {
                let ragReady = await ensureRAGReadyBeforeSend(
                    notes: notes,
                    knowledgeChunks: knowledgeChunks,
                    modelContext: modelContext
                )
                if ragReady, isEmbeddingModelLoaded {
                    let eligibleNotes = notes.filter { isNoteEmbeddingFresh($0) }
                    let eligibleChunks = knowledgeChunks.filter { isKnowledgeChunkEmbeddingFresh($0) }
                    self.lastRAGEligibleNotesCount = eligibleNotes.count
                    self.lastRAGEligibleChunksCount = eligibleChunks.count
                    if eligibleNotes.isEmpty && eligibleChunks.isEmpty {
                        let fallbackNotes = keywordNoteFallback()
                        let fallbackChunks = keywordChunkFallback()
                        ragNoteContext = Array(fallbackNotes.prefix(2))
                        ragChunkContext = Array(fallbackChunks.prefix(max(0, 3 - ragNoteContext.count)))
                        if ragNoteContext.isEmpty && ragChunkContext.isEmpty {
                            self.ragStatus = .noIndexedNotes
                        } else {
                            self.applyRetrievedContextMetadata(notes: ragNoteContext, chunks: ragChunkContext)
                            self.ragStatus = .usedContext(count: ragNoteContext.count + ragChunkContext.count)
                        }
                    } else {
                        var foundNotes: [Note] = []
                        var foundChunks: [KnowledgeChunk] = []
                        var vectorError: String? = nil

                        do {
                            let queryEmbedding = try await llamaContext.embedWithEmbeddingModel(text: userMessageText)
                            guard !queryEmbedding.isEmpty else {
                                throw LlamaError.noEmbeddings
                            }

                            typealias Scored = (score: Float, note: Note?, chunk: KnowledgeChunk?)
                            var scored: [Scored] = []

                            let compatibleNotes = eligibleNotes.filter {
                                ($0.embedding?.count ?? 0) == queryEmbedding.count
                            }
                            for note in compatibleNotes {
                                guard let embedding = note.embedding,
                                      let score = vectorSearchService.scoreEmbedding(queryEmbedding: queryEmbedding, candidateEmbedding: embedding) else { continue }
                                scored.append((score: score, note: note, chunk: nil))
                            }

                            let compatibleChunks = eligibleChunks.filter {
                                ($0.embedding?.count ?? 0) == queryEmbedding.count
                            }
                            for chunk in compatibleChunks {
                                guard let embedding = chunk.embedding,
                                      let score = vectorSearchService.scoreEmbedding(queryEmbedding: queryEmbedding, candidateEmbedding: embedding) else { continue }
                                scored.append((score: score, note: nil, chunk: chunk))
                            }

                            let top = scored.sorted { $0.score > $1.score }.prefix(3)
                            for item in top {
                                if let note = item.note {
                                    foundNotes.append(note)
                                } else if let chunk = item.chunk {
                                    foundChunks.append(chunk)
                                }
                            }
                        } catch {
                            vectorError = error.localizedDescription
                        }

                        if foundNotes.isEmpty && foundChunks.isEmpty {
                            let fallbackNotes = keywordNoteFallback()
                            let fallbackChunks = keywordChunkFallback()
                            foundNotes = Array(fallbackNotes.prefix(2))
                            foundChunks = Array(fallbackChunks.prefix(max(0, 3 - foundNotes.count)))
                        }

                        ragNoteContext = foundNotes
                        ragChunkContext = foundChunks
                        self.applyRetrievedContextMetadata(notes: foundNotes, chunks: foundChunks)
                        if foundNotes.isEmpty && foundChunks.isEmpty, let vectorError {
                            self.ragStatus = .failed(vectorError)
                        } else {
                            self.ragStatus = .usedContext(count: foundNotes.count + foundChunks.count)
                        }
                    }
                } else {
                    let fallbackNotes = keywordNoteFallback()
                    let fallbackChunks = keywordChunkFallback()
                    ragNoteContext = Array(fallbackNotes.prefix(2))
                    ragChunkContext = Array(fallbackChunks.prefix(max(0, 3 - ragNoteContext.count)))
                    self.applyRetrievedContextMetadata(notes: ragNoteContext, chunks: ragChunkContext)
                    if !ragNoteContext.isEmpty || !ragChunkContext.isEmpty {
                        self.ragStatus = .usedContext(count: ragNoteContext.count + ragChunkContext.count)
                    }
                }
            }

            let messages = buildMessageHistory(ragNotes: ragNoteContext, ragChunks: ragChunkContext)
            let prompt = await llamaContext.applyTemplate(messages: messages)

            let sourceNoteIds = ragNoteContext.map { $0.id }
            let sourceChunkIds = ragChunkContext.map { $0.id }
            let assistantMessage = ChatMessage(
                role: "assistant",
                content: "",
                sourceNoteIds: sourceNoteIds,
                sourceKnowledgeChunkIds: sourceChunkIds,
                session: session
            )
            modelContext.insert(assistantMessage)
            chatMessages.append(assistantMessage)

            var fullResponse = ""

            do {
                let stream = await llamaContext.completion(prompt: prompt)
                for try await token in stream {
                    if Task.isCancelled { break }
                    fullResponse += token
                    let snapshot = fullResponse
                    let parsed = parseThinkTags(snapshot)
                    assistantMessage.content = parsed.content
                    assistantMessage.thoughtProcess = parsed.thought
                    session.updatedAt = Date()
                }
            } catch {
                assistantMessage.content = "Error: \(error.localizedDescription)"
                session.updatedAt = Date()
            }

            try? modelContext.save()
            try? refreshSessions(modelContext: modelContext)
            self.isGenerating = false
        }
    }

    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        Task {
            await llamaContext.stopCompletion()
        }
        isGenerating = false
    }

    func ragStatusText() -> String? {
        switch ragStatus {
        case .ready:
            return nil
        case .preparingModel:
            return "RAG: preparing embedding model..."
        case .preparingIndex:
            return "RAG: preparing knowledge index..."
        case .timedOut:
            return "RAG preparation timed out. Answering without retrieval context."
        case .disabledNoEmbeddingModel:
            return "RAG is disabled: load an embedding model."
        case .noIndexedNotes:
            return "No indexed knowledge for the active embedding model."
        case .usedContext(let count):
            return count > 0 ? "RAG: using \(count) source(s) as context." : "RAG: no relevant context found."
        case .failed(let message):
            return "RAG failed: \(message)"
        }
    }

    func ragDebugText() -> String? {
        if lastRAGPreparedNotesCount == 0 && lastRAGPreparedChunksCount == 0 && lastRAGEligibleNotesCount == 0 && lastRAGEligibleChunksCount == 0 && lastRAGRetrievedCount == 0 {
            return nil
        }
        if lastRAGRetrievedTitles.isEmpty && lastRAGRetrievedDocumentTitles.isEmpty {
            return "RAG: notes prepared \(lastRAGPreparedNotesCount), chunks prepared \(lastRAGPreparedChunksCount), notes eligible \(lastRAGEligibleNotesCount), chunks eligible \(lastRAGEligibleChunksCount), retrieved \(lastRAGRetrievedCount)"
        }
        let joinedNotes = lastRAGRetrievedTitles.prefix(2).joined(separator: ", ")
        let joinedDocs = lastRAGRetrievedDocumentTitles.prefix(2).joined(separator: ", ")
        let preview = [joinedNotes, joinedDocs].filter { !$0.isEmpty }.joined(separator: " | ")
        return "RAG: notes prepared \(lastRAGPreparedNotesCount), chunks prepared \(lastRAGPreparedChunksCount), notes eligible \(lastRAGEligibleNotesCount), chunks eligible \(lastRAGEligibleChunksCount), retrieved \(lastRAGRetrievedCount) [\(preview)]"
    }

    // MARK: - Indexing (RAG)

    func indexAllNotes(notes: [Note], modelContext: ModelContext) {
        guard isEmbeddingModelLoaded, !isIndexing else { return }
        guard !notes.isEmpty else { return }

        isIndexing = true
        indexingProgress = 0.0
        indexingStatus = "Starting indexing..."

        Task { @MainActor in
            let total = notes.count
            var indexed = 0
            var failed = 0

            for note in notes {
                do {
                    try await indexSingleNote(note: note, modelContext: modelContext)
                    indexed += 1
                } catch {
                    failed += 1
                }

                self.indexingProgress = Double(indexed + failed) / Double(total)
                self.indexingStatus = "Indexed \(indexed)/\(total) notes..."
            }

            try? modelContext.save()
            self.isIndexing = false
            self.indexingStatus = "Completed: \(indexed) indexed, \(failed) failed"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                self.indexingStatus = nil
                self.indexingProgress = 0.0
            }
        }
    }

    func handleNoteEdited(_ note: Note, modelContext: ModelContext) {
        markNoteEmbeddingStale(note)
        scheduleAutoIndex(for: note, modelContext: modelContext)
    }

    func startAutoIndexIfNeeded(notes: [Note], modelContext: ModelContext) {
        guard isEmbeddingModelLoaded, !isIndexing else { return }
        guard !notesNeedingEmbedding(notes).isEmpty else { return }

        Task { @MainActor in
            do {
                _ = try await ensureIndexedForRAG(notes: notes, modelContext: modelContext)
            } catch {
                // Do not surface hard error for automatic background refresh.
            }
        }
    }

    func startAutoIndexKnowledgeIfNeeded(chunks: [KnowledgeChunk], modelContext: ModelContext) {
        guard isEmbeddingModelLoaded, !isIndexing else { return }
        guard !knowledgeChunksNeedingEmbedding(chunks).isEmpty else { return }

        Task { @MainActor in
            do {
                _ = try await ensureKnowledgeChunksIndexedForRAG(chunks: chunks, modelContext: modelContext)
            } catch {
                // Best-effort background indexing for knowledge chunks.
            }
        }
    }

    private func ensureRAGReadyBeforeSend(
        notes: [Note],
        knowledgeChunks: [KnowledgeChunk],
        modelContext: ModelContext
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(10)
        func timedOut() -> Bool { Date() > deadline }

        do {
            if timedOut() {
                ragStatus = .timedOut
                return false
            }

            if !isEmbeddingModelLoaded {
                ragStatus = .preparingModel
                let loaded = await ensureEmbeddingModelLoadedForRAG()
                if !loaded {
                    ragStatus = .disabledNoEmbeddingModel
                    return false
                }
            }

            if timedOut() {
                ragStatus = .timedOut
                return false
            }

            if isIndexing {
                ragStatus = .preparingIndex
                let finished = await waitForIndexingToFinish(before: deadline)
                if !finished {
                    let fallbackEligibleNotes = notes.filter { isNoteEmbeddingFresh($0) }
                    let fallbackEligibleChunks = knowledgeChunks.filter { isKnowledgeChunkEmbeddingFresh($0) }
                    if fallbackEligibleNotes.isEmpty && fallbackEligibleChunks.isEmpty {
                        ragStatus = .timedOut
                        return false
                    }
                    return true
                }
            }

            if !notesNeedingEmbedding(notes).isEmpty || !knowledgeChunksNeedingEmbedding(knowledgeChunks).isEmpty {
                ragStatus = .preparingIndex
                _ = try await ensureIndexedForRAG(notes: notes, modelContext: modelContext, deadline: deadline)
                _ = try await ensureKnowledgeChunksIndexedForRAG(chunks: knowledgeChunks, modelContext: modelContext, deadline: deadline)
            }

            if timedOut() {
                let fallbackEligibleNotes = notes.filter { isNoteEmbeddingFresh($0) }
                let fallbackEligibleChunks = knowledgeChunks.filter { isKnowledgeChunkEmbeddingFresh($0) }
                if fallbackEligibleNotes.isEmpty && fallbackEligibleChunks.isEmpty {
                    ragStatus = .timedOut
                    return false
                }
            }

            return true
        } catch {
            ragStatus = .failed(error.localizedDescription)
            return false
        }
    }

    func indexedCountForActiveEmbedding(notes: [Note]) -> Int {
        notes.filter { isNoteEmbeddingFresh($0) }.count
    }

    func indexedKnowledgeChunkCountForActiveEmbedding(chunks: [KnowledgeChunk]) -> Int {
        chunks.filter { isKnowledgeChunkEmbeddingFresh($0) }.count
    }

    // MARK: - Helpers

    private func loadMessages(for session: ChatSession, modelContext: ModelContext) {
        let sessionId = session.id
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.session?.id == sessionId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        do {
            chatMessages = try modelContext.fetch(descriptor)
        } catch {
            chatMessages = []
            modelError = "Failed to load session messages: \(error.localizedDescription)"
        }
    }

    private func restoreSelectedSession() -> ChatSession? {
        guard let activeSessionId else { return nil }
        return sessions.first(where: { $0.id == activeSessionId })
    }

    private func ensureActiveSession(modelContext: ModelContext) -> ChatSession? {
        if let current = activeSession() {
            return current
        }
        if sessions.isEmpty {
            createNewChatSession(modelContext: modelContext)
            return activeSession()
        }
        if let first = sessions.first {
            selectSession(first, modelContext: modelContext)
            return first
        }
        return nil
    }

    private func autoTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 48 {
            return trimmed
        }
        let cut = trimmed.prefix(48).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cut)..."
    }

    private func migrateUngroupedMessagesIntoLegacySession(modelContext: ModelContext) throws {
        let ungroupedDescriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.session == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let ungrouped = try modelContext.fetch(ungroupedDescriptor)
        guard !ungrouped.isEmpty else { return }

        let legacy = try fetchOrCreateLegacySession(modelContext: modelContext)
        for message in ungrouped {
            message.session = legacy
            if message.createdAt > legacy.updatedAt {
                legacy.updatedAt = message.createdAt
            }
        }
        try modelContext.save()
    }

    private func fetchOrCreateLegacySession(modelContext: ModelContext) throws -> ChatSession {
        let legacyTitle = SessionDefaults.legacyTitle
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate<ChatSession> { $0.title == legacyTitle },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let legacy = ChatSession(title: SessionDefaults.legacyTitle)
        modelContext.insert(legacy)
        return legacy
    }

    private func ensureAtLeastOneSession(modelContext: ModelContext) throws {
        let count = try modelContext.fetchCount(FetchDescriptor<ChatSession>())
        if count == 0 {
            modelContext.insert(ChatSession(title: SessionDefaults.newChatTitle))
            try modelContext.save()
        }
    }

    private func refreshSessions(modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        sessions = try modelContext.fetch(descriptor)
    }

    private func buildMessageHistory(ragNotes: [Note] = [], ragChunks: [KnowledgeChunk] = []) -> [[String: String]] {
        var messages: [[String: String]] = []
        var systemContent = "You are a helpful assistant."
        let contextBlock = ragContextBlock(notes: ragNotes, chunks: ragChunks)

        if !contextBlock.isEmpty {
            systemContent += "\n\nUse retrieved knowledge when relevant, and prefer grounded answers."
        }

        messages.append([
            "role": "system",
            "content": systemContent
        ])

        let lastIndex = chatMessages.indices.last

        for (index, msg) in chatMessages.enumerated() {
            var content = msg.content

            // Inject retrieved context into the most recent user turn so templates
            // that ignore system role still receive retrieval context.
            if !contextBlock.isEmpty,
               msg.role == "user",
               index == lastIndex {
                content += "\n\nRetrieved context:\n\(contextBlock)"
            }

            messages.append([
                "role": msg.role,
                "content": content
            ])
        }

        return messages
    }

    private func ragContextBlock(notes: [Note], chunks: [KnowledgeChunk]) -> String {
        var lines: [String] = []

        for note in notes {
            let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : note.title
            let snippet = String(note.content.prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("- [Note: \(title)] \(snippet)")
        }

        for chunk in chunks {
            let rawTitle = chunk.document?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let docTitle = rawTitle.isEmpty ? "Document" : rawTitle
            let snippet = String(chunk.text.prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("- [KB: \(docTitle) / chunk \(chunk.chunkIndex + 1)] \(snippet)")
        }

        return lines.joined(separator: "\n")
    }

    private func applyRetrievedContextMetadata(notes: [Note], chunks: [KnowledgeChunk]) {
        retrievedContext = notes
        retrievedKnowledgeContext = chunks
        lastRAGRetrievedCount = notes.count + chunks.count
        lastRAGRetrievedTitles = notes.map {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : $0.title
        }
        lastRAGRetrievedDocumentTitles = chunks.map {
            let title = $0.document?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? "Document" : title
        }
    }

    private func parseThinkTags(_ text: String) -> (content: String, thought: String?) {
        let thinkPattern = #"<think>([\s\S]*?)</think>"#

        guard let regex = try? NSRegularExpression(pattern: thinkPattern, options: []) else {
            return (text, nil)
        }

        let range = NSRange(text.startIndex..., in: text)
        var thoughtContent: String? = nil
        var cleanedContent = text
        let matches = regex.matches(in: text, options: [], range: range)
        var thoughts: [String] = []

        for match in matches.reversed() {
            if let thoughtRange = Range(match.range(at: 1), in: text) {
                thoughts.insert(String(text[thoughtRange]), at: 0)
            }
            if let fullRange = Range(match.range, in: text) {
                cleanedContent.removeSubrange(fullRange)
            }
        }

        if !thoughts.isEmpty {
            thoughtContent = thoughts.joined(separator: "\n")
        }

        return (sanitizeOutput(cleanedContent), thoughtContent)
    }

    private func sanitizeOutput(_ content: String) -> String {
        let controlTokens = [
            "<|im_start|>", "<|im_end|>", "<|endoftext|>", "</s>",
            "<|assistant|>", "<|user|>", "<|system|>"
        ]

        var cleaned = content
        for token in controlTokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func modelPathIfInstalled(_ item: ModelCatalogItem) -> String? {
        do {
            let url = try ModelStorage.shared.fileURL(for: item)
            return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
        } catch {
            return nil
        }
    }

    private func findItem(id: String) -> ModelCatalogItem? {
        catalogStore.items.first(where: { $0.id == id })
    }

    private func ensureEmbeddingModelLoadedForRAG() async -> Bool {
        if isEmbeddingModelLoaded {
            return true
        }

        if let id = currentEmbeddingModelId,
           let item = findItem(id: id),
           modelPathIfInstalled(item) != nil {
            await loadEmbeddingModelAsync(item: item, persistSelection: false)
            if isEmbeddingModelLoaded {
                return true
            }
        }

        if let fallbackItem = catalogStore.items(kind: .embedding)
            .first(where: { modelPathIfInstalled($0) != nil }) {
            await loadEmbeddingModelAsync(item: fallbackItem, persistSelection: true)
        }

        return isEmbeddingModelLoaded
    }

    private func loadChatModelAsync(item: ModelCatalogItem, persistSelection: Bool) async {
        guard item.kind == .chat else { return }
        guard let path = modelPathIfInstalled(item) else {
            modelError = "Model file not found"
            return
        }
        guard !isChatModelLoading else { return }

        isChatModelLoading = true
        modelError = nil

        do {
            try await llamaContext.loadModel(path: path, lowMemory: isLowPowerMode)
            isChatModelLoaded = true
            currentChatModelId = item.id
            if persistSelection {
                defaults.set(item.id, forKey: PreferenceKey.activeChatModelId)
            }
        } catch {
            modelError = buildModelLoadError(error: error, path: path, modelName: item.name)
            isChatModelLoaded = false
        }

        isChatModelLoading = false
    }

    private func loadEmbeddingModelAsync(item: ModelCatalogItem, persistSelection: Bool) async {
        guard item.kind == .embedding else { return }
        guard let path = modelPathIfInstalled(item) else {
            modelError = "Model file not found"
            return
        }
        guard !isEmbeddingModelLoading else { return }

        isEmbeddingModelLoading = true
        modelError = nil

        do {
            try await llamaContext.loadEmbeddingModel(path: path, lowMemory: isLowPowerMode)
            isEmbeddingModelLoaded = true
            currentEmbeddingModelId = item.id
            if persistSelection {
                defaults.set(item.id, forKey: PreferenceKey.activeEmbeddingModelId)
            }
        } catch {
            modelError = buildModelLoadError(error: error, path: path, modelName: item.name)
            isEmbeddingModelLoaded = false
        }

        isEmbeddingModelLoading = false
    }

    private func loadOCRModelAsync(item: ModelCatalogItem, persistSelection: Bool) async {
        guard item.kind == .ocr || item.kind == .vl else { return }
        guard let path = modelPathIfInstalled(item) else {
            modelError = "Model file not found"
            return
        }
        guard !isOCRModelLoading else { return }

        isOCRModelLoading = true
        modelError = nil

        do {
            let auxiliaryURL = ((try? ModelStorage.shared.auxiliaryFileURL(for: item)) ?? nil)
            let auxiliaryPath = auxiliaryURL?.path
            do {
                try await llamaContext.loadOCRModel(path: path, auxiliaryPath: auxiliaryPath, lowMemory: isLowPowerMode)
            } catch {
                // Retry OCR/VL loading in low-memory mode for better device compatibility.
                if !isLowPowerMode {
                    try await llamaContext.loadOCRModel(path: path, auxiliaryPath: auxiliaryPath, lowMemory: true)
                } else {
                    throw error
                }
            }
            if !(await llamaContext.hasVisionOCRContext()) {
                throw LlamaError.ocrVisionUnavailable
            }
            isOCRModelLoaded = true
            currentOCRModelId = item.id
            touchOCRUsage()
            if persistSelection {
                defaults.set(item.id, forKey: PreferenceKey.activeOCRModelId)
            }
        } catch {
            modelError = buildModelLoadError(error: error, path: path, modelName: item.name)
            isOCRModelLoaded = false
        }

        isOCRModelLoading = false
    }

    private func unloadChatModelAsync(clearSelection: Bool) async {
        await llamaContext.unloadChat()
        isChatModelLoaded = false
        isChatModelLoading = false
        if clearSelection {
            currentChatModelId = nil
            defaults.removeObject(forKey: PreferenceKey.activeChatModelId)
        }
    }

    private func unloadEmbeddingModelAsync(clearSelection: Bool) async {
        await llamaContext.unloadEmbedding()
        isEmbeddingModelLoaded = false
        isEmbeddingModelLoading = false
        if clearSelection {
            currentEmbeddingModelId = nil
            defaults.removeObject(forKey: PreferenceKey.activeEmbeddingModelId)
        }
    }

    private func unloadOCRModelAsync(clearSelection: Bool) async {
        ocrAutoUnloadTask?.cancel()
        ocrAutoUnloadTask = nil
        ocrLastUsedAt = nil
        await llamaContext.unloadOCRModel()
        isOCRModelLoaded = false
        isOCRModelLoading = false
        if clearSelection {
            currentOCRModelId = nil
            defaults.removeObject(forKey: PreferenceKey.activeOCRModelId)
        }
    }

    private func prepareOCRModelForTask() async -> (enabled: Bool, loadedTemporarily: Bool) {
        guard let id = currentOCRModelId,
              let item = findItem(id: id),
              modelPathIfInstalled(item) != nil else {
            return (false, false)
        }

        if isOCRModelLoaded {
            touchOCRUsage()
            return (true, false)
        }

        await loadOCRModelAsync(item: item, persistSelection: false)
        if isOCRModelLoaded {
            touchOCRUsage()
            return (true, true)
        }

        return (false, false)
    }

    private func finishOCRModelTask(loadedTemporarily: Bool) async {
        if loadedTemporarily {
            await unloadOCRModelAsync(clearSelection: false)
        } else {
            scheduleOCRAutoUnload()
        }
    }

    private func touchOCRUsage() {
        ocrLastUsedAt = Date()
        scheduleOCRAutoUnload()
    }

    private func scheduleOCRAutoUnload(after seconds: TimeInterval = 45) {
        ocrAutoUnloadTask?.cancel()
        guard isOCRModelLoaded else { return }
        ocrAutoUnloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            guard self.isOCRModelLoaded else { return }
            guard !self.isImportingKnowledge else {
                self.scheduleOCRAutoUnload(after: seconds)
                return
            }
            guard let last = self.ocrLastUsedAt else {
                await self.unloadOCRModelAsync(clearSelection: false)
                return
            }
            if Date().timeIntervalSince(last) >= seconds {
                await self.unloadOCRModelAsync(clearSelection: false)
            } else {
                self.scheduleOCRAutoUnload(after: seconds)
            }
        }
    }

    private func noteContentHash(_ note: Note) -> String {
        noteContentHash(title: note.title, content: note.content)
    }

    private func buildModelLoadError(error: Error, path: String, modelName: String) -> String {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        var sizeText = "unknown size"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = (attrs[.size] as? NSNumber)?.int64Value {
            sizeText = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        }

        if let llamaError = error as? LlamaError {
            switch llamaError {
            case .invalidModelFile:
                return "\(modelName) is not a valid GGUF file (\(filename), \(sizeText)). Re-download this model."
            case .failedToLoadModel:
                return "Could not load \(modelName) (\(filename), \(sizeText)). File may be incompatible or incomplete. Re-download and try again."
            default:
                return llamaError.localizedDescription
            }
        }

        return error.localizedDescription
    }

    private func noteContentHash(title: String, content: String) -> String {
        let text = "\(title)\n\(content)"
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func knowledgeChunkContentHash(_ chunk: KnowledgeChunk) -> String {
        let digest = SHA256.hash(data: Data(chunk.text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func markNoteEmbeddingStale(_ note: Note) {
        note.embedding = nil
        note.embeddingModelId = nil
        note.embeddingUpdatedAt = nil
        note.embeddingContentHash = nil
    }

    private func scheduleAutoIndex(for note: Note, modelContext: ModelContext) {
        pendingAutoIndexTasks[note.id]?.cancel()
        pendingAutoIndexTasks[note.id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard isEmbeddingModelLoaded else { return }
            do {
                try await indexSingleNote(note: note, modelContext: modelContext)
                try? modelContext.save()
            } catch {
                // Silent for auto-index; user can always trigger full re-index from Settings.
            }
            self.pendingAutoIndexTasks[note.id] = nil
        }
    }

    private func ensureIndexedForRAG(notes: [Note], modelContext: ModelContext, deadline: Date? = nil) async throws -> Int {
        guard isEmbeddingModelLoaded, !isIndexing else { return 0 }
        let candidates = notesNeedingEmbedding(notes)
        guard !candidates.isEmpty else { return 0 }

        isIndexing = true
        indexingProgress = 0.0
        indexingStatus = "Auto-indexing notes..."
        defer { isIndexing = false }

        var indexed = 0
        var failed = 0
        let total = candidates.count

        for note in candidates {
            if let deadline, Date() > deadline { break }
            do {
                try await indexSingleNote(note: note, modelContext: modelContext)
                indexed += 1
            } catch {
                failed += 1
            }
            indexingProgress = Double(indexed + failed) / Double(total)
        }

        indexingStatus = nil
        indexingProgress = 0.0
        try? modelContext.save()
        return indexed
    }

    private func notesNeedingEmbedding(_ notes: [Note]) -> [Note] {
        notes.filter { note in
            !isNoteEmbeddingFresh(note)
        }
    }

    private func knowledgeChunksNeedingEmbedding(_ chunks: [KnowledgeChunk]) -> [KnowledgeChunk] {
        chunks.filter { chunk in
            !isKnowledgeChunkEmbeddingFresh(chunk)
        }
    }

    private func waitForIndexingToFinish(before deadline: Date) async -> Bool {
        while isIndexing {
            if Date() > deadline {
                return false
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return true
    }

    private func indexSingleNote(note: Note, modelContext: ModelContext) async throws {
        guard let embeddingModelId = currentEmbeddingModelId else {
            throw LlamaError.notLoaded
        }

        let textToEmbed = "\(note.title)\n\(note.content)"
        let contentHash = noteContentHash(note)
        let embedding = try await llamaContext.embedWithEmbeddingModel(text: textToEmbed)

        note.embedding = embedding
        note.embeddingModelId = embeddingModelId
        note.embeddingUpdatedAt = Date()
        note.embeddingContentHash = contentHash

        try? modelContext.save()
    }

    private func ensureKnowledgeChunksIndexedForRAG(chunks: [KnowledgeChunk], modelContext: ModelContext, deadline: Date? = nil) async throws -> Int {
        guard isEmbeddingModelLoaded, !isIndexing else { return 0 }
        let candidates = knowledgeChunksNeedingEmbedding(chunks)
        guard !candidates.isEmpty else { return 0 }

        isIndexing = true
        indexingProgress = 0.0
        indexingStatus = "Auto-indexing knowledge chunks..."
        defer { isIndexing = false }

        var indexed = 0
        var failed = 0
        let total = candidates.count

        for chunk in candidates {
            if let deadline, Date() > deadline { break }
            do {
                try await indexSingleKnowledgeChunk(chunk: chunk, modelContext: modelContext)
                indexed += 1
            } catch {
                failed += 1
            }
            indexingProgress = Double(indexed + failed) / Double(total)
        }

        indexingStatus = nil
        indexingProgress = 0.0
        try? modelContext.save()
        return indexed
    }

    private func indexSingleKnowledgeChunk(chunk: KnowledgeChunk, modelContext: ModelContext) async throws {
        guard let embeddingModelId = currentEmbeddingModelId else {
            throw LlamaError.notLoaded
        }

        let contentHash = knowledgeChunkContentHash(chunk)
        let embedding = try await llamaContext.embedWithEmbeddingModel(text: chunk.text)

        chunk.embedding = embedding
        chunk.embeddingModelId = embeddingModelId
        chunk.embeddingUpdatedAt = Date()
        chunk.embeddingContentHash = contentHash
        chunk.updatedAt = Date()

        try? modelContext.save()
    }

    private func isNoteEmbeddingFresh(_ note: Note) -> Bool {
        guard let embedding = note.embedding, !embedding.isEmpty else { return false }
        guard let modelId = note.embeddingModelId else { return false }
        guard modelId == currentEmbeddingModelId else { return false }
        guard let savedHash = note.embeddingContentHash else { return false }
        return savedHash == noteContentHash(note)
    }

    private func isKnowledgeChunkEmbeddingFresh(_ chunk: KnowledgeChunk) -> Bool {
        guard let embedding = chunk.embedding, !embedding.isEmpty else { return false }
        guard let modelId = chunk.embeddingModelId else { return false }
        guard modelId == currentEmbeddingModelId else { return false }
        guard let savedHash = chunk.embeddingContentHash else { return false }
        return savedHash == knowledgeChunkContentHash(chunk)
    }
}

extension GlobalViewModel {
    func importKnowledgeFiles(
        urls: [URL],
        sourceType: KnowledgeSourceType = .localFile,
        driveFileId: String? = nil,
        modelContext: ModelContext
    ) {
        guard !urls.isEmpty else { return }
        guard !isImportingKnowledge else { return }

        isImportingKnowledge = true
        knowledgeImportStatus = "Importing \(urls.count) file(s)..."

        Task { @MainActor in
            var success = 0
            var failed = 0
            let ocrSession = useModelOCRForImports ? await prepareOCRModelForTask() : (enabled: false, loadedTemporarily: false)

            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                do {
                    try await importSingleKnowledgeFile(
                        from: url,
                        sourceType: sourceType,
                        driveFileId: driveFileId,
                        preferOCRModel: ocrSession.enabled,
                        modelContext: modelContext
                    )
                    success += 1
                } catch {
                    failed += 1
                }
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if useModelOCRForImports {
                await finishOCRModelTask(loadedTemporarily: ocrSession.loadedTemporarily)
            }
            isImportingKnowledge = false
            knowledgeImportStatus = "Knowledge import: \(success) succeeded, \(failed) failed"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if !isImportingKnowledge {
                    knowledgeImportStatus = nil
                }
            }
        }
    }

    func importKnowledgeImageData(_ data: Data, suggestedName: String, modelContext: ModelContext) {
        guard !data.isEmpty else { return }
        guard !isImportingKnowledge else { return }

        isImportingKnowledge = true
        knowledgeImportStatus = "Importing image..."

        Task { @MainActor in
            defer { isImportingKnowledge = false }
            let ocrSession = useModelOCRForImports ? await prepareOCRModelForTask() : (enabled: false, loadedTemporarily: false)
            do {
                let ingested = try await knowledgeIngestionService.ingestImageData(
                    data,
                    suggestedName: suggestedName,
                    llamaContext: llamaContext,
                    preferOCRModel: ocrSession.enabled
                )
                try await persistIngestedDocument(ingested, modelContext: modelContext)
                knowledgeImportStatus = "Image imported to knowledge base"
            } catch {
                knowledgeImportStatus = "Image import failed: \(error.localizedDescription)"
            }
            if useModelOCRForImports {
                await finishOCRModelTask(loadedTemporarily: ocrSession.loadedTemporarily)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if !isImportingKnowledge {
                    knowledgeImportStatus = nil
                }
            }
        }
    }

    func importKnowledgeDriveFile(_ file: DriveFile, modelContext: ModelContext) {
        guard !isImportingKnowledge else { return }
        guard !file.id.isEmpty else { return }

        isImportingKnowledge = true
        knowledgeImportStatus = "Downloading from Drive..."

        Task { @MainActor in
            defer { isImportingKnowledge = false }
            let ocrSession = useModelOCRForImports ? await prepareOCRModelForTask() : (enabled: false, loadedTemporarily: false)
            let ext = URL(fileURLWithPath: file.name ?? "drive-file").pathExtension.lowercased()
            let suffix = resolvedDriveTempExtension(fileNameExtension: ext, mimeType: file.mimeType)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(suffix)", isDirectory: false)
            do {
                try await driveSync.downloadFileFromSynapsFolder(fileId: file.id, to: tempURL)
                try await importSingleKnowledgeFile(
                    from: tempURL,
                    sourceType: .drive,
                    driveFileId: file.id,
                    preferredTitle: file.name,
                    preferOCRModel: ocrSession.enabled,
                    modelContext: modelContext
                )
                knowledgeImportStatus = "Drive file imported"
            } catch {
                knowledgeImportStatus = "Drive import failed: \(error.localizedDescription)"
            }
            if useModelOCRForImports {
                await finishOCRModelTask(loadedTemporarily: ocrSession.loadedTemporarily)
            }
            try? FileManager.default.removeItem(at: tempURL)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if !isImportingKnowledge {
                    knowledgeImportStatus = nil
                }
            }
        }
    }

    func deleteKnowledgeDocument(_ document: KnowledgeDocument, modelContext: ModelContext) {
        knowledgeIngestionService.deleteStoredFile(relativePath: document.localRelativePath)
        modelContext.delete(document)
        try? modelContext.save()
    }

    func reindexKnowledgeBase(chunks: [KnowledgeChunk], modelContext: ModelContext) {
        guard isEmbeddingModelLoaded, !isIndexing else { return }
        guard !chunks.isEmpty else { return }

        isIndexing = true
        indexingProgress = 0
        indexingStatus = "Reindexing knowledge base..."

        Task { @MainActor in
            defer {
                isIndexing = false
                indexingProgress = 0
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    if !isIndexing {
                        indexingStatus = nil
                    }
                }
            }

            var indexed = 0
            var failed = 0
            for chunk in chunks {
                do {
                    try await indexSingleKnowledgeChunk(chunk: chunk, modelContext: modelContext)
                    indexed += 1
                } catch {
                    failed += 1
                }
                indexingProgress = Double(indexed + failed) / Double(chunks.count)
            }
            indexingStatus = "Reindexed knowledge chunks: \(indexed) done, \(failed) failed"
            try? modelContext.save()
        }
    }

    func resolveKnowledgeDocumentURL(_ document: KnowledgeDocument) -> URL? {
        try? knowledgeIngestionService.resolveDocumentURL(relativePath: document.localRelativePath)
    }

    private func importSingleKnowledgeFile(
        from url: URL,
        sourceType: KnowledgeSourceType,
        driveFileId: String? = nil,
        preferredTitle: String? = nil,
        preferOCRModel: Bool,
        modelContext: ModelContext
    ) async throws {
        var ingested = try await knowledgeIngestionService.ingestLocalFile(
            sourceURL: url,
            sourceType: sourceType,
            driveFileId: driveFileId,
            llamaContext: llamaContext,
            preferOCRModel: preferOCRModel
        )
        if let preferredTitle, !preferredTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ingested.title = preferredTitle
        }
        try await persistIngestedDocument(ingested, modelContext: modelContext)
    }

    private func persistIngestedDocument(_ ingested: IngestedKnowledgeDocument, modelContext: ModelContext) async throws {
        let document = KnowledgeDocument(
            title: ingested.title,
            sourceType: ingested.sourceType.rawValue,
            mimeType: ingested.mimeType,
            localRelativePath: ingested.relativePath,
            driveFileId: ingested.driveFileId,
            extractionStatus: ingested.chunks.isEmpty ? "empty" : "ready",
            extractionError: ingested.chunks.isEmpty ? "No text extracted" : nil,
            extractionEngine: ingested.extractionResult.engine,
            contentHash: ingested.contentHash,
            createdAt: Date(),
            updatedAt: Date()
        )
        modelContext.insert(document)

        for (index, text) in ingested.chunks.enumerated() {
            let chunk = KnowledgeChunk(
                chunkIndex: index,
                text: text,
                createdAt: Date(),
                updatedAt: Date(),
                document: document
            )
            modelContext.insert(chunk)
            if isEmbeddingModelLoaded {
                try? await indexSingleKnowledgeChunk(chunk: chunk, modelContext: modelContext)
            }
        }

        try? modelContext.save()
    }

    private func resolvedDriveTempExtension(fileNameExtension ext: String, mimeType: String?) -> String {
        if !ext.isEmpty {
            return ext
        }

        if let mimeType, let type = UTType(mimeType: mimeType), let preferred = type.preferredFilenameExtension, !preferred.isEmpty {
            return preferred
        }

        let normalizedMime = (mimeType ?? "").lowercased()
        switch normalizedMime {
        case "application/pdf":
            return "pdf"
        case "text/plain":
            return "txt"
        case "text/markdown":
            return "md"
        case "image/jpeg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/webp":
            return "webp"
        case "image/heic":
            return "heic"
        default:
            return "bin"
        }
    }
}
