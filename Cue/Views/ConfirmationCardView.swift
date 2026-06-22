import SwiftUI

/// The centerpiece: a card that animates up from above the composer when the
/// agent proposes an action. Shows the action verb, a plain-language summary,
/// parsed detail rows, and Confirm / Cancel. Delete uses destructive styling.
struct ConfirmationCardView: View {
    let action: PendingAction
    let onConfirm: () -> Void
    let onCancel: () -> Void
    /// Drops the request back into the composer for adjustment ("Edit" affordance).
    let onEdit: () -> Void

    private var accent: Color { action.isDestructive ? .red : .cueAccent }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            header
            details
            buttons
        }
        .padding(Theme.Spacing.l)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.prominent, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.prominent, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: action.verb.systemImage)
                .foregroundStyle(accent)
            Text(action.verb.title)
                .font(.headline)
                .foregroundStyle(action.isDestructive ? Color.red : Color.primary)
            Spacer()
            Button("Edit", action: onEdit)
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.cueAccent)
                .accessibilityHint("Puts this request back in the text field so you can adjust it")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            detailRow(icon: "textformat", text: action.summary)
            if let datetime = action.datetime {
                detailRow(
                    icon: "calendar",
                    text: DateParsing.friendlyFull(datetime)
                        + (action.datetimeWasDefaulted ? "  (defaulted to 9:00 AM — tap Edit to change)" : ""))
            }
            if let notes = action.notes, !notes.isEmpty {
                detailRow(icon: "note.text", text: notes)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(action: onCancel) {
                Text("Cancel").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("cancelAction")
            .accessibilityHint("Dismisses without changing anything")

            Button(action: onConfirm) {
                Text(action.isDestructive ? "Delete" : "Confirm").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(accent)
            .accessibilityIdentifier("confirmAction")
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}

#Preview("Add") {
    ConfirmationCardView(
        action: PendingAction(id: "1", toolName: "create_task", verb: .add,
                              summary: "Call with Marko", title: "Call with Marko",
                              datetime: Date().addingTimeInterval(3 * 3600),
                              datetimeWasDefaulted: false, notes: nil, rawInput: .object([:])),
        onConfirm: {}, onCancel: {}, onEdit: {})
    .padding()
}

#Preview("Delete") {
    ConfirmationCardView(
        action: PendingAction(id: "2", toolName: "delete_task", verb: .delete,
                              summary: "Finish the report", title: "Finish the report",
                              datetime: nil, datetimeWasDefaulted: false,
                              notes: nil, rawInput: .object([:])),
        onConfirm: {}, onCancel: {}, onEdit: {})
    .padding()
}
