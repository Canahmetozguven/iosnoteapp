import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == "user" { Spacer() }
            
            VStack(alignment: .leading) {
                if message.role == "assistant" {
                    let parts = parseContent(message.content)
                    
                    if let thought = parts.thought {
                        DisclosureGroup("Thinking Process") {
                            Text(thought)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                                .overlay(
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 2)
                                        .padding(.vertical, 4),
                                    alignment: .leading
                                )
                        }
                        .tint(.gray)
                    }
                    
                    if !parts.response.isEmpty {
                        Text(LocalizedStringKey(parts.response)) // Markdown support
                    } else if parts.thought != nil && parts.isThinking {
                        // Still thinking and no response yet
                        HStack {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(message.content)
                }
            }
            .padding(12)
            .background(message.role == "user" ? AppTheme.primary.opacity(0.18) : AppTheme.bubbleAi)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            if message.role != "user" { Spacer() }
        }
    }
    
    struct ParsedContent {
        var thought: String?
        var response: String
        var isThinking: Bool
    }
    
    func parseContent(_ content: String) -> ParsedContent {
        // Simple parser for <think>...</think>
        if content.contains("<think>") {
            let components = content.components(separatedBy: "</think>")
            if components.count > 1 {
                // Completed thought
                let thoughtPart = components[0].replacingOccurrences(of: "<think>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let responsePart = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                return ParsedContent(thought: thoughtPart, response: responsePart, isThinking: false)
            } else {
                // Still thinking (no closing tag)
                let thoughtPart = content.replacingOccurrences(of: "<think>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return ParsedContent(thought: thoughtPart, response: "", isThinking: true)
            }
        }
        return ParsedContent(thought: nil, response: content, isThinking: false)
    }
}
