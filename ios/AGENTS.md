# AGENTS.md - iOS App Source

## Overview
Modular Clean Architecture targeting iOS 17+. Optimized for local LLM execution and SwiftData persistence.

## Layer Map
- **App/**: Entry point, App lifecycle, dependency injection.
- **Core/**: Shared infrastructure and AI bridging.
    - `AI/LlamaContext`: `Actor` for thread-safe llama.cpp interaction.
    - `AI/ModelManager`: Lifecycle and resource management for GGUF files.
    - `GlobalViewModel`: App-wide state (@Observable).
- **Data/**: Persistence and external sources.
    - `Models/SchemaV1`: SwiftData definitions.
    - `Repositories`: Abstracted data access.
- **Domain/**: Business logic and AI services.
    - `Services/VectorSearchService`: RAG logic (cosine similarity).
- **UI/**: SwiftUI views and local view models.
    - `Chat`, `Notes`, `Settings`: Domain-specific view trees.

## Conventions
- **State Management**: Use `@Observable` macro (iOS 17). Avoid `ObservableObject` unless legacy interop required.
- **Concurrency**: Prefer `async/await`. Critical AI operations MUST run on dedicated `Actors` to avoid blocking main thread.
- **AI Execution**:
    - Default: Metal (GPU) acceleration.
    - Fallback: Low Power Mode restricts context size and uses CPU-only if necessary.
- **Parsing**: LLM outputs containing `<think>...</think>` tags must be parsed to separate reasoning from final response.
- **RAG Implementation**: MVP uses linear cosine similarity scan over local embeddings.
- **UI Patterns**: View-State-Action (VSA). Keep views lean; move logic to `@Observable` view models.

## Key Entry Points
- Bridge: `Core/AI/LlamaContext.swift`
- Persistence: `Data/Models/SchemaV1.swift`
- Global State: `Core/GlobalViewModel.swift`
