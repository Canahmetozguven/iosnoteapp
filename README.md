# Synaps Notes (iOS)

Native iOS app (SwiftUI + SwiftData) with local LLM inference via `llama.cpp`.

## Build / Release
- CI build (unsigned): `.github/workflows/ios-build.yml`
- TestFlight upload (signed, manual trigger): `.github/workflows/ios-testflight.yml`
  - Builds an IPA via Fastlane (`fastlane/Fastfile`) then uploads to TestFlight.

## App Identity
- Bundle ID: `com.synapsnotes.ios`
- Xcode project is generated via `xcodegen` from `ios/project.yml`

## OCR Status
- Current behavior: Knowledge import OCR uses Apple Vision OCR only.
- Temporary deprecation: Local OCR/VL model inference for imports is disabled.
- Planned feature: Re-enable selectable local OCR/VL models after compatibility hardening.

## App Icon
Apple requires the 1024x1024 App Store icon to be **opaque** (no alpha channel).

To update the app icon from a PNG on Windows:
```powershell
cd C:\Users\canahmet\Documents\projects\ios_note_app
pwsh -NoProfile -File ios\scripts\update_appicon.ps1 -SourcePng "C:\path\to\logo.png" -CommitAndPush
```
