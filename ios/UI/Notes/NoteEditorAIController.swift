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

    enum DiffLineKind {
        case context
        case removed
        case added
        case meta
    }

    struct PreviewDiffLine {
        let kind: DiffLineKind
        let text: String
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
    var previewThought = ""
    var errorMessage: String?
    var scopeDescription: String?

    private var snapshot: Snapshot?
    private var generationTask: Task<Void, Never>?

    var hasPendingPreview: Bool {
        activeAction != nil
    }

    var canAcceptPreview: Bool {
        !previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func previewDiffLines(hideUnchanged: Bool) -> [PreviewDiffLine] {
        guard activeAction != nil else { return [] }
        let before = previewTargetBeforeText()
        let after = previewTargetAfterText()
        let lines = makeDiffLines(before: before, after: after)
        guard hideUnchanged else { return lines }

        let filtered = lines.filter { $0.kind != .context }
        if filtered.isEmpty, !lines.isEmpty {
            return [PreviewDiffLine(kind: .meta, text: "No changed lines in preview.")]
        }
        return filtered
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
            errorMessage = "Accept or reject the current preview first."
            return false
        }

        guard isModelLoaded else {
            errorMessage = "Load a chat model from Settings to use in-note AI actions."
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
        isGenerating = true
        previewText = ""
        previewThought = ""
        errorMessage = nil
        scopeDescription = "\(scopeText(for: mode)) • Style: \(outputStyle.title)"

        guard let currentSnapshot = snapshot else {
            errorMessage = "Could not prepare action context."
            return false
        }
        let prompt = buildPrompt(action: action, snapshot: currentSnapshot, style: outputStyle)
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
                    let parsed = parseThinkTags(rawOutput)
                    previewText = parsed.content
                    previewThought = parsed.thought ?? ""
                }
            } catch {
                errorMessage = "Generation failed: \(error.localizedDescription)"
            }
        }

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
        let resultContent = (snapshot.baseText as NSString).replacingCharacters(in: snapshot.replacementRange, with: replacement)
        let cursorLocation = snapshot.replacementRange.location + (replacement as NSString).length
        let result = ApplyResult(
            content: resultContent,
            selectedRange: NSRange(location: cursorLocation, length: 0),
            action: action
        )

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

    private func clearState() {
        generationTask?.cancel()
        generationTask = nil
        activeAction = nil
        isGenerating = false
        previewText = ""
        previewThought = ""
        errorMessage = nil
        scopeDescription = nil
        snapshot = nil
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

    private func replacementText(for action: NoteAIAction, snapshot: Snapshot, preview: String) -> String {
        if action == .autoComplete, snapshot.mode == .selection {
            return snapshot.selectedText + preview
        }
        return preview
    }

    private func previewTargetBeforeText() -> String {
        guard let snapshot else { return "" }
        switch snapshot.mode {
        case .selection:
            return snapshot.selectedText
        case .cursor:
            return ""
        case .fullNote:
            return snapshot.baseText
        }
    }

    private func previewTargetAfterText() -> String {
        guard let action = activeAction, let snapshot else { return "" }
        return replacementText(for: action, snapshot: snapshot, preview: previewText)
    }

    private func makeDiffLines(before: String, after: String) -> [PreviewDiffLine] {
        let beforeLines = splitLines(before)
        let afterLines = splitLines(after)

        if beforeLines == afterLines {
            if beforeLines.isEmpty { return [] }
            return beforeLines.map { PreviewDiffLine(kind: .context, text: $0) }
        }

        if beforeLines.isEmpty {
            return afterLines.map { PreviewDiffLine(kind: .added, text: $0) }
        }

        if afterLines.isEmpty {
            return beforeLines.map { PreviewDiffLine(kind: .removed, text: $0) }
        }

        var prefixCount = 0
        let maxPrefix = min(beforeLines.count, afterLines.count)
        while prefixCount < maxPrefix, beforeLines[prefixCount] == afterLines[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        let maxSuffix = min(beforeLines.count - prefixCount, afterLines.count - prefixCount)
        while suffixCount < maxSuffix,
              beforeLines[beforeLines.count - 1 - suffixCount] == afterLines[afterLines.count - 1 - suffixCount] {
            suffixCount += 1
        }

        let prefixLines = Array(beforeLines.prefix(prefixCount))
        let suffixLines = suffixCount > 0 ? Array(beforeLines.suffix(suffixCount)) : []
        let beforeMiddle = Array(beforeLines[prefixCount..<(beforeLines.count - suffixCount)])
        let afterMiddle = Array(afterLines[prefixCount..<(afterLines.count - suffixCount)])

        var lines: [PreviewDiffLine] = []
        appendContext(lines: prefixLines, to: &lines, keepTail: true)
        lines.append(contentsOf: beforeMiddle.map { PreviewDiffLine(kind: .removed, text: $0) })
        lines.append(contentsOf: afterMiddle.map { PreviewDiffLine(kind: .added, text: $0) })
        appendContext(lines: suffixLines, to: &lines, keepTail: false)
        return lines
    }

    private func appendContext(lines: [String], to output: inout [PreviewDiffLine], keepTail: Bool) {
        let contextLimit = 4
        guard !lines.isEmpty else { return }

        if lines.count <= contextLimit {
            output.append(contentsOf: lines.map { PreviewDiffLine(kind: .context, text: $0) })
            return
        }

        let hiddenCount = lines.count - contextLimit
        if keepTail {
            output.append(PreviewDiffLine(kind: .meta, text: "... \(hiddenCount) unchanged line(s) ..."))
            output.append(contentsOf: lines.suffix(contextLimit).map { PreviewDiffLine(kind: .context, text: $0) })
        } else {
            output.append(contentsOf: lines.prefix(contextLimit).map { PreviewDiffLine(kind: .context, text: $0) })
            output.append(PreviewDiffLine(kind: .meta, text: "... \(hiddenCount) unchanged line(s) ..."))
        }
    }

    private func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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

    private func inputText(for snapshot: Snapshot) -> String {
        switch snapshot.mode {
        case .selection:
            return snapshot.selectedText
        case .cursor, .fullNote:
            return snapshot.baseText
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

    private func clampedRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        let safeLength = min(max(0, range.length), length - location)
        return NSRange(location: location, length: safeLength)
    }

    private func parseThinkTags(_ text: String) -> (content: String, thought: String?) {
        let pattern = #"<think>([\s\S]*?)</think>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (sanitizeOutput(text), nil)
        }

        let range = NSRange(text.startIndex..., in: text)
        var thoughts: [String] = []
        var cleaned = text
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches.reversed() {
            if let thoughtRange = Range(match.range(at: 1), in: text) {
                thoughts.insert(String(text[thoughtRange]), at: 0)
            }
            if let fullRange = Range(match.range, in: cleaned) {
                cleaned.removeSubrange(fullRange)
            }
        }

        let thought = thoughts.isEmpty ? nil : thoughts.joined(separator: "\n")
        return (sanitizeOutput(cleaned), thought)
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
}
