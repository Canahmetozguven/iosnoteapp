import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(GlobalViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [Note]
    @Query private var knowledgeChunks: [KnowledgeChunk]

    @State private var inputText = ""
    @State private var showingSessionSheet = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let ragStatusText = vm.ragStatusText() {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ragStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let debugLine = vm.ragDebugText() {
                        Text(debugLine)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground).opacity(0.9))
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
        .onAppear {
            vm.bootstrapIfNeeded(modelContext: modelContext)
            vm.startAutoIndexIfNeeded(notes: notes, modelContext: modelContext)
            vm.startAutoIndexKnowledgeIfNeeded(chunks: knowledgeChunks, modelContext: modelContext)
        }
        .onChange(of: vm.isEmbeddingModelLoaded) {
            if vm.isEmbeddingModelLoaded {
                vm.startAutoIndexIfNeeded(notes: notes, modelContext: modelContext)
                vm.startAutoIndexKnowledgeIfNeeded(chunks: knowledgeChunks, modelContext: modelContext)
            }
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
                LazyVStack(spacing: 12) {
                    ForEach(vm.chatMessages, id: \.id) { msg in
                        MessageBubble(
                            message: msg,
                            sourceNoteTitles: sourceNoteTitles(for: msg),
                            sourceChunkTitles: sourceChunkTitles(for: msg)
                        )
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
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
        .background(AppTheme.card.opacity(0.95))
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        vm.sendMessage(text: text, notes: notes, knowledgeChunks: knowledgeChunks, modelContext: modelContext)
    }

    private func sourceNoteTitles(for message: ChatMessage) -> [String] {
        guard !message.sourceNoteIds.isEmpty else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return message.sourceNoteIds.compactMap { id in
            guard let note = byId[id] else { return nil }
            let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "Untitled Note" : title
        }
    }

    private func sourceChunkTitles(for message: ChatMessage) -> [String] {
        guard !message.sourceKnowledgeChunkIds.isEmpty else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: knowledgeChunks.map { ($0.id, $0) })
        return message.sourceKnowledgeChunkIds.compactMap { id in
            guard let chunk = byId[id] else { return nil }
            let docTitle = chunk.document?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolved = docTitle.isEmpty ? "Document" : docTitle
            return "\(resolved) (chunk \(chunk.chunkIndex + 1))"
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
