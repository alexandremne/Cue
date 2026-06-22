import SwiftUI

/// The pinned bottom composer: a multiline-capable text field plus a filled
/// accent send button. Disabled when empty or while a request is in flight.
struct ComposerView: View {
    @Binding var text: String
    /// `true` while a request is in flight; disables sending.
    let isSending: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
            TextField("Ask Cue to add, change, or complete anything…",
                      text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.leading, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s + 2)
                .accessibilityLabel("Message Cue")
                .accessibilityIdentifier("composerField")

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(canSend ? Color.cueAccent : Color.secondary.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .padding(.trailing, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xs)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("composerSend")
        }
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.prominent, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.prominent, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private func send() {
        guard canSend else { return }
        onSend()
    }
}

#Preview("Empty") {
    StatefulPreviewWrapper("") { ComposerView(text: $0, isSending: false, onSend: {}) }
        .padding()
}

#Preview("With text") {
    StatefulPreviewWrapper("move it to Wednesday same time") {
        ComposerView(text: $0, isSending: false, onSend: {})
    }
    .padding()
}

#if DEBUG
/// Small helper so previews can drive a `@Binding`.
private struct StatefulPreviewWrapper<Content: View>: View {
    @State private var value: String
    private let content: (Binding<String>) -> Content

    init(_ initial: String, @ViewBuilder content: @escaping (Binding<String>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }
    var body: some View { content($value) }
}
#endif
