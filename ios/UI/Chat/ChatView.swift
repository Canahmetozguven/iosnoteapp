import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(GlobalViewModel.self) var vm
    @Query private var notes: [Note]
    @State private var inputText: String = ""
    
    var body: some View {
        VStack {
            if !vm.isChatModelLoaded {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Model not loaded")
                        .font(.headline)
                    Text("Please go to Settings, download a chat model, and tap Load Model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(vm.chatMessages, id: \.id) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: vm.chatMessages.count) {
                        if let lastId = vm.chatMessages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    // Auto-scroll for streaming updates
                    .onChange(of: vm.chatMessages.last?.content) {
                        if let lastId = vm.chatMessages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                
                HStack {
                    TextField("Type a message...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(vm.isBusy && vm.chatMessages.last?.role == "assistant") // Disable only if generating
                    
                    if vm.isBusy && vm.chatMessages.last?.role == "assistant" {
                         Button(action: {
                             vm.stopGeneration()
                         }) {
                             Image(systemName: "stop.circle.fill")
                                 .font(.title2)
                                 .foregroundStyle(.red)
                         }
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        vm.sendMessage(text: text, notes: notes)
    }
}
