import SwiftUI

/// A single chat bubble — assistant lines lead from the left, the user's own
/// turns trail to the right. Errors get a soft red treatment.
struct AssistantBubbleView: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: Theme.Spacing.xxl) }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.isError ? Color.red : Color.primary)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .background(bubbleBackground)

            if !isUser { Spacer(minLength: Theme.Spacing.xxl) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isUser ? "You" : "Cue"): \(message.text)")
    }

    @ViewBuilder private var bubbleBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        if message.isError {
            shape.fill(Color.red.opacity(0.12))
        } else if isUser {
            shape.fill(Color.cueAccent.opacity(0.16))
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

/// Three pulsing dots shown near the composer while a request is in flight.
/// Honors Reduce Motion by holding the dots steady.
struct ThinkingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(animating ? 1.0 : 0.55)
                    .opacity(animating ? 1.0 : 0.4)
                    .animation(
                        reduceMotion ? nil
                        : .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.18),
                        value: animating)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(.regularMaterial))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { animating = true }
        .accessibilityLabel("Cue is thinking")
    }
}

#Preview("Bubbles") {
    VStack(spacing: 8) {
        AssistantBubbleView(message: .user("schedule a call with Marko next Tuesday at 3pm"))
        AssistantBubbleView(message: .assistant("You have two calls Tuesday — Marko or Ana?"))
        AssistantBubbleView(message: ChatMessage(role: .assistant,
                                                 text: "I couldn't reach the model — check your connection and try again.",
                                                 isError: true))
        ThinkingIndicator()
    }
    .padding()
}
