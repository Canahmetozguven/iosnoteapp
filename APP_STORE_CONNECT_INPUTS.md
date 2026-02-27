# App Store Connect Inputs (Copy/Paste)

Last updated: 2026-02-27

## 1. App Information

- Name: `Synaps Notes`
- Subtitle (<=30 chars): `Private AI notes, on-device`
- Primary Category: `Productivity`
- Secondary Category: `Utilities`
- Privacy Policy URL: `https://github.com/canahmet/ios_note_app/blob/main/PRIVACY_POLICY.md`
- Support URL: `https://github.com/canahmet/ios_note_app/blob/main/SUPPORT.md`
- Marketing URL: `https://github.com/canahmet/ios_note_app`
- Keywords (<=100 bytes): `notes,ai,offline,private,llm,ocr,knowledge,rag`

## 2. Description

```text
Synaps Notes is a private, on-device note app with local AI features.

- Write and organize notes locally on your iPhone.
- Use local model chat with your own notes and knowledge files.
- Import PDFs, images, and text files with OCR support.
- Keep data on-device by default, with optional Google Drive backup/sync.

No account is required to use core features.
```

## 3. App Review Notes

```text
Core app usage is fully local and works without login.
Google Sign-In is optional and only used for user-initiated Drive backup/sync/restore.
No ads or tracking SDKs are used.
```

## 4. App Privacy (Nutrition Label) Baseline

- Tracking: `No`
- Data types to disclose (recommended baseline):
  - `Email Address` (optional Google Sign-In) -> Purpose: `App Functionality`, Linked: `Yes`
  - `User Content` (notes/files/backups when Drive sync/import/export is used) -> Purpose: `App Functionality`, Linked: `Yes`
- Diagnostics: `No` (if not collected)
- Advertising Data: `No`

## 5. Export Compliance

- App config (`Info.plist`) already sets:
  - `ITSAppUsesNonExemptEncryption = false`
- In App Store Connect encryption questions: choose the path indicating no non-exempt encryption documentation is required.

## 6. Age Rating

- Complete the updated age-rating questionnaire in App Store Connect.
- Recommended baseline for this build: `17+` (conservative for open-ended AI/chat output).

## 7. Ready-to-Use Answers (ASC Wizard)

- Export Compliance:
  - "Does your app use encryption?" -> `Yes`
  - "Is your app exempt (standard encryption only)?" -> `Yes`
  - "Does your app use proprietary/non-standard encryption?" -> `No`
- IDFA / Tracking:
  - "Do you track users?" -> `No`
  - "Do you use IDFA?" -> `No`

## 8. Reference Links

- Upcoming requirements (Xcode 26 + iOS 26 SDK from April 28, 2026):  
  https://developer.apple.com/news/upcoming-requirements/
- App privacy details:  
  https://developer.apple.com/app-store/app-privacy-details/
- App information reference:  
  https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- App privacy reference:  
  https://developer.apple.com/help/app-store-connect/reference/app-privacy
- Export compliance:  
  https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation
- Age ratings:  
  https://developer.apple.com/help/app-store-connect/reference/age-ratings
