# iOS Knowledge Base (From Android Codebase)

**Generated:** 2026-02-13  
**Source:** `android_note_app` Android implementation  
**Goal:** Build iOS app with behavior parity to current Android app.

## Overview
This knowledge base captures the real architecture and behavior of the Android app so the iOS implementation can match it with minimal drift.

The Android app is:
- MVVM + Clean Architecture (`feature` / `domain` / `core`)
- On-device LLM via `llama.cpp` native bridge
- Local notes + chat persistence
- RAG-capable chat with model-aware bypass
- Runtime backend selection with crash-safe fallback

## Directory
- `docs/ios_kb/ANDROID_TO_IOS_ARCHITECTURE_MAP.md`
- `docs/ios_kb/IOS_NATIVE_ENGINE_PORT_GUIDE.md`
- `docs/ios_kb/IOS_FEATURE_PARITY_CHECKLIST.md`
- `docs/ios_kb/IOS_VISUAL_PARITY_GUIDELINES.md`

## Key Android Reference Paths
- App entry/navigation: `app/src/main/java/com/synapsenotes/ai/MainActivity.kt`
- Main lifecycle model restore: `app/src/main/java/com/synapsenotes/ai/MainViewModel.kt`
- Core AI engine: `app/src/main/java/com/synapsenotes/ai/core/ai/LlmEngine.kt`
- Native bridge interface: `app/src/main/java/com/synapsenotes/ai/core/ai/LlamaContext.kt`
- Native JNI implementation: `app/src/main/cpp/native-lib.cpp`
- Hardware policy: `app/src/main/java/com/synapsenotes/ai/core/ai/DefaultHardwareCapabilityProvider.kt`
- Data schema: `app/src/main/java/com/synapsenotes/ai/core/database/`
- Repositories: `app/src/main/java/com/synapsenotes/ai/core/data/repository/`
- Chat flow: `app/src/main/java/com/synapsenotes/ai/feature/chat/ChatViewModel.kt`
- Notes AI actions: `app/src/main/java/com/synapsenotes/ai/feature/notes/NoteDetailViewModel.kt`

## Porting Principle
Port behavior first, then optimize platform-specific UX.  
Critical rule: keep inference, embedding, and persistence semantics identical unless explicitly changed.
