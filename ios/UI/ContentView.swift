import SwiftUI

struct ContentView: View {
    @AppStorage(OnboardingState.completionKey) private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                TabView {
                    NotesView()
                        .tabItem {
                            Label("Notes", systemImage: "note.text")
                        }

                    NavigationStack {
                        ChatView()
                    }
                    .tabItem {
                        Label("Chat", systemImage: "message")
                    }

                    NavigationStack {
                        FilesView()
                    }
                    .tabItem {
                        Label("Files", systemImage: "folder")
                    }
                }
                .tint(AppTheme.primary)
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
    }
}
