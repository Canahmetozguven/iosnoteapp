# iOS Port Status Report

## Project State
- **Architecture**: Native iOS (SwiftUI + SwiftData)
- **AI Core**: llama.cpp (Remote Swift Package)
- **Build System**: GitHub Actions + EAS
- **Development Environment**: Native iOS

## Recent Updates (Phase 2 & 3 Complete)
- **Dependencies**: Fixed `llama.cpp` dependency by switching to the official GitHub repository in `project.yml`.
- **Chat Logic**: Implemented `GlobalViewModel` with streaming responses, `<think>` tag parsing, and busy state management.
- **Notes UI**: Created `NotesView` (List with swipe-to-delete) and `NoteEditorView` (Minimalist editor with auto-save).
- **RAG Integration**:
    - Implemented `VectorSearchService` (Cosine Similarity).
    - Wired `GlobalViewModel` to index notes and search them during chat.
    - Updated `SettingsView` with Indexing controls and progress UI.

## Current Focus
1.  **Verification**: Pull the changes to a Mac environment.
2.  **Build**: Run `xcodegen` and open `SynapsNotes-iOS.xcodeproj`.
3.  **Run**: Test on a physical device (iPhone 15 Pro recommended) for Metal acceleration.

## Pending / Next Steps
- **Model Import**: Verify `.gguf` file import via Finder/Files app works as expected.
- **Performance**: Test RAG latency on large note collections.
- **Unit Tests**: Expand `SynapsNotesTests` to cover `VectorSearchService`.
