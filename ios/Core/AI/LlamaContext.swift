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
    case ocrBridgeUnavailable
    case ocrVisionUnavailable
    case modelFileMissing
    case invalidModelFile
}

actor LlamaContext {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var modelEmbed: OpaquePointer?
    private var contextEmbed: OpaquePointer?
    private var modelOCR: OpaquePointer?
    private var contextOCR: OpaquePointer?
    private var visionOCRContext: OpaquePointer?
    private var visionOCRMarker: String = "<__media__>"
    
    // Batch for chat processing
    private var batch: llama_batch
    private var batchCapacity: Int32
    
    // State for streaming
    private var stopRequested = false
    private var chatGpuEnabled = false
    private var embeddingGpuEnabled = false
    private var ocrGpuEnabled = false
    
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
        if let visionOCRContext = visionOCRContext { mtmd_free(visionOCRContext) }
        if let contextOCR = contextOCR { llama_free(contextOCR) }
        if let modelOCR = modelOCR { llama_model_free(modelOCR) }
    }

    private func resetBatch(capacity: Int32) {
        let safeCapacity = max(Int32(1), capacity)
        llama_batch_free(self.batch)
        self.batchCapacity = safeCapacity
        self.batch = llama_batch_init(safeCapacity, 0, 1)
    }
    
    // MARK: - Model Loading
    
    func loadModel(path: String, lowMemory: Bool = false) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw LlamaError.modelFileMissing
        }
        guard isGGUFFile(path: path) else {
            throw LlamaError.invalidModelFile
        }

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
        guard FileManager.default.fileExists(atPath: path) else {
            throw LlamaError.modelFileMissing
        }
        guard isGGUFFile(path: path) else {
            throw LlamaError.invalidModelFile
        }

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
        unloadOCRModel()
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

    func loadOCRModel(path: String, auxiliaryPath: String? = nil, lowMemory: Bool = false) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw LlamaError.modelFileMissing
        }
        guard isGGUFFile(path: path) else {
            throw LlamaError.invalidModelFile
        }

        if let visionOCRContext = visionOCRContext { mtmd_free(visionOCRContext); self.visionOCRContext = nil }
        if let contextOCR = contextOCR { llama_free(contextOCR); self.contextOCR = nil }
        if let modelOCR = modelOCR { llama_model_free(modelOCR); self.modelOCR = nil }

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = lowMemory ? 0 : 99
        self.ocrGpuEnabled = !lowMemory

        self.modelOCR = llama_model_load_from_file(path, modelParams)
        if self.modelOCR == nil && !lowMemory {
            modelParams.n_gpu_layers = 0
            self.modelOCR = llama_model_load_from_file(path, modelParams)
            self.ocrGpuEnabled = false
        }

        guard let modelOCR = self.modelOCR else {
            throw LlamaError.failedToLoadModel
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = lowMemory ? 2048 : 4096
        ctxParams.n_batch = 512

        self.contextOCR = llama_init_from_model(modelOCR, ctxParams)
        guard self.contextOCR != nil else {
            throw LlamaError.failedToInitContext
        }

        initializeVisionOCRContext(model: modelOCR, modelPath: path, auxiliaryPath: auxiliaryPath, lowMemory: lowMemory)
    }

    private func isGGUFFile(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), let data, data.count == 4 else { return false }
        let expected = Data([0x47, 0x47, 0x55, 0x46]) // "GGUF"
        return data == expected
    }

    func unloadOCRModel() {
        if let visionOCRContext = visionOCRContext {
            mtmd_free(visionOCRContext)
            self.visionOCRContext = nil
        }
        if let contextOCR = contextOCR {
            llama_free(contextOCR)
            self.contextOCR = nil
        }
        if let modelOCR = modelOCR {
            llama_model_free(modelOCR)
            self.modelOCR = nil
        }
        ocrGpuEnabled = false
    }

    func isOCRModelLoaded() -> Bool {
        contextOCR != nil && modelOCR != nil
    }

    func hasVisionOCRContext() -> Bool {
        visionOCRContext != nil
    }

    func extractTextFromImageData(_ imageData: Data) async throws -> String {
        guard !imageData.isEmpty else { return "" }
        guard let contextOCR = self.contextOCR, let modelOCR = self.modelOCR else {
            throw LlamaError.notLoaded
        }
        guard let visionOCRContext = self.visionOCRContext else {
            throw LlamaError.ocrVisionUnavailable
        }

        let marker = visionOCRMarker
        let prompt = "\(marker)\nExtract all readable text from this document image. Return plain text only."
        let promptC = strdup(prompt)
        guard let promptC else { throw LlamaError.decodeFailed }
        defer { free(promptC) }

        var textInput = mtmd_input_text(text: UnsafePointer(promptC), add_special: true, parse_special: true)

        let bitmap: OpaquePointer? = imageData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            return mtmd_helper_bitmap_init_from_buf(visionOCRContext, base, imageData.count)
        }
        guard let bitmap else { throw LlamaError.decodeFailed }
        defer { mtmd_bitmap_free(bitmap) }

        guard let chunks = mtmd_input_chunks_init() else {
            throw LlamaError.decodeFailed
        }
        defer { mtmd_input_chunks_free(chunks) }

        var bitmapArray: [OpaquePointer?] = [bitmap]
        let tokenizeRes = bitmapArray.withUnsafeMutableBufferPointer { bitmapPtr -> Int32 in
            mtmd_tokenize(visionOCRContext, chunks, &textInput, bitmapPtr.baseAddress, 1)
        }
        guard tokenizeRes == 0 else {
            throw LlamaError.decodeFailed
        }

        if let mem = llama_get_memory(contextOCR) {
            llama_memory_clear(mem, true)
        }

        var newNPast: llama_pos = 0
        let evalRes = mtmd_helper_eval_chunks(
            visionOCRContext,
            contextOCR,
            chunks,
            0,
            0,
            Int32(max(1, Int(llama_n_batch(contextOCR)))),
            true,
            &newNPast
        )
        guard evalRes == 0 else {
            throw LlamaError.decodeFailed
        }

        return try sampleText(
            context: contextOCR,
            model: modelOCR,
            startPos: Int32(newNPast),
            maxTokens: 768,
            temperature: 0.1,
            stopSequences: ["<|im_end|>", "<|endoftext|>", "</s>", "<|user|>", "<|assistant|>"]
        )
    }

    func refineOCRText(_ rawText: String) async throws -> String {
        guard let contextOCR = self.contextOCR, let modelOCR = self.modelOCR else {
            throw LlamaError.notLoaded
        }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let prompt = """
        You are an OCR cleanup assistant.
        Fix OCR mistakes in the provided text, preserve meaning and formatting, and return only corrected text.

        OCR INPUT:
        \(trimmed)

        CORRECTED OUTPUT:
        """
        return try generateText(
            prompt: prompt,
            context: contextOCR,
            model: modelOCR,
            maxTokens: 512,
            temperature: 0.2
        )
    }

    func isGpuEnabled() -> Bool {
        chatGpuEnabled || embeddingGpuEnabled || ocrGpuEnabled
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
    
    func embedWithEmbeddingModel(text: String) throws -> [Float] {
        guard let context = self.contextEmbed, let model = self.modelEmbed else {
            throw LlamaError.notLoaded
        }
        return try embed(text: text, context: context, model: model)
    }

    func embed(text: String) throws -> [Float] {
        guard let context = self.contextEmbed ?? self.context,
              let model = self.modelEmbed ?? self.model else {
            throw LlamaError.notLoaded
        }
        return try embed(text: text, context: context, model: model)
    }

    private func embed(text: String, context: OpaquePointer, model: OpaquePointer) throws -> [Float] {
        
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

    private func initializeVisionOCRContext(
        model: OpaquePointer,
        modelPath: String,
        auxiliaryPath: String?,
        lowMemory: Bool
    ) {
        if let visionOCRContext = visionOCRContext {
            mtmd_free(visionOCRContext)
            self.visionOCRContext = nil
        }

        let candidates: [String] = [auxiliaryPath, modelPath].compactMap { $0 }
        guard !candidates.isEmpty else { return }

        var params = mtmd_context_params_default()
        params.use_gpu = !lowMemory
        params.print_timings = false
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount)))
        params.warmup = false
        params.media_marker = mtmd_default_marker()
        params.image_marker = mtmd_default_marker()

        for candidate in candidates {
            guard let ctx = mtmd_init_from_file(candidate, model, params) else {
                continue
            }
            if mtmd_support_vision(ctx) {
                visionOCRContext = ctx
                if let markerPtr = mtmd_default_marker() {
                    visionOCRMarker = String(cString: markerPtr)
                } else {
                    visionOCRMarker = "<__media__>"
                }
                return
            }
            mtmd_free(ctx)
        }
    }

    private func generateText(
        prompt: String,
        context: OpaquePointer,
        model: OpaquePointer,
        maxTokens: Int,
        temperature: Float
    ) throws -> String {
        let tokens = try tokenize(text: prompt, context: context, model: model, addSpecial: true)
        if tokens.isEmpty { return "" }

        if let mem = llama_get_memory(context) {
            llama_memory_clear(mem, true)
        }

        let chunkSize = max(1, min(512, Int(llama_n_batch(context))))
        resetBatch(capacity: Int32(chunkSize))

        for i in stride(from: 0, to: tokens.count, by: chunkSize) {
            let end = min(i + chunkSize, tokens.count)
            self.batch.n_tokens = 0
            for idx in i..<end {
                let isLast = idx == tokens.count - 1
                if !batchAdd(token: tokens[idx], pos: Int32(idx), logits: isLast) {
                    throw LlamaError.batchOverflow
                }
            }
            if llama_decode(context, self.batch) != 0 {
                throw LlamaError.decodeFailed
            }
        }

        var sparams = llama_sampler_chain_default_params()
        let sampler = llama_sampler_chain_init(sparams)
        defer { llama_sampler_free(sampler) }

        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED))

        let n_ctx = Int32(llama_n_ctx(context))
        var nCur = Int32(tokens.count)
        var decoded = 0
        var output = ""

        while decoded < maxTokens && nCur < n_ctx {
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(llama_model_get_vocab(model), token) {
                break
            }

            let piece = tokenToPiece(token: token, model: model)
            output += piece

            self.batch.n_tokens = 0
            if !batchAdd(token: token, pos: nCur, logits: true) {
                throw LlamaError.batchOverflow
            }
            nCur += 1
            decoded += 1

            if llama_decode(context, self.batch) != 0 {
                throw LlamaError.decodeFailed
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sampleText(
        context: OpaquePointer,
        model: OpaquePointer,
        startPos: Int32,
        maxTokens: Int,
        temperature: Float,
        stopSequences: [String]
    ) throws -> String {
        var sparams = llama_sampler_chain_default_params()
        let sampler = llama_sampler_chain_init(sparams)
        defer { llama_sampler_free(sampler) }

        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED))

        let nCtx = Int32(llama_n_ctx(context))
        var nCur = startPos
        var decoded = 0
        var output = ""

        while decoded < maxTokens && nCur < nCtx {
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(llama_model_get_vocab(model), token) {
                break
            }

            let piece = tokenToPiece(token: token, model: model)
            output += piece
            if stopSequences.contains(where: { output.hasSuffix($0) || piece.contains($0) }) {
                break
            }

            self.batch.n_tokens = 0
            if !batchAdd(token: token, pos: nCur, logits: true) {
                throw LlamaError.batchOverflow
            }
            nCur += 1
            decoded += 1

            if llama_decode(context, self.batch) != 0 {
                throw LlamaError.decodeFailed
            }
        }

        var cleaned = output
        for token in stopSequences {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
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

extension LlamaError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failedToLoadModel:
            return "Failed to load model. The file may be incomplete, incompatible, or corrupted."
        case .failedToInitContext:
            return "Failed to initialize llama context. Try Low Power Mode or a smaller model."
        case .decodeFailed:
            return "Model decode failed."
        case .noEmbeddings:
            return "No embeddings returned by model."
        case .notLoaded:
            return "Model is not loaded."
        case .batchOverflow:
            return "Token batch overflow."
        case .ocrBridgeUnavailable:
            return "OCR bridge is unavailable."
        case .ocrVisionUnavailable:
            return "Vision/OCR projector is unavailable for this model."
        case .modelFileMissing:
            return "Model file not found on disk."
        case .invalidModelFile:
            return "Invalid model file format. Expected a GGUF file."
        }
    }
}
