# iOS Build Instructions (SynapsNotes)

## Canonical Build Identity
- Project: `ios/SynapsNotes-iOS.xcodeproj`
- Scheme: `SynapsNotes-iOS`
- Bundle ID: `com.synapsnotes.ios`

## Prerequisites
- Xcode 15+ with iOS 17 SDK
- Homebrew tools: `cmake`, `xcodegen`
- EAS CLI (`npm i -g eas-cli` or project-managed equivalent)
- Apple Developer account connected to EAS for signing/submission

## Local Build (Device/CI-style)
1. Build `llama.xcframework` and generate project:
   - `bash ios/eas-prebuild.sh`
2. Build app:
   - `xcodebuild -project ios/SynapsNotes-iOS.xcodeproj -scheme SynapsNotes-iOS -sdk iphoneos -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`

## Local Test (Simulator)
1. Generate project if needed:
   - `cd ios && xcodegen && cd ..`
2. Run tests:
   - `xcodebuild test -project ios/SynapsNotes-iOS.xcodeproj -scheme SynapsNotes-iOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15'`

## EAS Build Profiles
- Internal build:
  - `eas build --platform ios --profile development`
- Simulator preview build:
  - `eas build --platform ios --profile preview`
- TestFlight/App Store build:
  - `eas build --platform ios --profile production`

## EAS Submit
- Submit latest production build:
  - `eas submit --platform ios --profile production`

## GitHub Actions (No EAS Build Credits)
- CI build artifact (unsigned):
  - Workflow: `.github/workflows/ios-build.yml`
- Signed TestFlight upload (manual trigger):
  - Workflow: `.github/workflows/ios-testflight.yml`
  - Uses Fastlane lane: `fastlane/Fastfile` -> `ios github_testflight`
  - Fastlane version is pinned in `Gemfile` and executed via `bundle exec`.

### Required GitHub Secrets (for `ios-testflight.yml`)
- `ASC_KEY_ID`: App Store Connect API key ID
- `ASC_ISSUER_ID`: App Store Connect API issuer ID
- `ASC_KEY_CONTENT_BASE64`: Base64 of `AuthKey_<KEY_ID>.p8`
- `IOS_DIST_P12_BASE64`: Base64 of Apple Distribution `.p12`
- `IOS_DIST_P12_PASSWORD`: Password for the `.p12`
- `APPLE_TEAM_ID`: Apple Team ID (e.g. `VGA93M6T72`)

The workflow downloads the App Store provisioning profile directly from App Store Connect, so a `.mobileprovision` secret is not required.

### Base64 Helper Commands
- macOS/Linux:
  - `base64 -i AuthKey_<KEY_ID>.p8 | pbcopy`
  - `base64 -i dist.p12 | pbcopy`
- Windows PowerShell:
  - `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_<KEY_ID>.p8"))`
  - `[Convert]::ToBase64String([IO.File]::ReadAllBytes("dist.p12"))`

## CI Consistency Checklist
- `eas.json` uses `"scheme": "SynapsNotes-iOS"` for all iOS build profiles.
- `ios/project.yml` starts with `name: SynapsNotes-iOS`.
- `ios/project.yml` sets `PRODUCT_BUNDLE_IDENTIFIER: com.synapsnotes.ios`.
- GitHub workflow references:
  - `ios/SynapsNotes-iOS.xcodeproj`
  - `-scheme SynapsNotes-iOS`
  - artifact path `Release-iphoneos/SynapsNotes-iOS.app`

## Credential Expectations (EAS Managed)
- Default mode is EAS-managed credentials.
- First production build may prompt for:
  - Apple Team authentication
  - Distribution certificate/provisioning creation
  - App Store Connect app linkage
