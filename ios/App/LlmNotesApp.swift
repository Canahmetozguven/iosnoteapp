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

    var sharedModelContainer: ModelContainer = Self.makeModelContainer()

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

    private static func makeSchema() -> Schema {
        Schema([
            SchemaV4.Note.self,
            SchemaV4.ChatSession.self,
            SchemaV4.ChatMessage.self,
            SchemaV4.KnowledgeDocument.self,
            SchemaV4.KnowledgeChunk.self
        ])
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = makeSchema()
        let persistentConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppSchemaMigrationPlan.self,
                configurations: [persistentConfig]
            )
        } catch {
            // Do not hard-crash in production if migration metadata is inconsistent.
            print("SwiftData: migration plan container init failed: \(error)")
        }

        do {
            return try ModelContainer(for: schema, configurations: [persistentConfig])
        } catch {
            print("SwiftData: direct persistent container init failed: \(error)")
        }

        do {
            let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [inMemoryConfig])
        } catch {
            fatalError("Could not create any ModelContainer: \(error)")
        }
    }
}
