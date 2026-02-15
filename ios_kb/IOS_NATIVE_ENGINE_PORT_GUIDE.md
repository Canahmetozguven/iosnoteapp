# iOS Native Engine Port Guide

## Objective
Port Android `LlmEngine` + JNI behavior to iOS while keeping runtime behavior equivalent.

## Android Reference
- Engine orchestration: `app/src/main/java/com/synapsenotes/ai/core/ai/LlmEngine.kt`
- Native interface: `app/src/main/java/com/synapsenotes/ai/core/ai/LlmContext.kt`
- Native symbols: `app/src/main/java/com/synapsenotes/ai/core/ai/LlamaContext.kt`
- C++ implementation: `app/src/main/cpp/native-lib.cpp`
- Session state: `app/src/main/cpp/LlmSession.h`

## Required iOS Engine Surface
Create an iOS `LlmContext` protocol matching Android capabilities:
- `loadModel(path:template:nBatch:nCtx:useMmap:backend:) -> Bool`
- `loadEmbeddingModel(path:nBatch:nCtx:useMmap:backend:) -> Bool`
- `completion(prompt:systemPrompt:stopSequences:onToken:) async throws -> String`
- `stopCompletion()`
- `embed(text:) throws -> [Float]`
- `unload()`, `unloadChat()`, `unloadEmbedding()`
- `isGpuEnabled() -> Bool`

Then create `LlmEngine` wrapper with:
- backend fallback ordering
- timeout for model loading
- single-thread access gate for native calls
- stream-token interface for chat/note AI actions

## Backend Strategy for iOS
Android uses CPU/OpenCL/Vulkan with device heuristics.  
iOS implementation should use:
- Metal backend first (if enabled in `llama.cpp` build)
- CPU fallback always available

Preserve the same control flow:
1. Determine preferred backend.
2. Try preferred backend first.
3. On failure, mark backend failed and try fallback.
4. Persist preferred/failed state to preferences.

## Crash-Safe Attempt Tracking (Port This)
Android writes "attempting backend" before risky native calls and clears it after success.  
iOS should replicate with `UserDefaults`:
- `attempting_backend`
- `attempting_embedding_backend`
- `failed_backends`
- `preferred_backend`
- `preferred_embedding_backend`

On app launch:
- If `attempting_*` exists from previous run, mark that backend failed.
- Clear `attempting_*` keys after processing.

## Streaming and Sanitization Parity
Keep these semantics from Android:
- Token stream may contain `<think>...</think>` or control tokens.
- Separate `thoughtProcess` text from final assistant answer.
- Sanitize output tokens using logic equivalent to `OutputSanitizer.kt`.

## Model Lifecycle Parity
From Android behavior:
- Chat and embedding models can be loaded separately.
- Existing model is unloaded before loading a new one.
- App background transition triggers release/unload.
- Foreground restores active models if configured and memory permits.

iOS implementation:
- Hook into scene phase transitions.
- On background: release engine memory.
- On active: restore previously selected model(s) carefully.

## File and Model Management Parity
Android `ModelManager.kt`:
- Copies bundled `.gguf` from app assets.
- Stores runtime models in app files directory.
- Can download sidecar config `.json`.

iOS target:
- Bundle initial models in app resources (if size policy allows).
- Runtime models in `Application Support/models/`.
- Keep filename-based active model references in prefs.

## Porting Risks to Track
1. Token stream threading bugs (UI updates on background thread).
2. Deadlocks around stop-generation.
3. Loading timeout mismatch causing frozen UX.
4. Context/window size mismatch causing model failures.
5. Missing sanitization leading to visible control tokens in UI.

