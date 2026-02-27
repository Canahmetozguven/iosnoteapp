# App Store Reviewer Guide - Synaps Notes (v1.0.0)

This document provides necessary information and instructions for Apple's app review team to test the functionality of Synaps Notes.

## App Review Information

- **Contact Information:** (User Name), (Email), (Phone)
- **Demo Account:** (If required for Google Sign-In)
- **Notes for Reviewers:** This app performs local AI inference on the device using `llama.cpp`. No data is sent to external servers for chat or OCR processing.

## Testing Instructions

### 1. Local AI Chat
1. Launch the app and navigate to the **Chat** tab.
2. Type a message (e.g., "Hello, what can you do?") and press send.
3. Observe the AI generating a response locally on the device.

### 2. Knowledge Base Ingestion & OCR
1. Navigate to the **Knowledge Base** tab.
2. Tap the **+** button to import a document or image.
3. Select **Import from Photos** and choose an image containing text.
4. After selection, the app will process the image using Apple Vision OCR.
5. Confirm the text appears in your knowledge base.

### 3. RAG Pipeline (Contextual Chat)
1. Ensure at least one document or image is in the knowledge base.
2. Navigate to the **Chat** tab and ask a question based on the imported content (e.g., "Summarize the text from the image I just imported").
3. Observe the AI using the retrieved context from the knowledge base in its response.

### 4. Cloud Sync & Backup (Google Drive)
1. Navigate to the **Settings** tab.
2. Tap **Sign in with Google** and complete the authentication.
3. Enable **Google Drive Sync**.
4. Tap **Backup Now** to manually trigger a backup of your knowledge base to Google Drive.
5. Verify the backup is created in your Google Drive's App Data folder.

## Technical Details
- **Engine:** `llama.cpp` (Metal-accelerated on iOS).
- **OCR:** Apple Vision Framework.
- **Persistence:** SwiftData.
- **Authentication:** Google Sign-In (Official SDK).
- **Sync:** Google Drive API.
