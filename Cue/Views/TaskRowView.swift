import SwiftUI

/// A single task row: leading completion toggle, title, and an optional datetime
/// pill. Completed tasks are struck through and dimmed.
struct TaskRowView: View {
    let task: TaskItem
    /// Toggles completion; owned by the parent so it can animate the list move.
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Button(action: onToggle) {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isComplete ? Color.cueAccent : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isComplete
                                ? "Completed: \(task.title). Mark as not done."
                                : "Not done: \(task.title). Mark as done.")
            .accessibilityAddTraits(task.isComplete ? [.isButton, .isSelected] : .isButton)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isComplete, color: .secondary)
                    .foregroundStyle(task.isComplete ? Color.secondary : Color.primary)

                if let datetime = task.datetime {
                    Text(DateParsing.friendly(datetime))
                        .font(.caption)
                        .foregroundStyle(task.isComplete ? Color.secondary : Color.cueAccent)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                (task.isComplete ? Color.secondary : Color.cueAccent).opacity(0.12))
                        )
                        .accessibilityLabel("Scheduled \(DateParsing.friendly(datetime))")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }
}

#Preview("Active") {
    List {
        TaskRowView(task: TaskItem(title: "Call with Marko",
                                   datetime: Date().addingTimeInterval(3 * 3600)),
                    onToggle: {})
        TaskRowView(task: TaskItem(title: "Buy groceries"), onToggle: {})
    }
}

#Preview("Completed") {
    List {
        TaskRowView(task: TaskItem(title: "Renew passport", isComplete: true),
                    onToggle: {})
    }
}
