import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var selectedIndex = 0
    @AppStorage(OnboardingState.ragRetrievalProfileKey) private var profileRaw = RAGRetrievalProfile.fastRecommended.rawValue
    @AppStorage(OnboardingState.strictGroundingKey) private var strictGrounding = false

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            kind: .info,
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
            kind: .info,
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
            kind: .qualitySetup,
            title: "Choose Answer Style",
            detail: "You can change this anytime in Settings.",
            points: [
                "Fast is best for everyday speed.",
                "Deep Search checks more sources before answering.",
                "Strict grounding avoids unsupported claims."
            ],
            symbol: "slider.horizontal.3",
            tint: AppTheme.primaryDark
        ),
        OnboardingStep(
            kind: .info,
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
            kind: .info,
            title: "Build a Knowledge Base",
            detail: "Import PDFs, images, and text into Knowledge Base. OCR extracts content and Chat retrieves relevant chunks.",
            points: [
                "Import from Files, Photos, or connected Google Drive.",
                "Apple Vision OCR is currently used for all imports.",
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
                    Group {
                        if step.kind == .qualitySetup {
                            QualitySetupCard(profileRaw: $profileRaw, strictGrounding: $strictGrounding)
                        } else {
                            OnboardingStepCard(step: step)
                        }
                    }
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
        if RAGRetrievalProfile(rawValue: profileRaw) == nil {
            profileRaw = RAGRetrievalProfile.fastRecommended.rawValue
        }
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

private struct QualitySetupCard: View {
    @Binding var profileRaw: String
    @Binding var strictGrounding: Bool

    private var selectedProfile: RAGRetrievalProfile {
        RAGRetrievalProfile(rawValue: profileRaw) ?? .fastRecommended
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(AppTheme.primaryDark.opacity(0.14))
                    .frame(width: 84, height: 84)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryDark)
            }

            Text("Choose Answer Style")
                .font(.system(.title2, design: .rounded).weight(.bold))

            Text("This controls how much the app searches before answering.")
                .font(.body)
                .foregroundStyle(.secondary)

            Picker("Answer Quality", selection: Binding(
                get: { selectedProfile },
                set: { profileRaw = $0.rawValue }
            )) {
                ForEach(RAGRetrievalProfile.allCases) { profile in
                    Text(profile.displayName).tag(profile)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedProfile.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Strict grounding", isOn: $strictGrounding)
            Text("When on, the assistant avoids unsupported claims and asks for more sources when needed.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
    enum Kind {
        case info
        case qualitySetup
    }

    let kind: Kind
    let title: String
    let detail: String
    let points: [String]
    let symbol: String
    let tint: Color
}
