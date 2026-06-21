#if canImport(UIKit)
import UIKit
#endif

/// Thin wrapper over UIKit feedback generators, the one place the app touches
/// UIKit. Centralizing it keeps views and services UIKit-free. All methods are
/// `@MainActor` because feedback generators must be used on the main thread.
@MainActor
enum Haptics {
    /// Plays on a successful, committed action (confirm + execute).
    static func success() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    /// A soft tap for lightweight, reversible interactions (toggle, cancel).
    static func light() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    /// A selection tick for picker-like changes (e.g. dropping text back into the composer).
    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
