import Foundation
import llama

// Define error types for Llama operations
enum LlamaError: Error {
    case failedToLoadModel
    case failedToInitContext
    case decodeFailed
    case noEmbeddings
    case notLoaded
    case batchOverflow
}

actor LlamaContext {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var modelEmbed: OpaquePointer?
    private var contextEmbed: OpaquePointer?
    
    // Batch for chat processing
    private var batch: llama_batch
    private var batchCapacity: Int32
    
    // State for streaming
    private var stopRequested = false
    private var chatGpuEnabled = false
    private var embeddingGpuEnabled = false
    
    init() {
        self.batchCapacity = 512
        self.batch = llama_batch_init(batchCapacity, 0, 1)
        
        // Initialize backend (only needs to happen once ideally, but safe to call multiple times if idempotent or handled by app init)
        llama_backend_init()
    }
    
    deinit {
        llama_batch_free(batch)
        if let context = context { llama_free(context) }
        if let model = model { llama_model_free(model) }
        if let contextEmbed = contextEmbed { llama_free(contextEmbed) }
        if let modelEmbed = modelEmbed { llama_model_free(modelEmbed) }
    }

    private func resetBatch(capacity: Int32) {
        let safeCapacity = max(Int32(1), capacity)
        llama_batch_free(self.batch)
        self.batchCapacity = safeCapacity
        self.batch = llama_batch_init(safeCapacity, 0, 1)
    }
    
    // MARK: - Model Loading
    
    func loadModel(path: String, lowMemory: Bool = false) throws {
        // Cleanup existing
        if let context = context { llama_free(context); self.context = nil }
        if let model = model { llama_model_free(model); self.model = nil }
        
        var modelParams = llama_model_default_params()
        
         // GPU Strategy:
         // If lowMemory (Low Power Mode) is true, force CPU immediately to avoid Metal crash/overhead
        if lowMemory {
             print("LlamaContext: Low Power Mode active. Forcing CPU.")
            modelParams.n_gpu_layers = 0
            self.chatGpuEnabled = false
        } else {
            // -1 to offload all layers to GPU (Metal on iOS)
            modelParams.n_gpu_layers = 99
            self.chatGpuEnabled = true
        }
        
        print("LlamaContext: Loading model from \(path)")
        self.model = llama_model_load_from_file(path, modelParams)
        
        // Fallback to CPU if GPU load fails (simulating native-lib behavior)
        if self.model == nil && !lowMemory {
            print("LlamaContext: Failed to load with GPU, retrying CPU only...")
            modelParams.n_gpu_layers = 0
            self.model = llama_model_load_from_file(path, modelParams)
            self.chatGpuEnabled = false
        }
        
        guard let model = self.model else {
            throw LlamaError.failedToLoadModel
        }
        
         var ctxParams = llama_context_default_params()
         // Reduced context for Low Power Mode / Low Memory environments
         ctxParams.n_ctx = lowMemory ? 2048 : 4096
        ctxParams.n_batch = 512
        
        self.context = llama_init_from_model(model, ctxParams)
        guard self.context != nil else {
            throw LlamaError.failedToInitContext
        }
        
        print("LlamaContext: Chat model loaded successfully (ctx: \(ctxParams.n_ctx))")
    }
    
    func loadEmbeddingModel(path: String, lowMemory: Bool = false) throws {
        if let contextEmbed = contextEmbed { llama_free(contextEmbed); self.contextEmbed = nil }
        if let modelEmbed = modelEmbed { llama_model_free(modelEmbed); self.modelEmbed = nil }
        
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = lowMemory ? 0 : 99
        self.embeddingGpuEnabled = !lowMemory
        
        print("LlamaContext: Loading embedding model from \(path)")
        self.modelEmbed = llama_model_load_from_file(path, modelParams)
        
        if self.modelEmbed == nil && !lowMemory {
            modelParams.n_gpu_layers = 0
            self.modelEmbed = llama_model_load_from_file(path, modelParams)
            self.embeddingGpuEnabled = false
        }
        
        guard let modelEmbed = self.modelEmbed else {
            throw LlamaError.failedToLoadModel
        }
        
        var ctxParams = llama_context_default_params()
        ctxParams.embeddings = true
        ctxParams.n_batch = 2048
        
        self.contextEmbed = llama_init_from_model(modelEmbed, ctxParams)
        guard self.contextEmbed != nil else {
            throw LlamaError.failedToInitContext
        }
        
        print("LlamaContext: Embedding model loaded successfully")
    }

    func unload() {
        unloadChat()
        unloadEmbedding()
    }

    func unloadChat() {
        stopRequested = true
        if let context = context {
            llama_free(context)
            self.context = nil
        }
        if let model = model {
            llama_model_free(model)
            self.model = nil
        }
        chatGpuEnabled = false
    }

    func unloadEmbedding() {
        if let contextEmbed = contextEmbed {
            llama_free(contextEmbed)
            self.contextEmbed = nil
        }
        if let modelEmbed = modelEmbed {
            llama_model_free(modelEmbed)
            self.modelEmbed = nil
        }
        embeddingGpuEnabled = false
    }

    func isGpuEnabled() -> Bool {
        chatGpuEnabled || embeddingGpuEnabled
    }
    
    // MARK: - Completion
    
    func stopCompletion() {
        self.stopRequested = true
    }
    
    func completion(prompt: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let model = self.model, let context = self.context else {
                        throw LlamaError.notLoaded
                    }
                    
                    self.stopRequested = false
                    
                    // Tokenize
                    let tokens = try tokenize(text: prompt, context: context, model: model, addSpecial: true)
                    
                    // Clear KV cache for new chat
                    // In a real chat app with history, we might want to be smarter about this (KV cache reuse),
                    // but for now, matching the Android "stateless" prompt approach per request or full history re-eval.
                    if let mem = llama_get_memory(context) {
                        llama_memory_clear(mem, true)
                    }
                    
                    let n_ctx = Int32(llama_n_ctx(context))
                    let maxPromptTokens = max(1, Int(n_ctx - 1))
                    let promptTokens = tokens.count > maxPromptTokens ? Array(tokens.suffix(maxPromptTokens)) : tokens
                    let n_tokens = promptTokens.count
                    let chunkSize = max(1, min(512, Int(llama_n_batch(context))))
                    resetBatch(capacity: Int32(chunkSize))
                    
                    // Process prompt in chunks
                    for i in stride(from: 0, to: n_tokens, by: chunkSize) {
                        let chunkEnd = min(i + chunkSize, n_tokens)
                        let chunk = Array(promptTokens[i..<chunkEnd])
                        
                        // Clear batch for this chunk
                        self.batch.n_tokens = 0
                        
                        for (idx, token) in chunk.enumerated() {
                            let pos = Int32(i + idx)
                            let isLast = (i + idx) == (n_tokens - 1)
                            if !batchAdd(token: token, pos: pos, logits: isLast) {
                                throw LlamaError.batchOverflow
                            }
                        }
                        
                        if llama_decode(context, self.batch) != 0 {
                            throw LlamaError.decodeFailed
                        }
                    }
                    
                    // Sampler setup
                    var sparams = llama_sampler_chain_default_params()
                    let sampler = llama_sampler_chain_init(sparams)
                    defer { llama_sampler_free(sampler) }
                    
                    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
                    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
                    llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
                    llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED))
                    
                    // Generation Loop
                    var n_cur = Int32(n_tokens)
                    var n_decode = 0
                    let max_tokens = 2048
                    
                    // Stop sequences (matching Android)
                    let stopSequences = [
                        "<｜User｜>", "<｜Assistant｜>", "<｜end▁of▁sentence｜>",
                        "<|im_end|>", "<|im_start|>",
                        "</s>", "<|endoftext|>"
                    ]
                    var generatedTextBuffer = ""
                    
                    while n_decode < max_tokens && n_cur < n_ctx {
                        if self.stopRequested || Task.isCancelled {
                            print("LlamaContext: Generation stopped")
                            break
                        }
                        
                        let newTokenId = llama_sampler_sample(sampler, context, -1)
                        
                        if llama_vocab_is_eog(llama_model_get_vocab(model), newTokenId) {
                            break
                        }
                        
                        // Convert token to string
                        let piece = tokenToPiece(token: newTokenId, model: model)
                        generatedTextBuffer += piece
                        
                        // Check stop sequences
                        var shouldStop = false
                        for seq in stopSequences {
                            // Check if buffer ends with seq
                            if generatedTextBuffer.hasSuffix(seq) {
                                shouldStop = true
                                break
                            }
                             // Or if piece contains seq (rare but possible)
                            if piece.contains(seq) {
                                shouldStop = true
                                break
                            }
                        }
                        
                        // Yield result BEFORE breaking if it was a stop sequence? 
                        // Usually we don't yield the stop token.
                        // For simplicity, we yield everything and let UI handle or trim.
                        // But strictly:
                        if !shouldStop {
                            continuation.yield(piece)
                        } else {
                            break
                        }
                        
                        // Prepare next batch
                        self.batch.n_tokens = 0
                        if !batchAdd(token: newTokenId, pos: n_cur, logits: true) {
                            throw LlamaError.batchOverflow
                        }
                        n_cur += 1
                        n_decode += 1
                        
                        if llama_decode(context, self.batch) != 0 {
                            throw LlamaError.decodeFailed
                        }
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Embeddings
    
    func embed(text: String) throws -> [Float] {
        // Prefer dedicated embedding context, fallback to chat context
        guard let context = self.contextEmbed ?? self.context,
              let model = self.modelEmbed ?? self.model else {
            throw LlamaError.notLoaded
        }
        
        let tokens = try tokenize(text: text, context: context, model: model, addSpecial: true)
        let n_tokens = Int32(tokens.count)
        
        if n_tokens == 0 { return [] }
        
        // Clear KV for clean embedding
        if let mem = llama_get_memory(context) {
            llama_memory_clear(mem, true)
        }
        
        let chunkSize = max(1, min(Int(llama_n_batch(context)), 1024))
        resetBatch(capacity: Int32(chunkSize))

        for i in stride(from: 0, to: Int(n_tokens), by: chunkSize) {
            let chunkEnd = min(i + chunkSize, Int(n_tokens))
            self.batch.n_tokens = 0
            for idx in i..<chunkEnd {
                if !batchAdd(token: tokens[idx], pos: Int32(idx), logits: (idx == Int(n_tokens) - 1)) {
                    throw LlamaError.batchOverflow
                }
            }

            if llama_decode(context, self.batch) != 0 {
                throw LlamaError.decodeFailed
            }
        }
        
        // Retrieve embeddings
        // llama_get_embeddings returns pointer to float array of size n_embd
        guard let embeddingPtr = llama_get_embeddings(context) else {
            throw LlamaError.noEmbeddings
        }
        
        let n_embd = Int(llama_model_n_embd(model))
        let buffer = UnsafeBufferPointer(start: embeddingPtr, count: n_embd)
        var embeddings = Array(buffer)
        
        // Normalize (Cosine Similarity preparation)
        let sumSq = embeddings.reduce(0) { $0 + $1 * $1 }
        let norm = sqrt(sumSq)
        if norm > 0 {
            embeddings = embeddings.map { $0 / norm }
        }
        
        return embeddings
    }
    
    // MARK: - Helpers
    
    @discardableResult
    private func batchAdd(token: llama_token, pos: llama_pos, logits: Bool) -> Bool {
        if self.batch.n_tokens >= self.batchCapacity {
            return false
        }
        let i = Int(self.batch.n_tokens)
        self.batch.token[i] = token
        self.batch.pos[i] = pos
        self.batch.n_seq_id[i] = 1
        self.batch.seq_id[i]![0] = 0 // seq_id 0
        self.batch.logits[i] = logits ? 1 : 0
        self.batch.n_tokens += 1
        return true
    }
    
    private func tokenize(text: String, context: OpaquePointer, model: OpaquePointer, addSpecial: Bool) throws -> [llama_token] {
        let vocab = llama_model_get_vocab(model)
        let textLen = Int32(text.utf8.count)
        let maxTokens = textLen + 100
        
        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        
        var n_tokens = llama_tokenize(vocab, text, textLen, &tokens, Int32(tokens.count), addSpecial, true)
        
        if n_tokens < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n_tokens))
            n_tokens = llama_tokenize(vocab, text, textLen, &tokens, Int32(tokens.count), addSpecial, true)
        }
        
        if n_tokens >= 0 {
            return Array(tokens.prefix(Int(n_tokens)))
        } else {
            return []
        }
    }
    
    private func tokenToPiece(token: llama_token, model: OpaquePointer) -> String {
        let vocab = llama_model_get_vocab(model)
        // Buffer for token string
        var buffer = [CChar](repeating: 0, count: 256)
        let n = llama_token_to_piece(vocab, token, &buffer, 256, 0, true)
        if n > 0 {
            let data = Data(bytes: buffer, count: Int(n))
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }
    
    func applyTemplate(messages: [[String: String]]) -> String {
        guard let model = self.model, !messages.isEmpty else {
            return applyManualTemplate(messages: messages)
        }

        var cMessages = [llama_chat_message](repeating: llama_chat_message(role: nil, content: nil), count: messages.count)
        var allocated = [UnsafeMutablePointer<CChar>]()
        allocated.reserveCapacity(messages.count * 2)

        for (idx, msg) in messages.enumerated() {
            let role = msg["role"] ?? "user"
            let content = msg["content"] ?? ""

            guard let roleDup = strdup(role), let contentDup = strdup(content) else {
                return applyManualTemplate(messages: messages)
            }
            allocated.append(roleDup)
            allocated.append(contentDup)
            cMessages[idx] = llama_chat_message(role: UnsafePointer(roleDup), content: UnsafePointer(contentDup))
        }

        defer {
            for ptr in allocated {
                free(ptr)
            }
        }

        let tmpl = llama_model_chat_template(model, nil)
        let estimatedChars = max(1024, messages.reduce(0) { $0 + (($1["content"]?.utf8.count ?? 0) + 32) } * 2)
        var buffer = [CChar](repeating: 0, count: estimatedChars)

        let rendered: String? = cMessages.withUnsafeBufferPointer { chatPtr in
            guard let chatBase = chatPtr.baseAddress else {
                return nil
            }

            return buffer.withUnsafeMutableBufferPointer { outPtr in
                guard let outBase = outPtr.baseAddress else {
                    return nil
                }

                var outLen = llama_chat_apply_template(
                    tmpl,
                    chatBase,
                    cMessages.count,
                    true,
                    outBase,
                    Int32(outPtr.count)
                )

                if outLen < 0 {
                    return nil
                }

                if outLen >= Int32(outPtr.count) {
                    var resized = [CChar](repeating: 0, count: Int(outLen) + 1)
                    outLen = resized.withUnsafeMutableBufferPointer { resizedPtr in
                        guard let resizedBase = resizedPtr.baseAddress else { return Int32(-1) }
                        return llama_chat_apply_template(
                            tmpl,
                            chatBase,
                            cMessages.count,
                            true,
                            resizedBase,
                            Int32(resizedPtr.count)
                        )
                    }
                    guard outLen >= 0 else { return nil }
                    return String(cString: resized)
                }

                return String(cString: outBase)
            }
        }

        return rendered ?? applyManualTemplate(messages: messages)
    }

    private func applyManualTemplate(messages: [[String: String]]) -> String {
        let systemPrompt = messages.first { $0["role"] == "system" }?["content"] ?? ""
        var formatted = ""
        if !systemPrompt.isEmpty {
            formatted += "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
        }
        for msg in messages {
            if let role = msg["role"], let content = msg["content"], role != "system" {
                formatted += "<|im_start|>\(role)\n\(content)<|im_end|>\n"
            }
        }
        formatted += "<|im_start|>assistant\n"
        return formatted
    }
}
