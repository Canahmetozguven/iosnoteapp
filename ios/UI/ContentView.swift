import SwiftUI

private enum AppTab: Int {
    case notes = 0
    case chat = 1
    case knowledge = 2
}

struct ContentView: View {
    @AppStorage(OnboardingState.completionKey) private var hasCompletedOnboarding = false
    @AppStorage(OnboardingState.selectedTabKey) private var selectedTabRaw = AppTab.chat.rawValue

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                TabView(selection: $selectedTabRaw) {
                    NotesView()
                        .tag(AppTab.notes.rawValue)
                        .tabItem {
                            Label("Notes", systemImage: "note.text")
                        }

                    NavigationStack {
                        ChatView()
                    }
                    .tag(AppTab.chat.rawValue)
                    .tabItem {
                        Label("Chat", systemImage: "message")
                    }

                    NavigationStack {
                        KnowledgeBaseView()
                    }
                    .tag(AppTab.knowledge.rawValue)
                    .tabItem {
                        Label("Knowledge", systemImage: "books.vertical")
                    }
                }
                .tint(AppTheme.primary)
                .onAppear {
                    if AppTab(rawValue: selectedTabRaw) == nil {
                        selectedTabRaw = AppTab.chat.rawValue
                    }
                }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
    }
}
