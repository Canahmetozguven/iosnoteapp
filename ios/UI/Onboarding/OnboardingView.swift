import SwiftUI

struct OnboardingView: View {
    @Environment(GlobalViewModel.self) private var vm
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
            kind: .modelDownload,
            title: "Set Up AI Once",
            detail: "Before chatting, you need to download a lightweight Chat model. We recommend this small model to get started quickly.",
            points: [],
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
                .disabled(!(hasChatModel && hasEmbeddingModel) || isLastStep)
            }

            TabView(selection: $selectedIndex) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Group {
                        if step.kind == .qualitySetup {
                            QualitySetupCard(profileRaw: $profileRaw, strictGrounding: $strictGrounding)
                        } else if step.kind == .modelDownload {
                            ModelDownloadCard(step: step)
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
            .onChange(of: selectedIndex) { _, newIndex in
                let downloadIndex = steps.firstIndex(where: { $0.kind == .modelDownload }) ?? 1
                if newIndex > downloadIndex && !(hasChatModel && hasEmbeddingModel) {
                    // Prevent swiping past the model download step if either model is missing
                    selectedIndex = downloadIndex
                }
            }

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
                .disabled(!canMoveForward)
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

    private var hasChatModel: Bool {
        vm.catalogStore.items(kind: .chat).contains { vm.isInstalled($0) }
    }

    private var hasEmbeddingModel: Bool {
        vm.catalogStore.items(kind: .embedding).contains { vm.isInstalled($0) }
    }

    private var canMoveForward: Bool {
        let step = steps[selectedIndex]
        if step.kind == .modelDownload {
            return hasChatModel && hasEmbeddingModel
        }
        return true
    }

    private func completeOnboarding() {
        if RAGRetrievalProfile(rawValue: profileRaw) == nil {
            profileRaw = RAGRetrievalProfile.fastRecommended.rawValue
        }
        hasCompletedOnboarding = true
    }
}

private struct ModelDownloadCard: View {
    @Environment(GlobalViewModel.self) private var vm
    let step: OnboardingStep

    private var suggestedChatModel: ModelCatalogItem? {
        vm.catalogStore.items.first(where: { $0.id == "qwen3-0.6b-q4-k-m" }) ?? vm.catalogStore.items.first(where: { $0.kind == .chat })
    }

    private var suggestedEmbeddingModel: ModelCatalogItem? {
        vm.catalogStore.items.first(where: { $0.id == "bge-small-en-v1.5-q8-0" }) ?? vm.catalogStore.items.first(where: { $0.kind == .embedding })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            Text("Before chatting, you need to download a lightweight Chat model and an Embedding model for searching notes.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                if let chatModel = suggestedChatModel {
                    modelRow(item: chatModel, label: "Chat Model:")
                }
                
                if let embeddingModel = suggestedEmbeddingModel {
                    modelRow(item: embeddingModel, label: "Embedding Model:")
                }
            }
            .padding(.top, 4)
            
            let hasChat = vm.catalogStore.items(kind: .chat).contains(where: { vm.isInstalled($0) })
            let hasEmbedding = vm.catalogStore.items(kind: .embedding).contains(where: { vm.isInstalled($0) })

            if !(hasChat && hasEmbedding) {
                Text("You must download both models to continue.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.redError)
            } else {
                Text("Models ready! You can now move forward.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.greenSuccess)
                    .onAppear {
                        if vm.currentChatModelId == nil, let chatModel = suggestedChatModel {
                            vm.loadChatModel(item: chatModel)
                        }
                        if vm.currentEmbeddingModelId == nil, let embeddingModel = suggestedEmbeddingModel {
                            vm.loadEmbeddingModel(item: embeddingModel)
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

    @ViewBuilder
    private func modelRow(item: ModelCatalogItem, label: String) -> some View {
        let isInstalled = vm.isInstalled(item)
        let downloadState = vm.downloads.state(for: item.id)

        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.greenSuccess)
                        .font(.title2)
                } else {
                    switch downloadState {
                    case .notStarted, .failed, .paused:
                        Button {
                            vm.startDownload(item)
                        } label: {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.title2)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.primary)
                    case .queued:
                        ProgressView()
                    case .downloading(let progress, _, _):
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.greenSuccess)
                            .font(.title2)
                    }
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
        }
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
        case modelDownload
    }

    let kind: Kind
    let title: String
    let detail: String
    let points: [String]
    let symbol: String
    let tint: Color
}
