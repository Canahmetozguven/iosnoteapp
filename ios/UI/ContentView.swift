import SwiftUI

struct ContentView: View {
    var body: some View {
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
    }
}
