import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Environment(GlobalViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Bindable var note: Note
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var aiController = NoteEditorAIController()
    @State private var hideUnchangedDiffLines = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $note.title, axis: .vertical)
                .font(.system(size: 28, weight: .bold))
                .padding(.horizontal)
                .padding(.top)
                .disabled(aiController.hasPendingPreview)

            actionBar

            ZStack(alignment: .topLeading) {
                if note.content.isEmpty {
                    Text("Write your note here...")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                SelectionAwareTextEditor(
                    text: $note.content,
                    selectedRange: $editorSelection,
                    isEditable: !aiController.hasPendingPreview
                )
                .padding(.horizontal)
            }
            .frame(maxHeight: .infinity)

            if aiController.hasPendingPreview {
                previewPanel
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .onChange(of: note.title) { _ in
            note.updatedAt = Date()
            vm.handleNoteEdited(note, modelContext: modelContext)
        }
        .onChange(of: note.content) { _ in
            note.updatedAt = Date()
            vm.handleNoteEdited(note, modelContext: modelContext)
            editorSelection = clampedSelection(editorSelection, in: note.content)
        }
        .onDisappear {
            if aiController.isGenerating {
                aiController.stop(llamaContext: vm.llamaContext)
            }
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NoteAIAction.allCases) { action in
                        Button {
                            startAction(action)
                        } label: {
                            Label(action.title, systemImage: action.icon)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(aiController.hasPendingPreview)
                    }
                }
                .padding(.horizontal)
            }

            Picker(
                "Style",
                selection: Binding(
                    get: { aiController.outputStyle },
                    set: { aiController.outputStyle = $0 }
                )
            ) {
                ForEach(NoteAIOutputStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .disabled(aiController.hasPendingPreview)

            if let scope = aiController.scopeDescription {
                Text(scope)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else if !vm.isChatModelLoaded {
                Text("Load a chat model in Settings to enable in-note AI actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            if !aiController.hasPendingPreview, let error = aiController.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(aiController.activeAction?.title ?? "AI") Preview")
                    .font(.headline)
                Spacer()
                if aiController.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !aiController.previewThought.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thought Process")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(aiController.previewThought)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Diff Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Toggle("Hide unchanged", isOn: $hideUnchangedDiffLines)
                    .font(.caption)
                    .toggleStyle(.switch)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if displayedDiffLines.isEmpty {
                            Text("Generating preview...")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(displayedDiffLines.enumerated()), id: \.offset) { _, line in
                                diffLineRow(line)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .padding(8)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let error = aiController.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                if aiController.isGenerating {
                    Button("Stop") {
                        aiController.stop(llamaContext: vm.llamaContext)
                    }
                }

                Button("Reject", role: .destructive) {
                    rejectPreview()
                }

                Spacer()

                Button("Accept") {
                    acceptPreview()
                }
                .disabled(aiController.isGenerating || !aiController.canAcceptPreview)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
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

    private func rejectPreview() {
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

    private func clampedSelection(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        let safeLength = min(max(0, range.length), length - location)
        return NSRange(location: location, length: safeLength)
    }

    private var displayedDiffLines: [NoteEditorAIController.PreviewDiffLine] {
        aiController.previewDiffLines(hideUnchanged: hideUnchangedDiffLines)
    }

    @ViewBuilder
    private func diffLineRow(_ line: NoteEditorAIController.PreviewDiffLine) -> some View {
        let marker: String
        let tint: Color
        let background: Color

        switch line.kind {
        case .context:
            marker = " "
            tint = .secondary
            background = .clear
        case .removed:
            marker = "-"
            tint = .red
            background = Color.red.opacity(0.08)
        case .added:
            marker = "+"
            tint = .green
            background = Color.green.opacity(0.10)
        case .meta:
            marker = "…"
            tint = .secondary.opacity(0.8)
            background = Color(.tertiarySystemFill)
        }

        HStack(alignment: .top, spacing: 8) {
            Text(marker)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(tint)
                .frame(width: 10, alignment: .leading)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
