# iOS Build Instructions (SynapsNotes)

## Canonical Build Identity
- Project: `ios/SynapsNotes-iOS.xcodeproj`
- Scheme: `SynapsNotes-iOS`
- Bundle ID: `com.synapsnotes.ios`

## Prerequisites
- Xcode 16+ (App Store Connect upload requires iOS 18+ SDK)
- Homebrew tools: `cmake`, `xcodegen`
- Ruby/Bundler for Fastlane (CI uses `ruby/setup-ruby` with `bundler-cache: true`)

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

## GitHub Actions (No EAS Build Credits)
- CI build artifact (unsigned):
  - Workflow: `.github/workflows/ios-build.yml`
- Signed TestFlight upload (manual trigger):
  - Workflow: `.github/workflows/ios-testflight.yml`
  - Uses Fastlane lanes: `fastlane/Fastfile` -> `ios github_build` then `ios github_upload`
  - The workflow also unzips the built IPA and asserts `Assets.car` exists before upload.
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

## App Icon Notes (Upload Validation)
App Store Connect rejects App Store icons with transparency. The generated AppIcon set is produced as **opaque RGB** (no alpha channel).

To update the icon from a PNG on Windows:
- `pwsh -NoProfile -File ios/scripts/update_appicon.ps1 -SourcePng C:\\path\\to\\logo.png -CommitAndPush`

## CI Consistency Checklist
- `ios/project.yml` starts with `name: SynapsNotes-iOS`.
- `ios/project.yml` sets `PRODUCT_BUNDLE_IDENTIFIER: com.synapsnotes.ios`.
- GitHub workflow references:
  - `ios/SynapsNotes-iOS.xcodeproj`
  - `-scheme SynapsNotes-iOS`
  - artifact path `Release-iphoneos/SynapsNotes-iOS.app`

## (Optional) EAS
This repo includes `eas.json` for reference, but the current release pipeline uses **GitHub Actions + Fastlane**.
