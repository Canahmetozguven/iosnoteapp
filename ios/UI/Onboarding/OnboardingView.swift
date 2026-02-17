import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var selectedIndex = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            title: "Welcome to Synaps Notes",
            detail: "Capture ideas quickly, keep your notes organized, and chat with your own knowledge completely on-device.",
            points: [
                "Use the Notes tab to create and edit notes.",
                "Your notes are saved locally with SwiftData.",
                "Everything is designed for fast personal workflows."
            ],
            symbol: "sparkles",
            tint: AppTheme.primary
        ),
        OnboardingStep(
            title: "Set Up AI Once",
            detail: "Before chatting, open Settings and prepare local models.",
            points: [
                "Download and load one Chat model.",
                "Download and load one Embedding model.",
                "Low Power Mode is available for lighter devices."
            ],
            symbol: "gearshape.2.fill",
            tint: AppTheme.secondary
        ),
        OnboardingStep(
            title: "Chat With Your Notes",
            detail: "Use the Chat tab to ask questions. The app pulls relevant notes to answer with context (RAG).",
            points: [
                "Ask naturally, like \"summarize my project notes\".",
                "Keep notes updated so embeddings stay fresh.",
                "Create multiple chat sessions for different topics."
            ],
            symbol: "text.bubble.fill",
            tint: AppTheme.greenSuccess
        ),
        OnboardingStep(
            title: "Build a Knowledge Base",
            detail: "Import PDFs, images, and text into Knowledge Base. OCR extracts content and Chat retrieves relevant chunks.",
            points: [
                "Import from Files, Photos, or connected Google Drive.",
                "OCR model is used first when loaded; Vision OCR is fallback.",
                "Chat uses both Notes and Knowledge Base chunks as context."
            ],
            symbol: "books.vertical.fill",
            tint: AppTheme.primaryDark
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") {
                    completeOnboarding()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .opacity(isLastStep ? 0 : 1)
                .disabled(isLastStep)
            }

            TabView(selection: $selectedIndex) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    OnboardingStepCard(step: step)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.easeInOut(duration: 0.2), value: selectedIndex)

            HStack(spacing: 12) {
                if selectedIndex > 0 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedIndex -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }

                Button(isLastStep ? "Start Using App" : "Next") {
                    if isLastStep {
                        completeOnboarding()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedIndex += 1
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    private var isLastStep: Bool {
        selectedIndex == steps.count - 1
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}

private struct OnboardingStepCard: View {
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(step.tint.opacity(0.14))
                    .frame(width: 84, height: 84)
                Image(systemName: step.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(step.tint)
            }

            Text(step.title)
                .font(.system(.title2, design: .rounded).weight(.bold))

            Text(step.detail)
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(step.points, id: \.self) { point in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(step.tint)
                            .frame(width: 7, height: 7)
                            .padding(.top, 7)
                        Text(point)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

private struct OnboardingStep {
    let title: String
    let detail: String
    let points: [String]
    let symbol: String
    let tint: Color
}
