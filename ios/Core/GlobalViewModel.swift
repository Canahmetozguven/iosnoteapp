import Foundation
import SwiftUI
import SwiftData
import CryptoKit
import UniformTypeIdentifiers

enum GenerationStage: String {
    case searchingSources
    case rankingSources
    case draftingAnswer

    var displayText: String {
        switch self {
        case .searchingSources:
            return "Searching notes and documents..."
        case .rankingSources:
            return "Ranking the best sources..."
        case .draftingAnswer:
            return "Drafting answer..."
        }
    }
}

struct AssistantAnswerInsight {
    var confidence: RetrievalConfidence
    var topScore: Float?
    var profile: RAGRetrievalProfile
    var strictGrounding: Bool
    var sourceCount: Int
    var generatedAt: Date
}

@MainActor
@Observable
class GlobalViewModel {
    let catalogStore = ModelCatalogStore()
    let downloads = ModelDownloadManager.shared.viewModel()
    private let downloadManager = ModelDownloadManager.shared
    let driveSync = DriveSyncService()
    private let knowledgeIngestionService = KnowledgeIngestionService()
    var llamaContext = LlamaContext()
    let ragPipelineService = RAGPipelineService()

    private enum PreferenceKey {
        static let activeChatModelId = "active_chat_model_id"
        static let activeEmbeddingModelId = "active_embedding_model_id"
        static let activeOCRModelId = "active_ocr_model_id"
        static let useModelOCRForImports = "use_model_ocr_for_imports"
        static let longAnswerMode = "long_answer_mode"
        static let lowPowerMode = "low_power_mode"
        static let activeChatSessionId = "active_chat_session_id"
        static let ragRetrievalProfile = "rag_retrieval_profile"
        static let strictGroundingMode = "strict_grounding_mode"
        static let ragNoteBoosts = "rag_note_boosts"
        static let ragChunkBoosts = "rag_chunk_boosts"
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
    var lastRAGConfidence: RetrievalConfidence = .none
    var lastRAGTopScore: Float? = nil
    var lastRAGProfileUsed: RAGRetrievalProfile = .fastRecommended
    var generationStage: GenerationStage? = nil
    var knowledgeImportStatus: String? = nil

    // Chat state (session-aware and persisted in SwiftData).
    var sessions: [ChatSession] = []
    var activeSessionId: UUID? = nil
    var chatMessages: [ChatMessage] = []
    private(set) var insightByAssistantMessageId: [UUID: AssistantAnswerInsight] = [:]
    private(set) var citationsByAssistantMessageId: [UUID: [CitationRef]] = [:]
    private(set) var feedbackByAssistantMessageId: [UUID: AssistantAnswerFeedback] = [:]
    private var noteFeedbackBoosts: [UUID: Float] = [:]
    private var chunkFeedbackBoosts: [UUID: Float] = [:]

    // Defaults:
    // - Simulator: true (no practical Metal acceleration for this app flow)
    // - Physical devices: false (prefer GPU/Metal)
    var isLowPowerMode: Bool = false {
        didSet {
            defaults.set(isLowPowerMode, forKey: PreferenceKey.lowPowerMode)
        }
    }

    // Local OCR/VL import path is temporarily deprecated.
    // Apple Vision OCR is always used for imports for now.
    var useModelOCRForImports: Bool = false {
        didSet {
            if useModelOCRForImports {
                useModelOCRForImports = false
                return
            }
            defaults.set(false, forKey: PreferenceKey.useModelOCRForImports)
        }
    }

    var isLongAnswerMode: Bool = false {
        didSet {
            defaults.set(isLongAnswerMode, forKey: PreferenceKey.longAnswerMode)
        }
    }

    var ragRetrievalProfile: RAGRetrievalProfile = .fastRecommended {
        didSet {
            defaults.set(ragRetrievalProfile.rawValue, forKey: PreferenceKey.ragRetrievalProfile)
        }
    }

    var strictGroundingMode: Bool = false {
        didSet {
            defaults.set(strictGroundingMode, forKey: PreferenceKey.strictGroundingMode)
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
        useModelOCRForImports = false
        defaults.set(false, forKey: PreferenceKey.useModelOCRForImports)
        if defaults.object(forKey: PreferenceKey.longAnswerMode) != nil {
            isLongAnswerMode = defaults.bool(forKey: PreferenceKey.longAnswerMode)
        } else {
            isLongAnswerMode = false
            defaults.set(false, forKey: PreferenceKey.longAnswerMode)
        }
        if let rawSessionId = defaults.string(forKey: PreferenceKey.activeChatSessionId) {
            activeSessionId = UUID(uuidString: rawSessionId)
        }
        if let rawProfile = defaults.string(forKey: PreferenceKey.ragRetrievalProfile),
           let profile = RAGRetrievalProfile(rawValue: rawProfile) {
            ragRetrievalProfile = profile
        } else {
            ragRetrievalProfile = .fastRecommended
            defaults.set(ragRetrievalProfile.rawValue, forKey: PreferenceKey.ragRetrievalProfile)
        }
        strictGroundingMode = defaults.bool(forKey: PreferenceKey.strictGroundingMode)
        noteFeedbackBoosts = loadBoostMap(forKey: PreferenceKey.ragNoteBoosts)
        chunkFeedbackBoosts = loadBoostMap(forKey: PreferenceKey.ragChunkBoosts)
        normalizeStoredModelSelections()
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
        generationStage = nil
    }

    // MARK: - Chat

    func sendMessage(
        text: String,
        notes: [Note] = [],
        knowledgeChunks: [KnowledgeChunk] = [],
        forcedProfile: RAGRetrievalProfile? = nil,
        strictGrounding: Bool? = nil,
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
        let retrievalProfile = forcedProfile ?? ragRetrievalProfile
        let strictGroundingRequest = strictGrounding ?? strictGroundingMode

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
        lastRAGConfidence = .none
        lastRAGTopScore = nil
        lastRAGProfileUsed = retrievalProfile
        generationStage = .searchingSources

        generationTask = Task { @MainActor in
            var ragNoteContext: [Note] = []
            var ragChunkContext: [KnowledgeChunk] = []
            var ragCitations: [CitationRef] = []
            var ragConfidence: RetrievalConfidence = .none

            if !notes.isEmpty || !knowledgeChunks.isEmpty {
                self.generationStage = .searchingSources
                let ragReady = await ensureRAGReadyBeforeSend(
                    notes: notes,
                    knowledgeChunks: knowledgeChunks,
                    modelContext: modelContext
                )
                let eligibleNotes = notes.filter { isNoteEmbeddingFresh($0) }
                let eligibleChunks = knowledgeChunks.filter { isKnowledgeChunkEmbeddingFresh($0) }
                self.lastRAGEligibleNotesCount = eligibleNotes.count
                self.lastRAGEligibleChunksCount = eligibleChunks.count

                var queryEmbedding: [Float]? = nil
                var vectorError: String? = nil
                if ragReady, isEmbeddingModelLoaded, (!eligibleNotes.isEmpty || !eligibleChunks.isEmpty) {
                    do {
                        let embedded = try await llamaContext.embedWithEmbeddingModel(text: userMessageText)
                        queryEmbedding = embedded.isEmpty ? nil : embedded
                        if queryEmbedding == nil {
                            vectorError = LlamaError.noEmbeddings.localizedDescription
                        }
                    } catch {
                        vectorError = error.localizedDescription
                    }
                }
                self.generationStage = .rankingSources

                let retrieval = self.ragPipelineService.retrieveContext(
                    queryText: userMessageText,
                    queryEmbedding: queryEmbedding,
                    notes: notes,
                    chunks: knowledgeChunks,
                    noteBoosts: self.noteFeedbackBoosts,
                    chunkBoosts: self.chunkFeedbackBoosts,
                    semanticNoteIds: Set(eligibleNotes.map(\.id)),
                    semanticChunkIds: Set(eligibleChunks.map(\.id)),
                    profile: retrievalProfile
                )
                ragNoteContext = retrieval.selectedNotes
                ragChunkContext = retrieval.selectedChunks
                ragCitations = retrieval.citations
                ragConfidence = retrieval.confidence
                self.applyRetrievedContextMetadata(
                    notes: ragNoteContext,
                    chunks: ragChunkContext,
                    confidence: retrieval.confidence,
                    topScore: retrieval.topScore
                )

                if ragNoteContext.isEmpty && ragChunkContext.isEmpty {
                    if ragReady, isEmbeddingModelLoaded, eligibleNotes.isEmpty && eligibleChunks.isEmpty {
                        self.ragStatus = .noIndexedNotes
                    } else if let vectorError {
                        self.ragStatus = .failed(vectorError)
                    } else {
                        self.ragStatus = .usedContext(count: 0)
                    }
                } else {
                    self.ragStatus = .usedContext(count: retrieval.selectedCount)
                }
            }

            let messages = buildMessageHistory(
                ragNotes: ragNoteContext,
                ragChunks: ragChunkContext,
                citations: ragCitations,
                retrievalConfidence: ragConfidence,
                strictGrounding: strictGroundingRequest
            )
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
            citationsByAssistantMessageId[assistantMessage.id] = ragCitations
            insightByAssistantMessageId[assistantMessage.id] = AssistantAnswerInsight(
                confidence: ragConfidence,
                topScore: lastRAGTopScore,
                profile: retrievalProfile,
                strictGrounding: strictGroundingRequest,
                sourceCount: ragCitations.count,
                generatedAt: Date()
            )
            generationStage = .draftingAnswer

            var fullResponse = ""

            do {
                let maxTokens = isLongAnswerMode ? 1536 : 768
                let stream = await llamaContext.completion(prompt: prompt, maxTokens: maxTokens)
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
            self.generationStage = nil
        }
    }

    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        Task {
            await llamaContext.stopCompletion()
        }
        isGenerating = false
        generationStage = nil
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
        let scoreText: String
        if let score = lastRAGTopScore {
            scoreText = String(format: "%.2f", score)
        } else {
            scoreText = "-"
        }
        if lastRAGRetrievedTitles.isEmpty && lastRAGRetrievedDocumentTitles.isEmpty {
            return "RAG: notes prepared \(lastRAGPreparedNotesCount), chunks prepared \(lastRAGPreparedChunksCount), notes eligible \(lastRAGEligibleNotesCount), chunks eligible \(lastRAGEligibleChunksCount), retrieved \(lastRAGRetrievedCount), confidence \(lastRAGConfidence.summaryText), top \(scoreText), mode \(lastRAGProfileUsed.displayName)"
        }
        let joinedNotes = lastRAGRetrievedTitles.prefix(2).joined(separator: ", ")
        let joinedDocs = lastRAGRetrievedDocumentTitles.prefix(2).joined(separator: ", ")
        let preview = [joinedNotes, joinedDocs].filter { !$0.isEmpty }.joined(separator: " | ")
        return "RAG: notes prepared \(lastRAGPreparedNotesCount), chunks prepared \(lastRAGPreparedChunksCount), notes eligible \(lastRAGEligibleNotesCount), chunks eligible \(lastRAGEligibleChunksCount), retrieved \(lastRAGRetrievedCount), confidence \(lastRAGConfidence.summaryText), top \(scoreText), mode \(lastRAGProfileUsed.displayName) [\(preview)]"
    }

    func citations(for assistantMessageId: UUID) -> [CitationRef] {
        citationsByAssistantMessageId[assistantMessageId] ?? []
    }

    func insight(for assistantMessageId: UUID) -> AssistantAnswerInsight? {
        insightByAssistantMessageId[assistantMessageId]
    }

    func feedback(for assistantMessageId: UUID) -> AssistantAnswerFeedback? {
        feedbackByAssistantMessageId[assistantMessageId]
    }

    func recordFeedback(_ feedback: AssistantAnswerFeedback, for message: ChatMessage) {
        guard message.role == "assistant" else { return }
        if let previous = feedbackByAssistantMessageId[message.id] {
            applyFeedbackDelta(delta(for: previous) * -1, to: message)
        }
        feedbackByAssistantMessageId[message.id] = feedback
        applyFeedbackDelta(delta(for: feedback), to: message)
        saveBoostMap(noteFeedbackBoosts, forKey: PreferenceKey.ragNoteBoosts)
        saveBoostMap(chunkFeedbackBoosts, forKey: PreferenceKey.ragChunkBoosts)
    }

    private func delta(for feedback: AssistantAnswerFeedback) -> Float {
        switch feedback {
        case .notRelevant:
            return -0.06
        case .partlyWrong:
            return -0.03
        case .missingSource:
            return -0.01
        }
    }

    private func applyFeedbackDelta(_ delta: Float, to message: ChatMessage) {
        for noteId in message.sourceNoteIds {
            noteFeedbackBoosts[noteId] = clampedBoost((noteFeedbackBoosts[noteId] ?? 0) + delta)
        }
        for chunkId in message.sourceKnowledgeChunkIds {
            chunkFeedbackBoosts[chunkId] = clampedBoost((chunkFeedbackBoosts[chunkId] ?? 0) + delta)
        }
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

    func isChunkIndexedForActiveEmbedding(_ chunk: KnowledgeChunk) -> Bool {
        isKnowledgeChunkEmbeddingFresh(chunk)
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

    private func buildMessageHistory(
        ragNotes: [Note] = [],
        ragChunks: [KnowledgeChunk] = [],
        citations: [CitationRef] = [],
        retrievalConfidence: RetrievalConfidence = .none,
        strictGrounding: Bool = false
    ) -> [[String: String]] {
        var messages: [[String: String]] = []
        var systemContent = """
        You are a helpful assistant.
        Give concise, direct answers.
        Do not output chain-of-thought or reasoning tags such as <think>...</think>.
        If context is insufficient, say you are not sure instead of guessing.
        """
        let contextBlock = ragContextBlock(notes: ragNotes, chunks: ragChunks, citations: citations)

        if !contextBlock.isEmpty {
            systemContent += """

            Use retrieved knowledge as the primary source for factual claims.
            Cite grounded claims using [S#] references from the retrieved context.
            Never invent a source id.
            """
            if retrievalConfidence == .low || retrievalConfidence == .none {
                systemContent += "\n\nRetrieved evidence confidence is low. Be explicit about uncertainty when evidence is weak."
            }
            if strictGrounding {
                systemContent += "\n\nStrict grounding mode is ON: do not use facts that are not supported by retrieved context."
            }
        } else if strictGrounding {
            systemContent += "\n\nStrict grounding mode is ON. If evidence is missing, answer: \"I don't have enough evidence in your notes or knowledge base.\" and ask for more sources."
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

    private func ragContextBlock(notes: [Note], chunks: [KnowledgeChunk], citations: [CitationRef]) -> String {
        if !citations.isEmpty {
            return citations.map { citation in
                switch citation.sourceType {
                case .note:
                    return "- [\(citation.id)] [Note: \(citation.title)] \(citation.snippet)"
                case .knowledgeChunk:
                    let indexText = citation.chunkIndex.map { " / chunk \($0)" } ?? ""
                    return "- [\(citation.id)] [KB: \(citation.title)\(indexText)] \(citation.snippet)"
                }
            }.joined(separator: "\n")
        }

        var fallbackCitations: [CitationRef] = []
        for (index, note) in notes.enumerated() {
            let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Note" : note.title
            let snippet = String(note.content.prefix(550)).trimmingCharacters(in: .whitespacesAndNewlines)
            fallbackCitations.append(
                CitationRef(
                    id: "S\(index + 1)",
                    sourceType: .note,
                    title: title,
                    chunkIndex: nil,
                    noteId: note.id,
                    chunkId: nil,
                    snippet: snippet
                )
            )
        }

        for chunk in chunks {
            let rawTitle = chunk.document?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = rawTitle.isEmpty ? "Document" : rawTitle
            let snippet = String(chunk.text.prefix(550)).trimmingCharacters(in: .whitespacesAndNewlines)
            fallbackCitations.append(
                CitationRef(
                    id: "S\(fallbackCitations.count + 1)",
                    sourceType: .knowledgeChunk,
                    title: title,
                    chunkIndex: chunk.chunkIndex + 1,
                    noteId: nil,
                    chunkId: chunk.id,
                    snippet: snippet
                )
            )
        }

        return fallbackCitations.map { citation in
            switch citation.sourceType {
            case .note:
                return "- [\(citation.id)] [Note: \(citation.title)] \(citation.snippet)"
            case .knowledgeChunk:
                let indexText = citation.chunkIndex.map { " / chunk \($0)" } ?? ""
                return "- [\(citation.id)] [KB: \(citation.title)\(indexText)] \(citation.snippet)"
            }
        }.joined(separator: "\n")
    }

    private func applyRetrievedContextMetadata(
        notes: [Note],
        chunks: [KnowledgeChunk],
        confidence: RetrievalConfidence = .none,
        topScore: Float? = nil
    ) {
        retrievedContext = notes
        retrievedKnowledgeContext = chunks
        lastRAGRetrievedCount = notes.count + chunks.count
        lastRAGConfidence = confidence
        lastRAGTopScore = topScore
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
            guard ModelStorage.shared.exists(item) else { return nil }
            let url = try ModelStorage.shared.fileURL(for: item)
            return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
        } catch {
            return nil
        }
    }

    private func findItem(id: String) -> ModelCatalogItem? {
        catalogStore.items.first(where: { $0.id == id })
    }

    private func normalizeStoredModelSelections() {
        if let id = currentChatModelId, findItem(id: id) == nil {
            currentChatModelId = nil
            defaults.removeObject(forKey: PreferenceKey.activeChatModelId)
        }
        if let id = currentEmbeddingModelId, findItem(id: id) == nil {
            currentEmbeddingModelId = nil
            defaults.removeObject(forKey: PreferenceKey.activeEmbeddingModelId)
        }
        if let id = currentOCRModelId, findItem(id: id) == nil {
            currentOCRModelId = nil
            defaults.removeObject(forKey: PreferenceKey.activeOCRModelId)
            useModelOCRForImports = false
        }
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
            if let aux = item.auxiliaryFilename, !aux.isEmpty {
                modelError = "Required files are missing or invalid. Re-download both: \(item.filename) and \(aux)."
            } else {
                modelError = "Model file not found"
            }
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
            let hasVisionContext = await llamaContext.hasVisionOCRContext()
            // When OCR model mode is selected, both OCR and VL entries must provide real vision capability.
            if !hasVisionContext {
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

    private func disableModelOCRFallbackStatus(modelName: String? = nil) async {
        if isOCRModelLoaded || isOCRModelLoading {
            await unloadOCRModelAsync(clearSelection: false)
        }
        currentOCRModelId = nil
        defaults.removeObject(forKey: PreferenceKey.activeOCRModelId)
        useModelOCRForImports = false

        let resolvedName = modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedName, !resolvedName.isEmpty {
            knowledgeImportStatus = "\(resolvedName) could not be loaded. Switched OCR backend to Apple Vision."
        } else {
            knowledgeImportStatus = "Selected OCR/VL model is not ready. Switched OCR backend to Apple Vision."
        }
    }

    private func tryAutoRecoverOCRModel(excluding excludedId: String? = nil) async -> Bool {
        let candidates = (catalogStore.items(kind: .ocr) + catalogStore.items(kind: .vl))
            .filter { $0.id != excludedId && modelPathIfInstalled($0) != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for candidate in candidates {
            await loadOCRModelAsync(item: candidate, persistSelection: true)
            if isOCRModelLoaded {
                touchOCRUsage()
                knowledgeImportStatus = "Switched OCR model to \(candidate.name)."
                return true
            }
        }

        return false
    }

    private func prepareOCRModelForTask() async -> (enabled: Bool, loadedTemporarily: Bool) {
        guard let id = currentOCRModelId,
              let item = findItem(id: id) else {
            if await tryAutoRecoverOCRModel() {
                return (true, true)
            }
            await disableModelOCRFallbackStatus()
            return (false, false)
        }

        guard modelPathIfInstalled(item) != nil else {
            if await tryAutoRecoverOCRModel(excluding: item.id) {
                return (true, true)
            }
            await disableModelOCRFallbackStatus(modelName: item.name)
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

        if await tryAutoRecoverOCRModel(excluding: item.id) {
            return (true, true)
        }

        await disableModelOCRFallbackStatus(modelName: item.name)
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

    private func normalizedForSearch(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenCountEstimate(_ text: String) -> Int {
        text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
    }

    private func inferSectionHint(from text: String) -> String? {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let first = lines.first, !first.isEmpty else { return nil }
        if first.count > 90 {
            return nil
        }
        let words = first.split(separator: " ").count
        guard words > 0 && words <= 12 else { return nil }
        return first
    }

    private func loadBoostMap(forKey key: String) -> [UUID: Float] {
        guard let raw = defaults.dictionary(forKey: key) else { return [:] }
        var result: [UUID: Float] = [:]
        for (idString, value) in raw {
            guard let id = UUID(uuidString: idString) else { continue }
            if let numeric = value as? NSNumber {
                result[id] = Float(truncating: numeric)
            }
        }
        return result
    }

    private func saveBoostMap(_ map: [UUID: Float], forKey key: String) {
        var serialized: [String: Double] = [:]
        serialized.reserveCapacity(map.count)
        for (id, value) in map {
            serialized[id.uuidString] = Double(value)
        }
        defaults.set(serialized, forKey: key)
    }

    private func clampedBoost(_ value: Float) -> Float {
        max(-0.2, min(0.2, value))
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
        note.titleNormalized = normalizedForSearch(note.title)
        note.contentTokenCount = tokenCountEstimate(note.content)

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
        chunk.tokenCount = tokenCountEstimate(chunk.text)
        chunk.charCount = chunk.text.count
        chunk.sectionHint = inferSectionHint(from: chunk.text)
        chunk.documentTitleNormalized = normalizedForSearch(chunk.document?.title ?? "")
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
            if useModelOCRForImports && !ocrSession.enabled {
                isImportingKnowledge = false
                knowledgeImportStatus = "Model OCR is enabled, but the selected OCR/VL model is not ready. Download a compatible model and its mmproj, then load it."
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    if !isImportingKnowledge {
                        knowledgeImportStatus = nil
                    }
                }
                return
            }

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
            guard !useModelOCRForImports || ocrSession.enabled else {
                knowledgeImportStatus = "Model OCR is enabled, but the selected OCR/VL model is not ready. Download a compatible model and its mmproj, then load it."
                return
            }
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
            guard !useModelOCRForImports || ocrSession.enabled else {
                knowledgeImportStatus = "Model OCR is enabled, but the selected OCR/VL model is not ready. Download a compatible model and its mmproj, then load it."
                return
            }
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
                tokenCount: tokenCountEstimate(text),
                charCount: text.count,
                sectionHint: inferSectionHint(from: text),
                documentTitleNormalized: normalizedForSearch(document.title),
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
