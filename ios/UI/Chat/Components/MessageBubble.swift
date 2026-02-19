import SwiftUI

struct SourcePreview: Identifiable, Hashable {
    var id: String
    var citationId: String?
    var title: String
    var subtitle: String?
    var snippet: String
}

struct MessageBubble: View {
    let message: ChatMessage
    var sourcePreviews: [SourcePreview] = []
    var inlineCitationIds: [String] = []
    var stageText: String? = nil
    var feedback: AssistantAnswerFeedback? = nil
    var onCitationTap: ((String) -> Void)? = nil
    var onWhyTapped: (() -> Void)? = nil
    var onRetryDeepSearch: (() -> Void)? = nil
    var onFeedback: ((AssistantAnswerFeedback) -> Void)? = nil
    @State private var showingSources = false

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
                        Text(stageText ?? "Thinking...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                } else {
                    Text(message.content)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }

                if message.role == "assistant", !inlineCitationIds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(inlineCitationIds.prefix(2)), id: \.self) { citation in
                                Button(citation) {
                                    onCitationTap?(citation)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.white.opacity(0.16))
                                .controlSize(.small)
                            }
                            if inlineCitationIds.count > 2 {
                                Button("+\(inlineCitationIds.count - 2)") {
                                    showingSources = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.white.opacity(0.16))
                                .controlSize(.small)
                            }
                        }
                    }
                }

                if message.role == "assistant", !sourcePreviews.isEmpty {
                    DisclosureGroup("Sources (\(sourcePreviews.count))", isExpanded: $showingSources) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(sourcePreviews.prefix(4)) { preview in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 4) {
                                            if let citation = preview.citationId {
                                                Text(citation)
                                                    .font(.caption2.weight(.bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.white.opacity(0.14))
                                                    .clipShape(Capsule())
                                            }
                                            Text(preview.title)
                                                .font(.caption2.weight(.semibold))
                                                .lineLimit(1)
                                        }
                                        if let subtitle = preview.subtitle, !subtitle.isEmpty {
                                            Text(subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.75))
                                                .lineLimit(1)
                                        }
                                        Text(preview.snippet)
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.88))
                                            .lineLimit(3)
                                    }
                                    .padding(8)
                                    .frame(width: 220, alignment: .leading)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .tint(.white.opacity(0.85))
                }

                if message.role == "assistant", !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 10) {
                        if let onWhyTapped {
                            Button("Why this answer?") {
                                onWhyTapped()
                            }
                            .buttonStyle(.bordered)
                            .tint(.white.opacity(0.35))
                            .controlSize(.small)
                        }
                        if onRetryDeepSearch != nil || onFeedback != nil {
                            Menu {
                                if let onRetryDeepSearch {
                                    Button("Retry in Deep Search") {
                                        onRetryDeepSearch()
                                    }
                                }
                                if let onFeedback {
                                    Section("Rate This Answer") {
                                        ForEach(AssistantAnswerFeedback.allCases, id: \.rawValue) { item in
                                            Button {
                                                onFeedback(item)
                                            } label: {
                                                if feedback == item {
                                                    Label(item.label, systemImage: "checkmark")
                                                } else {
                                                    Text(item.label)
                                                }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white.opacity(0.35))
                            .controlSize(.small)
                        }
                    }
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
