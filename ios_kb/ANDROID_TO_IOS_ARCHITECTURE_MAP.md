# Android to iOS Architecture Map

## 1. Layer Mapping
| Android Layer | Current Android Path | iOS Equivalent (Recommended) | Notes |
|---|---|---|---|
| Presentation | `app/src/main/java/.../feature/` | `Features/` (SwiftUI + ViewModels) | Preserve per-feature ViewModel ownership and state flow behavior. |
| Domain | `app/src/main/java/.../domain/` | `Domain/` (protocols + use cases + pure models) | Keep framework-free business logic. |
| Data/Core | `app/src/main/java/.../core/` | `Core/` + `Data/` | Split infra (AI, storage, sync, prefs) from domain interfaces. |
| Native Engine | `app/src/main/cpp/` | `Native/llama` + Swift bridge | JNI becomes Swift/C++ bridge (Objective-C++ shim if needed). |

## 2. App Composition Parity
Current Android screens from `MainActivity.kt`:
- `onboarding`
- `notes`
- `noteDetail/{noteId}`
- `settings`
- `about_privacy`
- `chat`
- `files`

iOS target:
- Mirror route set with SwiftUI navigation.
- Keep bottom tab parity (`notes`, `chat`, `files`) and push-style detail/settings screens.

## 3. Dependency Injection Mapping
Android uses Hilt modules (e.g. `core/di/AiModule.kt`, `DatabaseModule.kt`, `RepositoryModule.kt`).

iOS recommendation:
- Start with a lightweight container (`AppContainer`) composed at app launch.
- Inject dependencies via initializers into ViewModels.
- Keep singleton lifetime for:
  - `LlmEngine`
  - Database stack
  - Preferences store
  - Model manager

## 4. Async/Concurrency Mapping
Android patterns:
- `viewModelScope.launch`
- `Flow` / `StateFlow`
- `Dispatchers.IO`
- `Mutex` guarding native access in `LlmEngine`

iOS parity:
- Use `async/await` + `Task`.
- Use `@MainActor` for UI state.
- Use `AsyncStream` or `Combine` for token streaming.
- Keep a single concurrency gate around native inference calls (actor or lock).

## 5. Data Model and Storage Mapping
Android database entities:
- `NoteEntity`: id, title, content, createdAt, updatedAt, tags, embedding
- `ChatSessionEntity`: id, title, createdAt, updatedAt
- `ChatMessageEntity`: id, sessionId, content, isUser, timestamp, sourceNoteIds, thoughtProcess

iOS options:
- SwiftData or Core Data (recommended: Core Data for explicit migration control).
- Keep the same fields and timestamp semantics for parity.
- Keep `embedding` persisted as float array (binary blob or transformable).

## 6. Core Behavior That Must Stay Identical
1. Model load fallback order and failure-memory behavior.
2. Chat RAG logic:
   - Use selected notes if user selected notes.
   - Else run vector search only if model requires RAG.
   - Else skip RAG.
3. Streaming token handling:
   - Parse thought tags (`<think>...</think>`) and keep thought process separate.
4. Output sanitization of model control tokens.
5. Auto restore models on app foreground and release engine on background transition.

## 7. Android-to-iOS Service Mapping
| Android Component | iOS Equivalent |
|---|---|
| `LlmEngine` | `LlmEngine` Swift class/actor |
| `LlmContext` + `LlamaContext` JNI | Swift bridge protocol + C/C++ wrapper |
| `ModelManager` | `ModelManager` using app sandbox (`Application Support/models`) |
| `AppPreferences` (SharedPreferences) | `UserDefaults` wrapper |
| Room DAOs | Repository over Core Data/SwiftData |
| WorkManager download/sync | `URLSession` background tasks + app lifecycle aware sync manager |

