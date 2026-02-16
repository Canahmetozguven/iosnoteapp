import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Environment(GlobalViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var note: Note

    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var aiController = NoteEditorAIController()

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 12) {
                titleCard
                toolsCard

                if aiController.hasPendingPreview {
                    inlinePreviewBar
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                }

                editorCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: note.title) {
            note.updatedAt = Date()
            vm.handleNoteEdited(note, modelContext: modelContext)
        }
        .onChange(of: note.content) {
            note.updatedAt = Date()
            vm.handleNoteEdited(note, modelContext: modelContext)
            editorSelection = clampedSelection(editorSelection, in: note.content)
        }
        .onDisappear {
            if aiController.isGenerating {
                aiController.stop(llamaContext: vm.llamaContext)
            }
        }
        .animation(.snappy(duration: 0.24), value: aiController.hasPendingPreview)
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color(.systemGroupedBackground),
                Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $note.title, axis: .vertical)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .disabled(aiController.hasPendingPreview)

            HStack(spacing: 8) {
                Text(noteMetricsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if aiController.hasPendingPreview {
                    Label("Previewing", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(14)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardStroke, lineWidth: 0.8)
        )
    }

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Writing Tools", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(vm.isChatModelLoaded ? "Model Ready" : "Model Not Loaded")
                    .font(.caption2)
                    .foregroundStyle(vm.isChatModelLoaded ? .green : .secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NoteAIAction.allCases) { action in
                        Button {
                            startAction(action)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: action.icon)
                                    .font(.caption.weight(.semibold))
                                Text(action.title)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(buttonFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(aiController.hasPendingPreview)
                    }
                }
                .padding(.vertical, 1)
            }

            HStack(spacing: 8) {
                ForEach(NoteAIOutputStyle.allCases) { style in
                    styleButton(style)
                }
            }
            .disabled(aiController.hasPendingPreview)

            Text(scopeHintText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardStroke, lineWidth: 0.8)
        )
    }

    private func styleButton(_ style: NoteAIOutputStyle) -> some View {
        let isSelected = aiController.outputStyle == style
        return Button {
            aiController.outputStyle = style
        } label: {
            Text(style.title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.accentColor : buttonFill)
                )
        }
        .buttonStyle(.plain)
    }

    private var inlinePreviewBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text("AI Draft")
                        .font(.subheadline.weight(.semibold))
                    Text(aiController.isGenerating ? "Writing suggestion in your note..." : "Review and choose what to keep.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                if aiController.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                if aiController.isGenerating {
                    Button {
                        aiController.stop(llamaContext: vm.llamaContext)
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                } else if aiController.canResume {
                    Button {
                        _ = aiController.resume(
                            llamaContext: vm.llamaContext,
                            isAppGenerating: vm.isGenerating
                        )
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    discardPreview()
                } label: {
                    Label("Discard", systemImage: "xmark")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    acceptPreview()
                } label: {
                    Label("Accept", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(aiController.isGenerating || !aiController.canAcceptPreview)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.9)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 8, x: 0, y: 2)
    }

    private var editorCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(cardStroke, lineWidth: 0.8)
                )

            if displayedEditorText.isEmpty {
                Text("Write your note here...")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            SelectionAwareTextEditor(
                text: editorTextBinding,
                selectedRange: editorSelectionBinding,
                isEditable: !aiController.hasPendingPreview
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if aiController.hasPendingPreview {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.07))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var cardFill: Color {
        Color(.secondarySystemBackground)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }

    private var buttonFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    private var displayedEditorText: String {
        aiController.previewNoteContent(fallbackCurrentText: note.content)
    }

    private var editorTextBinding: Binding<String> {
        if aiController.hasPendingPreview {
            return Binding(
                get: { displayedEditorText },
                set: { _ in }
            )
        }
        return $note.content
    }

    private var editorSelectionBinding: Binding<NSRange> {
        if aiController.hasPendingPreview {
            return Binding(
                get: {
                    aiController.previewSelectionRange(
                        fallback: clampedSelection(editorSelection, in: displayedEditorText)
                    )
                },
                set: { _ in }
            )
        }
        return $editorSelection
    }

    private var noteMetricsText: String {
        let words = wordCount(in: note.content)
        return words == 1 ? "1 word" : "\(words) words"
    }

    private var scopeHintText: String {
        if !vm.isChatModelLoaded {
            return "Load a chat model in Settings to enable AI writing tools."
        }
        if let scope = aiController.scopeDescription {
            return scope
        }
        let safe = clampedSelection(editorSelection, in: note.content)
        if safe.length > 0 {
            return "Selection detected: actions apply only to highlighted text."
        }
        return "No selection: Auto-Complete uses cursor; other actions apply to full note."
    }

    private func startAction(_ action: NoteAIAction) {
        let safeSelection = clampedSelection(editorSelection, in: note.content)
        editorSelection = safeSelection
        _ = aiController.start(
            action: action,
            noteText: note.content,
            selectedRange: safeSelection,
            isModelLoaded: vm.isChatModelLoaded,
            isAppGenerating: vm.isGenerating,
            llamaContext: vm.llamaContext
        )
    }

    private func acceptPreview() {
        guard let accepted = aiController.accept() else { return }
        let previous = note.content
        registerUndo(previousContent: previous, action: accepted.action)
        note.content = accepted.content
        editorSelection = clampedSelection(accepted.selectedRange, in: accepted.content)
    }

    private func discardPreview() {
        if aiController.isGenerating {
            aiController.stop(llamaContext: vm.llamaContext)
        }
        guard let rejected = aiController.reject() else { return }
        note.content = rejected.content
        editorSelection = clampedSelection(rejected.selectedRange, in: rejected.content)
    }

    private func registerUndo(previousContent: String, action: NoteAIAction) {
        guard let undoManager else { return }
        let vm = vm
        let modelContext = modelContext

        undoManager.registerUndo(withTarget: note) { target in
            let redoContent = target.content
            target.content = previousContent
            target.updatedAt = Date()
            vm.handleNoteEdited(target, modelContext: modelContext)

            undoManager.registerUndo(withTarget: target) { redoTarget in
                redoTarget.content = redoContent
                redoTarget.updatedAt = Date()
                vm.handleNoteEdited(redoTarget, modelContext: modelContext)
            }
        }
        undoManager.setActionName(action.undoActionName)
    }

    private func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func clampedSelection(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        let safeLength = min(max(0, range.length), length - location)
        return NSRange(location: location, length: safeLength)
    }
}
