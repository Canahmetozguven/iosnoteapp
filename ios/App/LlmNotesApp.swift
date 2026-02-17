import SwiftUI
import SwiftData
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct LlmNotesApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var globalViewModel = GlobalViewModel()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SchemaV3.Note.self,
            SchemaV3.ChatSession.self,
            SchemaV3.ChatMessage.self,
            SchemaV3.KnowledgeDocument.self,
            SchemaV3.KnowledgeChunk.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppSchemaMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(globalViewModel)
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    _ = GIDSignIn.sharedInstance.handle(url)
                    #endif
                }
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
