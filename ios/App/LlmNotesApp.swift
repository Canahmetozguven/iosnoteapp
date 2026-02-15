import SwiftUI
import SwiftData

@main
struct LlmNotesApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var globalViewModel = GlobalViewModel()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SchemaV1.Note.self,
            SchemaV1.ChatMessage.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(globalViewModel)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        globalViewModel.handleSceneDidBecomeActive()
                    case .background:
                        globalViewModel.handleSceneDidEnterBackground()
                    default:
                        break
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
