# iOS Feature Parity Checklist

## Purpose
Execution checklist to rebuild the same app behavior on iOS from this Android codebase.

## Phase 1: Foundation
- [ ] Define iOS module folders: `Features`, `Domain`, `Data`, `Core`, `Native`.
- [ ] Wire app-wide dependency container (singleton engine/database/preferences).
- [ ] Apply `docs/ios_kb/IOS_VISUAL_PARITY_GUIDELINES.md` before building screens.
- [ ] Build navigation shell with routes matching Android:
  - [ ] Onboarding
  - [ ] Notes list
  - [ ] Note detail
  - [ ] Chat
  - [ ] Files
  - [ ] Settings
  - [ ] About/Privacy

## Phase 2: Data and Domain
- [ ] Implement note storage model with fields:
  - `id`, `title`, `content`, `createdAt`, `updatedAt`, `tags`, `embedding`
- [ ] Implement chat session storage model.
- [ ] Implement chat message storage model with:
  - `sourceNoteIds`
  - `thoughtProcess`
- [ ] Implement repositories equivalent to:
  - `NoteRepository`
  - `ChatRepository`
  - `DriveRepository` (or iCloud/Google Drive equivalent)
- [ ] Implement use cases:
  - `GetNotes`
  - `SaveNote`
  - `DeleteNote`
  - `VectorSearch`

## Phase 3: Native AI Engine
- [ ] Add `llama.cpp` integration in iOS build.
- [ ] Implement Swift bridge surface equivalent to Android `LlmContext`.
- [ ] Implement `LlmEngine` with:
  - [ ] load timeout
  - [ ] backend fallback
  - [ ] single-call concurrency guard
  - [ ] token streaming interface
  - [ ] stop-generation support
- [ ] Implement output sanitizer parity with Android `OutputSanitizer.kt`.
- [ ] Implement prompt builder parity (`PromptBuilder.kt`).

## Phase 4: Feature Parity
- [ ] Notes list:
  - [ ] list notes ordered by `updatedAt desc`
  - [ ] create/delete/open note
- [ ] Note detail:
  - [ ] save/update
  - [ ] AI actions: autocomplete, summarize, rewrite, bullet points
  - [ ] preview accept/reject
  - [ ] undo last AI change
  - [ ] stop/resume generation
- [ ] Chat:
  - [ ] create sessions
  - [ ] load session history
  - [ ] RAG logic with model-aware bypass (`requiresRag`)
  - [ ] selected-note context injection
  - [ ] stream message tokens
  - [ ] persist thought process separately
- [ ] Files:
  - [ ] cloud list
  - [ ] import file as note
- [ ] Settings:
  - [ ] model list/download/load/unload
  - [ ] active model persistence
  - [ ] sync trigger/status
  - [ ] privacy/about

## Phase 5: Lifecycle and Stability
- [ ] Persist active model filenames and IDs.
- [ ] Restore models on foreground.
- [ ] Release engine on background.
- [ ] Implement safe-mode boot guard for crash loop protection.
- [ ] Persist backend failure history and attempting-backend markers.

## Phase 6: Validation
- [ ] Validate vector search returns top-K cosine similarity matches.
- [ ] Validate chat with/without RAG-required models.
- [ ] Validate streaming cancellation and resume behavior.
- [ ] Validate persistence of notes/sessions/messages after restart.
- [ ] Validate background/foreground model restore sequence.
- [ ] Validate visual parity against Android (colors, typography, spacing, component behavior).

## Android References for Verification
- `app/src/main/java/com/synapsenotes/ai/feature/chat/ChatViewModel.kt`
- `app/src/main/java/com/synapsenotes/ai/feature/notes/NoteDetailViewModel.kt`
- `app/src/main/java/com/synapsenotes/ai/core/ai/LlmEngine.kt`
- `app/src/main/java/com/synapsenotes/ai/core/ai/DefaultHardwareCapabilityProvider.kt`
- `app/src/main/java/com/synapsenotes/ai/core/database/`
- `app/src/main/java/com/synapsenotes/ai/core/data/repository/`
