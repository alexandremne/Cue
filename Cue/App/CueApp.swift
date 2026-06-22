import SwiftData
import SwiftUI

/// App entry point. Sets up the SwiftData container and hosts `HomeView`.
@main
struct CueApp: App {
    /// Shared SwiftData container for the task store.
    let container: ModelContainer

    /// When the process is launched only to host the unit-test bundle, we skip the
    /// live UI and use an in-memory store so tests stay hermetic and don't touch
    /// disk. (Each test creates its own container.)
    private let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: isRunningTests)
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
                Color.clear
            } else {
                HomeView()
                    .tint(.cueAccent)
            }
        }
        .modelContainer(container)
    }
}
