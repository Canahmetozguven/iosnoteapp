import Foundation
import SwiftUI
import SwiftData
import CryptoKit

@MainActor
@Observable
class GlobalViewModel {
    let catalogStore = ModelCatalogStore()
    let downloads = ModelDownloadManager.shared.viewModel()
    private let downloadManager = ModelDownloadManager.shared
    let driveSync = DriveSyncService()
    var llamaContext = LlamaContext()
    let vectorSearchService = VectorSearchService()

    private enum PreferenceKey {
        static let activeChatModelId = "active_chat_model_id"
        static let activeEmbeddingModelId = "active_embedding_model_id"
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
    var isChatModelLoading = false
    var isEmbeddingModelLoading = false
    var isGenerating = false
    var isIndexing = false

    var isBusy: Bool {
        isChatModelLoading || isEmbeddingModelLoading || isGenerating || isIndexing
    }

    var currentChatModelId: String? = nil
    var currentEmbeddingModelId: String? = nil

    var modelError: String? = nil
    var ragStatus: RAGStatus = .ready
    var retrievedContext: [Note] = []
    var lastRAGPreparedNotesCount: Int = 0
    var lastRAGEligibleNotesCount: Int = 0
    var lastRAGRetrievedCount: Int = 0

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

    // Progress for indexing (0.0 to 1.0)
    var indexingProgress: Double = 0.0
    var indexingStatus: String? = nil

    private var hasBootstrappedData = false
    private var isModelRehydrateInProgress = false
    private var generationTask: Task<Void, Never>?
    private var pendingAutoIndexTasks: [UUID: Task<Void, Never>] = [:]

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
        isChatModelLoading = false
        isEmbeddingModelLoading = false
    }

    // MARK: - Chat

    func sendMessage(text: String, notes: [Note] = [], modelContext: ModelContext) {
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
        lastRAGPreparedNotesCount = notes.count
        lastRAGEligibleNotesCount = 0
        lastRAGRetrievedCount = 0

        generationTask = Task { @MainActor in
            var ragContext: [Note] = []

            if !notes.isEmpty {
                let ragReady = await ensureRAGReadyBeforeSend(notes: notes, modelContext: modelContext)
                if ragReady, isEmbeddingModelLoaded {
                    let eligibleNotes = notes.filter { isNoteEmbeddingFresh($0) }
                    self.lastRAGEligibleNotesCount = eligibleNotes.count
                    if eligibleNotes.isEmpty {
                        self.ragStatus = .noIndexedNotes
                    } else {
                        do {
                            let queryEmbedding = try await llamaContext.embedWithEmbeddingModel(text: userMessageText)
                            guard !queryEmbedding.isEmpty else {
                                self.ragStatus = .failed("empty query embedding")
                                throw LlamaError.noEmbeddings
                            }
                            let compatibleNotes = eligibleNotes.filter {
                                ($0.embedding?.count ?? 0) == queryEmbedding.count
                            }
                            guard !compatibleNotes.isEmpty else {
                                self.ragStatus = .failed("embedding dimension mismatch")
                                throw LlamaError.noEmbeddings
                            }
                            let foundContext = vectorSearchService.findSimilarNotes(
                                queryEmbedding: queryEmbedding,
                                notes: compatibleNotes,
                                topK: 3
                            )
                            ragContext = foundContext
                            self.retrievedContext = foundContext
                            self.lastRAGRetrievedCount = foundContext.count
                            self.ragStatus = .usedContext(count: foundContext.count)
                        } catch {
                            if case .failed = self.ragStatus {
                                // Keep specific status set above.
                            } else {
                                self.ragStatus = .failed(error.localizedDescription)
                            }
                        }
                    }
                }
            }

            let messages = buildMessageHistory(ragContext: ragContext)
            let prompt = await llamaContext.applyTemplate(messages: messages)

            let sourceNoteIds = ragContext.map { $0.id }
            let assistantMessage = ChatMessage(
                role: "assistant",
                content: "",
                sourceNoteIds: sourceNoteIds,
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
            return "RAG: preparing note index..."
        case .timedOut:
            return "RAG preparation timed out. Answering without note context."
        case .disabledNoEmbeddingModel:
            return "RAG is disabled: load an embedding model."
        case .noIndexedNotes:
            return "No indexed notes for the active embedding model."
        case .usedContext(let count):
            return count > 0 ? "RAG: using \(count) note(s) as context." : "RAG: no relevant notes found."
        case .failed(let message):
            return "RAG failed: \(message)"
        }
    }

    func ragDebugText() -> String? {
        if lastRAGPreparedNotesCount == 0 && lastRAGEligibleNotesCount == 0 && lastRAGRetrievedCount == 0 {
            return nil
        }
        return "RAG notes: prepared \(lastRAGPreparedNotesCount), eligible \(lastRAGEligibleNotesCount), retrieved \(lastRAGRetrievedCount)"
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

    private func ensureRAGReadyBeforeSend(notes: [Note], modelContext: ModelContext) async -> Bool {
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
                    let fallbackEligible = notes.filter { isNoteEmbeddingFresh($0) }
                    if fallbackEligible.isEmpty {
                        ragStatus = .timedOut
                        return false
                    }
                    return true
                }
            }

            if !notesNeedingEmbedding(notes).isEmpty {
                ragStatus = .preparingIndex
                _ = try await ensureIndexedForRAG(notes: notes, modelContext: modelContext, deadline: deadline)
            }

            if timedOut() {
                let fallbackEligible = notes.filter { isNoteEmbeddingFresh($0) }
                if fallbackEligible.isEmpty {
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

    private func buildMessageHistory(ragContext: [Note] = []) -> [[String: String]] {
        var messages: [[String: String]] = []
        var systemContent = "You are a helpful assistant."

        if !ragContext.isEmpty {
            systemContent += "\n\nRelevant context from your notes:\n"
            for note in ragContext {
                let truncatedContent = String(note.content.prefix(500))
                systemContent += "- [\(note.title)]: \(truncatedContent)\n"
            }
            systemContent += "\nUse the above context to help answer the user's question when relevant."
        }

        messages.append([
            "role": "system",
            "content": systemContent
        ])

        for msg in chatMessages {
            messages.append([
                "role": msg.role,
                "content": msg.content
            ])
        }

        return messages
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
            modelError = error.localizedDescription
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
            modelError = error.localizedDescription
            isEmbeddingModelLoaded = false
        }

        isEmbeddingModelLoading = false
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

    private func noteContentHash(_ note: Note) -> String {
        noteContentHash(title: note.title, content: note.content)
    }

    private func noteContentHash(title: String, content: String) -> String {
        let text = "\(title)\n\(content)"
        let digest = SHA256.hash(data: Data(text.utf8))
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

    private func isNoteEmbeddingFresh(_ note: Note) -> Bool {
        guard let embedding = note.embedding, !embedding.isEmpty else { return false }
        guard let modelId = note.embeddingModelId else { return false }
        guard modelId == currentEmbeddingModelId else { return false }
        guard let savedHash = note.embeddingContentHash else { return false }
        return savedHash == noteContentHash(note)
    }
}
