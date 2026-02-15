import Foundation
import SwiftUI
import SwiftData

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
    }
    private let defaults = UserDefaults.standard

    var isChatModelLoaded: Bool = false
    var isEmbeddingModelLoaded: Bool = false

    var currentChatModelId: String? = nil
    var currentEmbeddingModelId: String? = nil

    var modelError: String? = nil
    var isBusy: Bool = false

    func displayName(for modelId: String?) -> String {
        guard let modelId else { return "None" }
        return catalogStore.items.first(where: { $0.id == modelId })?.name ?? modelId
    }
    
    // Defaults:
    // - Simulator: true (no practical Metal acceleration for this app flow)
    // - Physical devices: false (prefer GPU/Metal)
    var isLowPowerMode: Bool = false {
        didSet {
            defaults.set(isLowPowerMode, forKey: PreferenceKey.lowPowerMode)
        }
    }
    
    // Chat state
    var chatMessages: [ChatMessage] = [] // In-memory for current session, or fetch from DB
    
    // Track current generation task for cancellation
    private var generationTask: Task<Void, Never>?

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
            // If deleting active model, unload it first.
            if currentChatModelId == item.id { unloadChatModel() }
            if currentEmbeddingModelId == item.id { unloadEmbeddingModel() }
            try downloadManager.deleteDownloaded(item)
        } catch {
            modelError = error.localizedDescription
        }
    }

    func loadChatModel(item: ModelCatalogItem) {
        guard item.kind == .chat else { return }
        guard let path = modelPathIfInstalled(item) else {
            modelError = "Model file not found"
            return
        }
        
        isBusy = true
        modelError = nil
        
        Task {
            do {
                // Pass low power mode flag
                try await llamaContext.loadModel(path: path, lowMemory: isLowPowerMode)
                
                await MainActor.run {
                    self.isChatModelLoaded = true
                    self.currentChatModelId = item.id
                    self.defaults.set(item.id, forKey: PreferenceKey.activeChatModelId)
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.modelError = error.localizedDescription
                    self.isChatModelLoaded = false
                    self.isBusy = false
                }
            }
        }
    }

    func loadEmbeddingModel(item: ModelCatalogItem) {
        guard item.kind == .embedding else { return }
        guard let path = modelPathIfInstalled(item) else {
            modelError = "Model file not found"
            return
        }

        isBusy = true
        modelError = nil

        Task {
            do {
                try await llamaContext.loadEmbeddingModel(path: path, lowMemory: isLowPowerMode)
                await MainActor.run {
                    self.isEmbeddingModelLoaded = true
                    self.currentEmbeddingModelId = item.id
                    self.defaults.set(item.id, forKey: PreferenceKey.activeEmbeddingModelId)
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.modelError = error.localizedDescription
                    self.isEmbeddingModelLoaded = false
                    self.isBusy = false
                }
            }
        }
    }

    func unloadChatModel() {
        Task {
            await llamaContext.unloadChat()
            await MainActor.run {
                self.isChatModelLoaded = false
                self.currentChatModelId = nil
                self.defaults.removeObject(forKey: PreferenceKey.activeChatModelId)
            }
        }
    }

    func unloadEmbeddingModel() {
        Task {
            await llamaContext.unloadEmbedding()
            await MainActor.run {
                self.isEmbeddingModelLoaded = false
                self.currentEmbeddingModelId = nil
                self.defaults.removeObject(forKey: PreferenceKey.activeEmbeddingModelId)
            }
        }
    }

    func handleSceneDidBecomeActive() {
        downloadManager.restorePendingTasks()

        if !isBusy, !isChatModelLoaded, let id = currentChatModelId, let item = findItem(id: id), modelPathIfInstalled(item) != nil {
            loadChatModel(item: item)
        }
        if !isBusy, !isEmbeddingModelLoaded, let id = currentEmbeddingModelId, let item = findItem(id: id), modelPathIfInstalled(item) != nil {
            loadEmbeddingModel(item: item)
        }
    }

    func handleSceneDidEnterBackground() {
        stopGeneration()
        Task {
            await llamaContext.unload()
        }
        isChatModelLoaded = false
        isEmbeddingModelLoaded = false
        isBusy = false
    }
    
    // MARK: - Chat
    
    /// RAG context retrieved for the current query (for UI display if needed)
    var retrievedContext: [Note] = []
    
    func sendMessage(text: String, notes: [Note] = []) {
        guard isChatModelLoaded, !isBusy else { return }
        
        // Create and append user message
        let userMessage = ChatMessage(role: "user", content: text)
        chatMessages.append(userMessage)
        
        isBusy = true
        retrievedContext = []
        
        generationTask = Task {
            // RAG: Find relevant notes if available
            var ragContext: [Note] = []
            if !notes.isEmpty {
                do {
                    let queryEmbedding = try await llamaContext.embed(text: text)
                    if !queryEmbedding.isEmpty {
                        let foundContext = vectorSearchService.findSimilarNotes(
                            queryEmbedding: queryEmbedding,
                            notes: notes,
                            topK: 3
                        )
                        ragContext = foundContext
                        await MainActor.run {
                            self.retrievedContext = foundContext
                        }
                    }
                } catch {
                    print("RAG embedding failed: \(error.localizedDescription)")
                    // Continue without RAG context
                }
            }
            
            // Build prompt using chat template with RAG context
            let messages = buildMessageHistory(ragContext: ragContext, userQuery: text)
            let prompt = await llamaContext.applyTemplate(messages: messages)
            
            // Create assistant message placeholder
            let sourceNoteIds = ragContext.map { $0.id }
            let assistantMessage = ChatMessage(role: "assistant", content: "", sourceNoteIds: sourceNoteIds)
            await MainActor.run {
                chatMessages.append(assistantMessage)
            }
            
            var fullResponse = ""
            
            do {
                let stream = await llamaContext.completion(prompt: prompt)
                
                for try await token in stream {
                    if Task.isCancelled { break }
                    
                    fullResponse += token
                    let responseSnapshot = fullResponse
                     
                    // Parse and update the message on main thread
                    await MainActor.run {
                        let parsed = parseThinkTags(responseSnapshot)
                        assistantMessage.content = parsed.content
                        assistantMessage.thoughtProcess = parsed.thought
                    }
                }
            } catch {
                await MainActor.run {
                    assistantMessage.content = "Error: \(error.localizedDescription)"
                }
            }
            
            await MainActor.run {
                self.isBusy = false
            }
        }
    }
    
    func stopGeneration() {
        generationTask?.cancel()
        Task {
            await llamaContext.stopCompletion()
        }
        isBusy = false
    }
    
    // MARK: - Indexing (RAG)
    
    /// Progress for indexing (0.0 to 1.0)
    var indexingProgress: Double = 0.0
    var indexingStatus: String? = nil
    
    /// Index all notes by generating embeddings.
    /// Updates note.embedding directly (Note is a class, SwiftData persists changes).
    func indexAllNotes(notes: [Note]) {
        guard isEmbeddingModelLoaded, !isBusy else { return }
        
        isBusy = true
        indexingProgress = 0.0
        indexingStatus = "Starting indexing..."
        
        Task {
            let total = notes.count
            var indexed = 0
            var failed = 0
            
            for note in notes {
                do {
                    let textToEmbed = "\(note.title)\n\(note.content)"
                    let embedding = try await llamaContext.embed(text: textToEmbed)
                    
                    // Update the note's embedding (Note is a class, mutation persists)
                    await MainActor.run {
                        note.embedding = embedding
                    }
                    indexed += 1
                } catch {
                    print("Failed to embed note '\(note.title)': \(error.localizedDescription)")
                    failed += 1
                }
                
                // Update progress
                let indexedNow = indexed
                let failedNow = failed
                await MainActor.run {
                    self.indexingProgress = Double(indexedNow + failedNow) / Double(total)
                    self.indexingStatus = "Indexed \(indexedNow)/\(total) notes..."
                }
            }
            
            let indexedFinal = indexed
            let failedFinal = failed
            await MainActor.run {
                self.isBusy = false
                self.indexingStatus = "Completed: \(indexedFinal) indexed, \(failedFinal) failed"
                
                // Clear status after delay
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await MainActor.run {
                        self.indexingStatus = nil
                        self.indexingProgress = 0.0
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func buildMessageHistory(ragContext: [Note] = [], userQuery: String? = nil) -> [[String: String]] {
        // Convert ChatMessage array to dict format for template
        var messages: [[String: String]] = []
        
        // Build system prompt with optional RAG context
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
        // Parse <think>...</think> tags from response
        let thinkPattern = #"<think>([\s\S]*?)</think>"#
        
        guard let regex = try? NSRegularExpression(pattern: thinkPattern, options: []) else {
            return (text, nil)
        }
        
        let range = NSRange(text.startIndex..., in: text)
        var thoughtContent: String? = nil
        var cleanedContent = text
        
        // Extract all think blocks
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
}

private extension GlobalViewModel {
    func findItem(id: String) -> ModelCatalogItem? {
        catalogStore.items.first(where: { $0.id == id })
    }

    func modelPathIfInstalled(_ item: ModelCatalogItem) -> String? {
        do {
            let url = try ModelStorage.shared.fileURL(for: item)
            return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
        } catch {
            return nil
        }
    }
}
