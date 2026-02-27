# Implementation Plan - App Store Readiness (20260227)

This plan outlines the steps to prepare Synaps Notes for App Store submission.

## Phase 1: Research & Audit
Goal: Identify compliance gaps and verify asset readiness.

- [ ] Task: Audit App Store Icon and Assets
    - [ ] Verify `Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png` is opaque (no alpha).
    - [ ] Check `LaunchScreen.storyboard` for correct layout and branding.
    - [ ] Verify all required icon sizes are present and correctly linked in `project.yml`.
- [ ] Task: Audit `Info.plist` Privacy Strings
    - [ ] Review all `NS...UsageDescription` strings in `Resources/Info.plist`.
    - [ ] Ensure descriptions are clear, professional, and explain *why* the permission is needed.
- [ ] Task: Compliance Audit for Local AI
    - [ ] Verify `llama.cpp` integration follows Apple's guidelines for local execution (sandbox, performance).
    - [ ] Check if any "encryption" declarations are needed (documented in `app.json` as `ITSAppUsesNonExemptEncryption: false`).
- [ ] Task: Conductor - User Manual Verification 'Research & Audit' (Protocol in workflow.md)

## Phase 2: Metadata Generation
Goal: Prepare the text and instructions for the App Store Connect listing.

- [ ] Task: Draft App Store Listing Metadata
    - [ ] Write a compelling App Store Description.
    - [ ] Research and select relevant Keywords.
    - [ ] Draft the "What's New" text for the initial release (v1.0.0).
- [ ] Task: Create Reviewer Guide (`REVIEWER_GUIDE.md`)
    - [ ] Document the "App Review Information" requirements.
    - [ ] Provide step-by-step instructions for reviewers to test core features (Chat, RAG, OCR).
    - [ ] Include test account details for Google Sign-In if applicable.
- [ ] Task: Conductor - User Manual Verification 'Metadata Generation' (Protocol in workflow.md)

## Phase 3: Technical Refinement
Goal: Apply necessary changes to the codebase and verify the build.

- [ ] Task: Refine `Info.plist` and `project.yml`
    - [ ] Update any identified gaps in privacy strings or project configuration.
    - [ ] Ensure `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are correctly set for submission.
- [ ] Task: Verify Build and IPA Generation
    - [ ] Run `fastlane ios github_build` locally or via a mock CI trigger to ensure IPA generation success.
    - [ ] Inspect the generated IPA for icon and launch screen presence.
- [ ] Task: Conductor - User Manual Verification 'Technical Refinement' (Protocol in workflow.md)
