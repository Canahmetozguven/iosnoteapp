import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 44) }

            VStack(alignment: .leading, spacing: 8) {
                if let thought = message.thoughtProcess?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !thought.isEmpty {
                    DisclosureGroup("Thinking Process") {
                        Text(thought)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .tint(.white.opacity(0.85))
                }

                if message.content.isEmpty && message.role == "assistant" {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                } else {
                    Text(message.content)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            if message.role != "user" { Spacer(minLength: 44) }
        }
    }

    private var backgroundColor: Color {
        message.role == "user" ? AppTheme.bubbleUser : AppTheme.bubbleAi
    }
}
