# Synaps Notes (iOS) - Tech Stack

## Programming Language
- **Swift (5.10):** Modern and safe language for native iOS development.

## Platform
- **iOS 17.0+:** Targeting the latest features and security improvements.

## Core Frameworks
- **SwiftUI:** Declarative UI framework for a modern and responsive user experience.
- **SwiftData:** Powerful and easy-to-use persistence framework for app data.

## AI & Engine
- **llama.cpp:** High-performance, local LLM inference engine.
- **Custom Build Integration:** Automated `llama.xcframework` generation via custom build scripts.

## External Libraries (Swift Package Manager)
- **GoogleSignIn:** Secure user authentication and integration with Google services.
- **ZIPFoundation:** Robust library for file compression and decompression.

## Infrastructure & Tooling
- **XcodeGen:** Automated Xcode project generation from a declarative `project.yml` file.
- **Fastlane:** Streamlined build and release automation for iOS applications.
- **Ruby (3.2):** Used for managing Fastlane and other automation scripts.

## CI/CD Pipeline
- **GitHub Actions:** Primary platform for automated testing, building, and deployment.
- **Workflows:** Multi-stage workflows for preflight checks, build validation, and TestFlight uploads.
- **GitHub Virtual Machines:** Utilizing `macos-15` and `ubuntu-latest` runners for consistent build environments.
- **GitHub Secrets:** Secure management of sensitive credentials and API keys.

## Deployment
- **App Store Connect / TestFlight:** Automated delivery of builds to testers and the App Store via Fastlane.
