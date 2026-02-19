import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(GlobalViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [Note]
    @Query private var knowledgeChunks: [KnowledgeChunk]
    @AppStorage(OnboardingState.selectedTabKey) private var selectedTabRaw = 1

    @State private var inputText = ""
    @State private var showingSessionSheet = false
    @State private var strictForNextMessage = false
    @State private var whyMessageId: UUID?
    @State private var selectedSourcePreview: SourcePreview?
    @State private var showingChatOptions = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let ragStatusText = vm.ragStatusText() {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ragStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let stage = vm.generationStage {
                        Text(stage.displayText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let debugLine = vm.ragDebugText() {
                        Text(debugLine)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if isNoContextState {
                        noContextActions
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground).opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.45), lineWidth: 0.6)
                        )
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !vm.isChatModelLoaded {
                unloadedModelState
            } else {
                messagesArea
                composer
            }
        }
        .background(
            LinearGradient(
                colors: [Color(.systemGroupedBackground), Color(.secondarySystemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isInputFocused = false
        }
        .navigationTitle(vm.activeSession()?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.2), value: vm.generationStage?.rawValue ?? "")
        .animation(.easeInOut(duration: 0.2), value: vm.ragStatusText() ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSessionSheet = true
                } label: {
                    Image(systemName: "text.bubble")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vm.createNewChatSession(modelContext: modelContext)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingSessionSheet) {
            ChatSessionsSheet(vm: vm, modelContext: modelContext)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingChatOptions) {
            ChatOptionsSheet(vm: vm, strictForNextMessage: $strictForNextMessage)
                .presentationDetents([.medium])
        }
        .sheet(item: $selectedSourcePreview) { preview in
            SourcePreviewSheet(preview: preview)
        }
        .sheet(isPresented: whySheetPresented) {
            if let message = assistantMessage(by: whyMessageId) {
                WhyAnswerSheet(
                    message: message,
                    insight: vm.insight(for: message.id),
                    sourcePreviews: sourcePreviews(for: message)
                )
            }
        }
        .onAppear {
            strictForNextMessage = vm.strictGroundingMode
            vm.bootstrapIfNeeded(modelContext: modelContext)
            vm.startAutoIndexIfNeeded(notes: notes, modelContext: modelContext)
            vm.startAutoIndexKnowledgeIfNeeded(chunks: knowledgeChunks, modelContext: modelContext)
        }
        .onChange(of: vm.strictGroundingMode) { _, newValue in
            strictForNextMessage = newValue
        }
        .onChange(of: vm.isEmbeddingModelLoaded) {
            if vm.isEmbeddingModelLoaded {
                vm.startAutoIndexIfNeeded(notes: notes, modelContext: modelContext)
                vm.startAutoIndexKnowledgeIfNeeded(chunks: knowledgeChunks, modelContext: modelContext)
            }
        }
    }

    private var whySheetPresented: Binding<Bool> {
        Binding(
            get: { whyMessageId != nil },
            set: { if !$0 { whyMessageId = nil } }
        )
    }

    private var isNoContextState: Bool {
        if case .usedContext(let count) = vm.ragStatus, count == 0 {
            return true
        }
        return false
    }

    private var noContextActions: some View {
        HStack(spacing: 8) {
            Button("Add Source") {
                selectedTabRaw = 2
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
            .controlSize(.small)

            Menu("More") {
                Button("Ask narrower") {
                    inputText = "Using my notes/documents only: "
                    isInputFocused = true
                }
                Button("Switch to Deep Search") {
                    vm.ragRetrievalProfile = .deepSearch
                }
            }
            .controlSize(.small)
        }
    }

    private var unloadedModelState: some View {
        VStack(spacing: 14) {
            Image(systemName: "cpu")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
            Text("Chat model is not loaded")
                .font(.headline)
            Text("Open Settings, download a chat model, and load it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(vm.chatMessages, id: \.id) { msg in
                        MessageBubble(
                            message: msg,
                            sourcePreviews: sourcePreviews(for: msg),
                            inlineCitationIds: inlineCitationIds(for: msg),
                            stageText: vm.generationStage?.displayText,
                            feedback: vm.feedback(for: msg.id),
                            onCitationTap: { citation in
                                let normalized = citation
                                    .replacingOccurrences(of: "[", with: "")
                                    .replacingOccurrences(of: "]", with: "")
                                if let preview = sourcePreviews(for: msg).first(where: {
                                    $0.citationId == normalized || $0.citationId == citation
                                }) {
                                    selectedSourcePreview = preview
                                }
                            },
                            onWhyTapped: msg.role == "assistant" ? { whyMessageId = msg.id } : nil,
                            onRetryDeepSearch: msg.role == "assistant" ? { retryAssistantAnswer(msg, profile: .deepSearch) } : nil,
                            onFeedback: msg.role == "assistant" ? { feedback in
                                vm.recordFeedback(feedback, for: msg)
                            } : nil
                        )
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                isInputFocused = false
            })
            .onChange(of: vm.chatMessages.count) {
                if let lastId = vm.chatMessages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: vm.chatMessages.last?.content) {
                if let lastId = vm.chatMessages.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask anything...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.cardBorder.opacity(0.95))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(vm.isGenerating)
                .focused($isInputFocused)

            if !vm.isGenerating {
                Button {
                    showingChatOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(AppTheme.cardBorder.opacity(0.95))
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
            }

            if vm.isGenerating {
                Button {
                    vm.stopGeneration()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(AppTheme.redError.opacity(0.15))
                        .foregroundStyle(AppTheme.redError)
                        .clipShape(Circle())
                }
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(AppTheme.primary)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [AppTheme.card.opacity(0.96), AppTheme.cardElevated.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.6)
        }
        .shadow(color: AppTheme.subtleShadow, radius: 10, x: 0, y: -2)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        vm.sendMessage(
            text: text,
            notes: notes,
            knowledgeChunks: knowledgeChunks,
            strictGrounding: strictForNextMessage,
            modelContext: modelContext
        )
    }

    private func inlineCitationIds(for message: ChatMessage) -> [String] {
        guard message.role == "assistant" else { return [] }
        let citations = vm.citations(for: message.id)
        if !citations.isEmpty {
            return citations.map { "[\($0.id)]" }
        }
        guard let regex = try? NSRegularExpression(pattern: #"\[S\d+\]"#, options: []) else {
            return []
        }
        let range = NSRange(message.content.startIndex..., in: message.content)
        let matches = regex.matches(in: message.content, options: [], range: range)
        let values = matches.compactMap { match in
            Range(match.range, in: message.content).map { String(message.content[$0]) }
        }
        var seen: Set<String> = []
        var unique: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            unique.append(value)
        }
        return unique
    }

    private func sourcePreviews(for message: ChatMessage) -> [SourcePreview] {
        guard message.role == "assistant" else { return [] }
        let citations = vm.citations(for: message.id)
        if !citations.isEmpty {
            return citations.map { citation in
                let subtitle: String?
                switch citation.sourceType {
                case .note:
                    subtitle = "Note"
                case .knowledgeChunk:
                    if let index = citation.chunkIndex {
                        subtitle = "Knowledge chunk \(index)"
                    } else {
                        subtitle = "Knowledge"
                    }
                }
                return SourcePreview(
                    id: citation.id,
                    citationId: citation.id,
                    title: citation.title,
                    subtitle: subtitle,
                    snippet: citation.snippet
                )
            }
        }

        var previews: [SourcePreview] = []
        let noteById = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let chunkById = Dictionary(uniqueKeysWithValues: knowledgeChunks.map { ($0.id, $0) })

        for id in message.sourceNoteIds {
            guard let note = noteById[id] else { continue }
            let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            previews.append(
                SourcePreview(
                    id: "note-\(id.uuidString)",
                    citationId: nil,
                    title: title.isEmpty ? "Untitled Note" : title,
                    subtitle: "Note",
                    snippet: String(note.content.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        for id in message.sourceKnowledgeChunkIds {
            guard let chunk = chunkById[id] else { continue }
            let docTitle = chunk.document?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolved = docTitle.isEmpty ? "Document" : docTitle
            previews.append(
                SourcePreview(
                    id: "chunk-\(id.uuidString)",
                    citationId: nil,
                    title: resolved,
                    subtitle: "Chunk \(chunk.chunkIndex + 1)",
                    snippet: String(chunk.text.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        return previews
    }

    private func assistantMessage(by id: UUID?) -> ChatMessage? {
        guard let id else { return nil }
        return vm.chatMessages.first(where: { $0.id == id && $0.role == "assistant" })
    }

    private func retryAssistantAnswer(_ message: ChatMessage, profile: RAGRetrievalProfile) {
        guard let messageIndex = vm.chatMessages.firstIndex(where: { $0.id == message.id }) else { return }
        guard let userPrompt = vm.chatMessages[..<messageIndex].reversed().first(where: { $0.role == "user" })?.content else { return }

        vm.sendMessage(
            text: userPrompt,
            notes: notes,
            knowledgeChunks: knowledgeChunks,
            forcedProfile: profile,
            strictGrounding: vm.insight(for: message.id)?.strictGrounding ?? strictForNextMessage,
            modelContext: modelContext
        )
    }
}

private struct ChatOptionsSheet: View {
    let vm: GlobalViewModel
    @Binding var strictForNextMessage: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Answer Quality") {
                    Picker("Mode", selection: Bindable(vm).ragRetrievalProfile) {
                        ForEach(RAGRetrievalProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(vm.ragRetrievalProfile.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Grounding") {
                    Toggle("Strict grounding for next answer", isOn: $strictForNextMessage)
                    Text("When enabled, the assistant avoids unsupported claims and asks for more sources when needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Chat Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        vm.strictGroundingMode = strictForNextMessage
                        dismiss()
                    }
                }
            }
            .onDisappear {
                vm.strictGroundingMode = strictForNextMessage
            }
        }
    }
}

private struct WhyAnswerSheet: View {
    let message: ChatMessage
    let insight: AssistantAnswerInsight?
    let sourcePreviews: [SourcePreview]

    var body: some View {
        NavigationStack {
            List {
                Section("Answer Quality") {
                    LabeledContent("Confidence", value: insight?.confidence.summaryText.capitalized ?? "Unknown")
                    LabeledContent("Search Mode", value: insight?.profile.displayName ?? "Unknown")
                    LabeledContent("Strict Grounding", value: (insight?.strictGrounding ?? false) ? "On" : "Off")
                    if let score = insight?.topScore {
                        LabeledContent("Top Match Score", value: String(format: "%.2f", score))
                    }
                    LabeledContent("Sources Used", value: "\(insight?.sourceCount ?? sourcePreviews.count)")
                }

                Section("Why this answer") {
                    Text("The assistant selected the sources below and used them to ground factual statements. Use feedback buttons in chat if this selection should improve.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Sources") {
                    if sourcePreviews.isEmpty {
                        Text("No linked sources were captured for this answer.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sourcePreviews) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title)
                                    .font(.subheadline.weight(.semibold))
                                if let subtitle = source.subtitle {
                                    Text(subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(source.snippet)
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Why This Answer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SourcePreviewSheet: View {
    let preview: SourcePreview

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemGroupedBackground), Color(.secondarySystemGroupedBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(preview.title)
                            .font(.headline)
                        if let subtitle = preview.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(preview.snippet)
                            .font(.body)
                            .lineSpacing(2)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.6), lineWidth: 0.6)
                    )
                    .padding(14)
                }
            }
            .navigationTitle(preview.citationId ?? "Source")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ChatSessionsSheet: View {
    let vm: GlobalViewModel
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var renameSession: ChatSession?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        vm.createNewChatSession(modelContext: modelContext)
                        dismiss()
                    } label: {
                        Label("New Chat", systemImage: "plus.bubble")
                    }
                }

                Section("Previous Chats") {
                    ForEach(vm.sessions, id: \.id) { session in
                        Button {
                            vm.selectSession(session, modelContext: modelContext)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .lineLimit(1)
                                    Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if vm.activeSessionId == session.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.greenSuccess)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Rename") {
                                renameSession = session
                                renameText = session.title
                            }
                            .tint(AppTheme.primary)

                            Button("Delete", role: .destructive) {
                                vm.deleteChatSession(session, modelContext: modelContext)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Rename Chat", isPresented: Binding(
                get: { renameSession != nil },
                set: { if !$0 { renameSession = nil } }
            )) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) {
                    renameSession = nil
                }
                Button("Save") {
                    if let target = renameSession {
                        vm.renameChatSession(target, title: renameText, modelContext: modelContext)
                    }
                    renameSession = nil
                }
            }
        }
    }
}
