# Change List

## 1. Data Model and Migration
- Added `SchemaV2` with:
  - `ChatSession` model for conversation grouping.
  - `ChatMessage.session` relationship.
  - Note embedding metadata: `embeddingModelId`, `embeddingUpdatedAt`, `embeddingContentHash`.
- Added `AppSchemaMigrationPlan` for `SchemaV1 -> SchemaV2` lightweight migration.
- Added current schema aliases in `ios/Data/Models/CurrentSchema.swift`.
- Updated app container setup to use `SchemaV2` + migration plan.

## 2. Chat Sessions (New Chat / Previous Chats)
- Reworked global chat state to be session-based and persisted in SwiftData.
- Added bootstrap migration logic to move ungrouped legacy messages into a `Legacy Chat` session.
- Added session operations:
  - Create new chat
  - Select previous chat
  - Rename chat
  - Delete chat
- Added automatic session title generation from first user message.

## 3. RAG Reliability Fixes
- Added strict embedding retrieval path (`embedWithEmbeddingModel`) that requires an embedding model context.
- Removed reliance on chat-model fallback for RAG retrieval path.
- Added RAG status states and user-facing status text.
- Restricted retrieval to notes whose embeddings are fresh and match the active embedding model/content hash.

## 4. Auto Indexing
- Added per-note debounced auto-index trigger from note edit events.
- Mark edited notes stale immediately by clearing embedding and metadata.
- Added indexing metadata writeback during embedding generation.
- Kept manual `Index All Notes` action for full repair pass.

## 5. Model Lifecycle and Reload Behavior
- Reworked loading state into explicit flags:
  - `isChatModelLoading`
  - `isEmbeddingModelLoading`
  - `isGenerating`
  - `isIndexing`
- Fixed foreground resume flow to deterministically reload both chat and embedding models.
- Added per-model reload actions:
  - `reloadChatModel(item:)`
  - `reloadEmbeddingModel(item:)`
- Added `Reload` button on each model row in Settings.

## 6. Chat and Settings UI Refresh
- Updated chat screen with:
  - Top-left previous chats drawer
  - New chat action
  - Session-aware title
  - RAG status banner
  - Refined composer and message layout
- Updated settings screen with:
  - Session count in status
  - Per-row model reload controls
  - Fresh-embedding count based on active embedding model

## 7. Backup/Restore Compatibility
- Extended backup payload to include:
  - Chat sessions
  - Message `sessionId`
  - Note embedding metadata fields
- Export version bumped to `2`.
- Importer supports older payloads (missing sessions/session IDs) by creating/using fallback legacy session.

## Files Added
- `CHANGE_LIST.md`
- `ios/Data/Models/SchemaV2.swift`
- `ios/Data/Models/SchemaMigrationPlan.swift`
- `ios/Data/Models/CurrentSchema.swift`
- `ios/UI/Chat/ChatView.swift` (rewritten)
- `ios/UI/Chat/Components/MessageBubble.swift` (rewritten)

## Files Updated
- `ios/App/LlmNotesApp.swift`
- `ios/Core/AI/LlamaContext.swift`
- `ios/Core/GlobalViewModel.swift` (rewritten)
- `ios/UI/Settings/SettingsView.swift`
- `ios/UI/Notes/NoteEditorView.swift`
- `ios/Data/Models/SchemaV1.swift`
- `ios/Core/Sync/Backup/ExportModels.swift`
- `ios/Core/Sync/Backup/BackupExporter.swift`
- `ios/Core/Sync/Backup/BackupImporter.swift`

## Follow-up Fixes (Post-implementation QA)
- Fixed RAG reliability for existing notes by adding auto catch-up indexing:
  - Chat now auto-indexes stale/missing embeddings before retrieval when needed.
  - Added background auto-index trigger on Chat/Settings appear when embedding model is loaded.
  - Added RAG status state for indexing progress (`RAG is preparing note index...`).
- Fixed Chat keyboard dismissal:
  - Added keyboard toolbar `Done` action.
  - Added tap-to-dismiss behavior and interactive scroll keyboard dismissal.
- Reduced chat “too white” appearance:
  - Replaced flat white surfaces with system grouped gradients and adaptive backgrounds.
- Removed manual indexing controls from Settings:
  - Deleted manual “Index All Notes” action from UI.
  - Kept automatic indexing status and indexed-count visibility.
- Made Settings visually cooler:
  - Added adaptive grouped gradient background and refreshed section styling.
- Fixed Files tab behavior for Drive:
  - Files screen now shows both Drive files and Local files.
  - Added Drive listing via `DriveSyncService` + `DriveAPIClient` (`listFilesInSynapsFolder` / `listFiles`).
  - Added formatted size/date metadata and refreshable loading state.
