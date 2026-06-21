import SwiftData
import SwiftUI

/// App entry point. Sets up the SwiftData container and hosts `HomeView`.
@main
struct CueApp: App {
    /// Shared SwiftData container for the task store.
    let container: ModelContainer

    /// When the app is launched only to host the unit-test bundle, we skip the
    /// real on-disk store and the live UI so the test's own in-memory container
    /// is the single source of truth (avoids cross-container SwiftData conflicts).
    private let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        let useInMemory = isRunningTests
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: useInMemory)
            container = try ModelContainer(for: TaskItem.self, configurations: configuration)
        } catch {
            // A failed on-disk store shouldn't crash launch — fall back to an
            // in-memory store so the app still runs (data won't persist).
            do {
                let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try ModelContainer(for: TaskItem.self, configurations: fallback)
            } catch {
                fatalError("Could not create a SwiftData ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                // Hosting a test run — don't spin up the live UI or its @Query.
                Color.clear
            } else {
                HomeView()
                    .tint(.cueAccent)
            }
        }
        .modelContainer(container)
    }
}
