import SwiftUI

/// Central design tokens — the spacing scale, corner radii, and the single accent
/// color. Keeping these in one place enforces the restrained, consistent look the
/// spec calls for: one accent, generous whitespace, nothing competing.
enum Theme {
    /// The 4 / 8 / 12 / 16 / 24 / 32 spacing scale from the spec.
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// Standard screen horizontal padding.
        static let screen: CGFloat = 16
    }

    /// Continuous corner radii: 12 for cards, 16 for the composer and confirmation card.
    enum Radius {
        static let card: CGFloat = 12
        static let prominent: CGFloat = 16
    }
}

extension Color {
    /// The single calm indigo/violet accent, defined in the asset catalog with
    /// light + dark variants. Everything interactive uses this; nothing else competes.
    static let cueAccent = Color("AccentColor")
}
