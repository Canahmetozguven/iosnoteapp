import Foundation
import Observation

enum NoteAIOutputStyle: CaseIterable, Identifiable {
    case concise
    case balanced
    case editorial

    var id: String { title }

    var title: String {
        switch self {
        case .concise:
            return "Concise"
        case .balanced:
            return "Balanced"
        case .editorial:
            return "Editorial"
        }
    }
}

enum NoteAIAction: CaseIterable, Identifiable {
    case autoComplete
    case summarize
    case rewrite
    case bulletPoints

    var id: String { title }

    var title: String {
        switch self {
        case .autoComplete:
            return "Auto-Complete"
        case .summarize:
            return "Summarize"
        case .rewrite:
            return "Rewrite"
        case .bulletPoints:
            return "Bullet Points"
        }
    }

    var icon: String {
        switch self {
        case .autoComplete:
            return "text.badge.plus"
        case .summarize:
            return "text.alignleft"
        case .rewrite:
            return "wand.and.stars"
        case .bulletPoints:
            return "list.bullet"
        }
    }

    var undoActionName: String {
        switch self {
        case .autoComplete:
            return "AI Auto-Complete"
        case .summarize:
            return "AI Summarize"
        case .rewrite:
            return "AI Rewrite"
        case .bulletPoints:
            return "AI Bullet Points"
        }
    }
}

@Observable
final class NoteEditorAIController {
    struct ApplyResult {
        let content: String
        let selectedRange: NSRange
        let action: NoteAIAction
    }

    struct RejectResult {
        let content: String
        let selectedRange: NSRange
    }

    private enum TargetMode {
        case selection
        case cursor
        case fullNote
    }

    private struct Snapshot {
        let baseText: String
        let originalSelection: NSRange
        let replacementRange: NSRange
        let mode: TargetMode
        let selectedText: String
        let beforeCursor: String
        let afterCursor: String
    }

    var activeAction: NoteAIAction?
    var outputStyle: NoteAIOutputStyle = .balanced
    var isGenerating = false
    var previewText = ""
    var errorMessage: String?
    var scopeDescription: String?

    private var snapshot: Snapshot?
    private var generationTask: Task<Void, Never>?

    var hasPendingPreview: Bool {
        activeAction != nil
    }

    var canResume: Bool {
        hasPendingPreview && !isGenerating
    }

    var canAcceptPreview: Bool {
        !previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func start(
        action: NoteAIAction,
        noteText: String,
        selectedRange: NSRange,
        isModelLoaded: Bool,
        isAppGenerating: Bool,
        llamaContext: LlamaContext
    ) -> Bool {
        guard !hasPendingPreview else {
            errorMessage = "Accept or discard the current draft first."
            return false
        }

        guard isModelLoaded else {
            errorMessage = "Load a chat model from Settings to use AI actions."
            return false
        }

        guard !isAppGenerating else {
            errorMessage = "Another generation is already running."
            return false
        }

        let safeSelection = clampedRange(selectedRange, in: noteText)
        let nsText = noteText as NSString
        let hasSelection = safeSelection.length > 0

        if action != .autoComplete,
           !hasSelection,
           noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "There is no text to process."
            return false
        }

        let mode: TargetMode
        let replacementRange: NSRange
        if hasSelection {
            mode = .selection
            replacementRange = safeSelection
        } else if action == .autoComplete {
            mode = .cursor
            replacementRange = NSRange(location: safeSelection.location, length: 0)
        } else {
            mode = .fullNote
            replacementRange = NSRange(location: 0, length: nsText.length)
        }

        let selectedText = hasSelection ? nsText.substring(with: safeSelection) : ""
        let beforeCursor = nsText.substring(to: safeSelection.location)
        let afterCursor = nsText.substring(from: safeSelection.location)

        snapshot = Snapshot(
            baseText: noteText,
            originalSelection: safeSelection,
            replacementRange: replacementRange,
            mode: mode,
            selectedText: selectedText,
            beforeCursor: beforeCursor,
            afterCursor: afterCursor
        )

        activeAction = action
        previewText = ""
        errorMessage = nil
        scopeDescription = "\(scopeText(for: mode)) • Style: \(outputStyle.title)"

        guard let currentSnapshot = snapshot else {
            errorMessage = "Could not prepare action context."
            return false
        }

        let prompt = buildPrompt(action: action, snapshot: currentSnapshot, style: outputStyle)
        runGeneration(prompt: prompt, appendToExistingPreview: false, llamaContext: llamaContext)
        return true
    }

    @discardableResult
    func resume(llamaContext: LlamaContext, isAppGenerating: Bool) -> Bool {
        guard canResume else { return false }
        guard !isAppGenerating else {
            errorMessage = "Another generation is already running."
            return false
        }
        guard let action = activeAction, let snapshot else {
            errorMessage = "No preview session to resume."
            return false
        }

        let currentDraft = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentDraft.isEmpty else {
            errorMessage = "Nothing to resume yet."
            return false
        }

        errorMessage = nil
        let prompt = buildResumePrompt(
            action: action,
            snapshot: snapshot,
            style: outputStyle,
            partialDraft: currentDraft
        )
        runGeneration(prompt: prompt, appendToExistingPreview: true, llamaContext: llamaContext)
        return true
    }

    func stop(llamaContext: LlamaContext) {
        guard isGenerating else { return }
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        Task {
            await llamaContext.stopCompletion()
        }
    }

    func accept() -> ApplyResult? {
        guard let action = activeAction, let snapshot else { return nil }
        guard canAcceptPreview else { return nil }

        let replacement = replacementText(for: action, snapshot: snapshot, preview: previewText)
        let content = (snapshot.baseText as NSString).replacingCharacters(in: snapshot.replacementRange, with: replacement)
        let location = snapshot.replacementRange.location + (replacement as NSString).length
        let selectedRange = clampedRange(NSRange(location: location, length: 0), in: content)

        let result = ApplyResult(content: content, selectedRange: selectedRange, action: action)
        clearState()
        return result
    }

    func reject() -> RejectResult? {
        guard let snapshot else {
            clearState()
            return nil
        }

        let result = RejectResult(
            content: snapshot.baseText,
            selectedRange: snapshot.originalSelection
        )
        clearState()
        return result
    }

    func previewNoteContent(fallbackCurrentText: String) -> String {
        guard let action = activeAction, let snapshot else { return fallbackCurrentText }
        let replacement = replacementText(for: action, snapshot: snapshot, preview: previewText)
        return (snapshot.baseText as NSString).replacingCharacters(in: snapshot.replacementRange, with: replacement)
    }

    func previewSelectionRange(fallback: NSRange) -> NSRange {
        guard let action = activeAction, let snapshot else { return fallback }
        let replacement = replacementText(for: action, snapshot: snapshot, preview: previewText)
        let previewContent = previewNoteContent(fallbackCurrentText: snapshot.baseText)
        let location = snapshot.replacementRange.location + (replacement as NSString).length
        return clampedRange(NSRange(location: location, length: 0), in: previewContent)
    }

    private func clearState() {
        generationTask?.cancel()
        generationTask = nil
        activeAction = nil
        isGenerating = false
        previewText = ""
        errorMessage = nil
        scopeDescription = nil
        snapshot = nil
    }

    private func runGeneration(prompt: String, appendToExistingPreview: Bool, llamaContext: LlamaContext) {
        generationTask?.cancel()
        isGenerating = true
        if !appendToExistingPreview {
            previewText = ""
        }
        let basePreview = appendToExistingPreview ? previewText : ""

        generationTask = Task { @MainActor in
            defer {
                isGenerating = false
                generationTask = nil
            }

            let messages = [
                [
                    "role": "system",
                    "content": "You are an in-note writing assistant. Return plain text only with no markdown code fences."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ]

            let templatedPrompt = await llamaContext.applyTemplate(messages: messages)

            do {
                let stream = await llamaContext.completion(prompt: templatedPrompt)
                var rawOutput = ""
                for try await token in stream {
                    if Task.isCancelled { break }
                    rawOutput += token
                    let visible = visibleContent(from: rawOutput)
                    previewText = appendToExistingPreview ? (basePreview + visible) : visible
                }
            } catch {
                errorMessage = "Generation failed: \(error.localizedDescription)"
            }
        }
    }

    private func buildPrompt(action: NoteAIAction, snapshot: Snapshot, style: NoteAIOutputStyle) -> String {
        let styleRule = styleInstruction(for: action, style: style)

        switch action {
        case .autoComplete:
            if snapshot.mode == .selection {
                return """
                Task: Continue the selected passage naturally.
                Rules:
                - Keep the same language, style, and tone.
                - Return only the continuation text to append.
                - Do not add explanations.
                - \(styleRule)

                SELECTED_TEXT:
                \(snapshot.selectedText)
                """
            }

            return """
            Task: Continue this note from the cursor position.
            Rules:
            - Keep the same language, style, and tone.
            - Return only the text to insert at the cursor.
            - Do not add explanations.
            - \(styleRule)

            BEFORE_CURSOR:
            \(snapshot.beforeCursor)

            AFTER_CURSOR:
            \(snapshot.afterCursor)
            """

        case .summarize:
            return """
            Task: Summarize the provided text.
            Rules:
            - Keep it concise and preserve key details.
            - Return only the summary text.
            - Do not add explanations.
            - \(styleRule)

            INPUT_TEXT:
            \(inputText(for: snapshot))
            """

        case .rewrite:
            return """
            Task: Rewrite the provided text.
            Rules:
            - Improve clarity, flow, grammar, and tone.
            - Keep original meaning and factual details.
            - Return only the rewritten text.
            - Do not add explanations.
            - \(styleRule)

            INPUT_TEXT:
            \(inputText(for: snapshot))
            """

        case .bulletPoints:
            return """
            Task: Convert the provided text into clear, actionable bullet points.
            Rules:
            - Use lines that start with "- ".
            - Keep core facts and intent.
            - Return only the bullet list text.
            - Do not add explanations.
            - \(styleRule)

            INPUT_TEXT:
            \(inputText(for: snapshot))
            """
        }
    }

    private func buildResumePrompt(
        action: NoteAIAction,
        snapshot: Snapshot,
        style: NoteAIOutputStyle,
        partialDraft: String
    ) -> String {
        let originalTask = buildPrompt(action: action, snapshot: snapshot, style: style)
        return """
        Task: Continue the in-note draft below for the same editing request.
        Rules:
        - Return only additional continuation text.
        - Do not repeat content already in CURRENT_DRAFT.
        - Keep language, style, and tone consistent.
        - Do not add explanations.

        ORIGINAL_REQUEST:
        \(originalTask)

        CURRENT_DRAFT:
        \(partialDraft)
        """
    }

    private func replacementText(for action: NoteAIAction, snapshot: Snapshot, preview: String) -> String {
        if action == .autoComplete, snapshot.mode == .selection {
            return snapshot.selectedText + preview
        }
        return preview
    }

    private func inputText(for snapshot: Snapshot) -> String {
        switch snapshot.mode {
        case .selection:
            return snapshot.selectedText
        case .cursor, .fullNote:
            return snapshot.baseText
        }
    }

    private func scopeText(for mode: TargetMode) -> String {
        switch mode {
        case .selection:
            return "Scope: selected text"
        case .cursor:
            return "Scope: insert at cursor"
        case .fullNote:
            return "Scope: full note"
        }
    }

    private func styleInstruction(for action: NoteAIAction, style: NoteAIOutputStyle) -> String {
        switch (action, style) {
        case (_, .concise):
            return "Use compact phrasing and avoid extra detail."
        case (.summarize, .balanced):
            return "Balance brevity with key detail coverage."
        case (.rewrite, .balanced):
            return "Use natural, clear wording with moderate detail."
        case (.bulletPoints, .balanced):
            return "Use actionable bullets with one idea per line."
        case (.autoComplete, .balanced):
            return "Continue naturally without changing the existing voice."
        case (.summarize, .editorial):
            return "Preserve key points with stronger narrative flow and polished phrasing."
        case (.rewrite, .editorial):
            return "Prioritize readability, rhythm, and polished voice while keeping meaning."
        case (.bulletPoints, .editorial):
            return "Write sharp, polished bullets with strong verbs."
        case (.autoComplete, .editorial):
            return "Continue with expressive, polished prose while staying coherent."
        }
    }

    private func visibleContent(from text: String) -> String {
        let pattern = #"<think>([\s\S]*?)</think>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return sanitizeOutput(text)
        }

        var cleaned = text
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches.reversed() {
            if let fullRange = Range(match.range, in: cleaned) {
                cleaned.removeSubrange(fullRange)
            }
        }
        return sanitizeOutput(cleaned)
    }

    private func sanitizeOutput(_ content: String) -> String {
        let controlTokens = [
            "<|im_start|>", "<|im_end|>", "<|endoftext|>", "</s>",
            "<|assistant|>", "<|user|>", "<|system|>"
        ]

        var cleaned = content
        for token in controlTokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clampedRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        let safeLength = min(max(0, range.length), length - location)
        return NSRange(location: location, length: safeLength)
    }
}
