import SwiftUI

/// Friendly, centered empty state shown when there are no tasks yet.
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "checklist")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(Color.cueAccent)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.s) {
                Text("Nothing yet")
                    .font(.headline)
                Text("Ask Cue below to add your first task.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nothing yet. Ask Cue below to add your first task.")
    }
}

#Preview {
    EmptyStateView()
        .background(Color(.systemGroupedBackground))
}
