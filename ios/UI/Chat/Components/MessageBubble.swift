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

            VStack(alignment: .leading, spacing: 10) {
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
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .contentTransition(.opacity)
                    }
                } else {
                    Text(message.content)
                        .foregroundStyle(.white)
                        .font(.body)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }

                if message.role == "assistant", !inlineCitationIds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(inlineCitationIds.prefix(2)), id: \.self) { citation in
                                Button(citation) {
                                    onCitationTap?(citation)
                                }
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.chipFill)
                                .foregroundStyle(.white)
                                .overlay(
                                    Capsule().stroke(AppTheme.chipStroke, lineWidth: 0.8)
                                )
                                .clipShape(Capsule())
                                .controlSize(.small)
                            }
                            if inlineCitationIds.count > 2 {
                                Button("+\(inlineCitationIds.count - 2)") {
                                    showingSources = true
                                }
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.chipFill)
                                .foregroundStyle(.white)
                                .overlay(
                                    Capsule().stroke(AppTheme.chipStroke, lineWidth: 0.8)
                                )
                                .clipShape(Capsule())
                                .controlSize(.small)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                                                .font(.caption2.weight(.bold))
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
                                    .background(Color.white.opacity(0.09))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 0.6)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .tint(.white.opacity(0.85))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if message.role == "assistant", !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 10) {
                        if let onWhyTapped {
                            Button("Why this answer?") {
                                onWhyTapped()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.secondary.opacity(0.8))
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
                            .tint(Color.white.opacity(0.4))
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: backgroundGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.9)
            )
            .shadow(color: AppTheme.subtleShadow, radius: 6, x: 0, y: 3)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: showingSources)

            if message.role != "user" { Spacer(minLength: 44) }
        }
    }

    private var backgroundGradient: [Color] {
        if message.role == "user" {
            return [AppTheme.bubbleUserTop, AppTheme.bubbleUser]
        }
        return [AppTheme.bubbleAiTop, AppTheme.bubbleAi]
    }
}
