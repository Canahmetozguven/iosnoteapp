import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(GlobalViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [Note]

    @State private var inputText = ""
    @State private var showingSessionSheet = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let ragStatusText = vm.ragStatusText() {
                Text(ragStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
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
        }
        .onChange(of: vm.isEmbeddingModelLoaded) {
            if vm.isEmbeddingModelLoaded {
                vm.startAutoIndexIfNeeded(notes: notes, modelContext: modelContext)
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
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }
            .scrollDismissesKeyboard(.interactively)
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
                .background(Color(.tertiarySystemBackground))
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
        .background(Color(.secondarySystemBackground).opacity(0.95))
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        vm.sendMessage(text: text, notes: notes, modelContext: modelContext)
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
