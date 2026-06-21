import SwiftData
import SwiftUI

/// App entry point. Sets up the SwiftData container and hosts `HomeView`.
@main
struct CueApp: App {
    /// Shared SwiftData container for the task store.
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: TaskItem.self)
        } catch {
            // A failed on-disk store shouldn't crash launch — fall back to an
            // in-memory store so the app still runs (data won't persist).
            do {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try ModelContainer(for: TaskItem.self, configurations: configuration)
            } catch {
                fatalError("Could not create a SwiftData ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(.cueAccent)
        }
        .modelContainer(container)
    }
}
