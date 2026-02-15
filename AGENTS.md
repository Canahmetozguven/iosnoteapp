# AGENTS.md - iOS Note App Port

## Overview
Native iOS port of the Android LLM Note App. Built with SwiftUI, SwiftData, and llama.cpp for local inference.

## Repo Map
- `ios/`: Core Swift source code and resources.
  - `App/`: Application entry and lifecycle.
  - `Core/`: Shared logic, AI integration, and utilities.
  - `Data/`: SwiftData models and repository implementations.
  - `Domain/`: Business logic and service interfaces.
  - `UI/`: SwiftUI views (Chat, Notes, Settings).
- `ios_kb/`: Android-to-iOS parity knowledge base and implementation checklists.
- `BUILD_INSTRUCTIONS.md`: Detailed setup for local/CI/EAS submit.
- `.github/workflows/`: CI/CD pipelines for automated builds.

## Where to Look
- **Entry Point**: `ios/App/LlmNotesApp.swift`
- **Porting Docs**: `ios_kb/`
- **CI Config**: `.github/workflows/ios-build.yml`
- **Local AI Logic**: `ios/Core/AI/`
- **Data Models**: `ios/Data/Models/SchemaV1.swift`
- **Main UI**: `ios/UI/ContentView.swift`
- **Vector Search**: `ios/Domain/Services/VectorSearchService.swift`

## Conventions
- **Architecture**: Clean Architecture with MVVM.
  - `Domain/`: Protocols and business logic.
  - `Data/`: SwiftData models and Repository implementations.
  - `UI/`: SwiftUI views and ViewModels.
- **Platform**: Targets iOS 17+ using Swift 5.10+.
- **Persistence**: SwiftData for local storage.
- **AI Core**: llama.cpp integrated via local Swift Package.
  - References Android repository tree for shared resources where applicable.
- **Tooling**: Bun-based workspace for automation.

## Anti-patterns
- **Large Files**: NEVER commit `.gguf` models. Use external file sharing.
- **State**: Avoid complex global state; prefer SwiftData for persistence.
- **Concurrency**: Use Swift Structured Concurrency (async/await) over Combine/Callbacks where possible.

## Critical Commands
- **Project Gen**: `xcodegen`
- **Build (CI)**: `xcodebuild -project ios/SynapsNotes-iOS.xcodeproj -scheme SynapsNotes-iOS -sdk iphonesimulator`
- **Build (Cloud Internal)**: `eas build --platform ios --profile development`
- **Build (Cloud TestFlight)**: `eas build --platform ios --profile production`
- **Submit (TestFlight/App Store Connect)**: `eas submit --platform ios --profile production`
- **Test**: `xcodebuild test -project ios/SynapsNotes-iOS.xcodeproj -scheme SynapsNotes-iOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15'`
