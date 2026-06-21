import Foundation

/// A non-persisted conversation message that drives the chat UI. Distinct from
/// the persisted `TaskItem` and from the wire-format `APIMessage`.
struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable { case user, assistant }

    let id: UUID
    let role: Role
    var text: String
    /// Optional awaiting-confirmation payload, per the spec's data model. The live
    /// confirmation card is driven by `AgentService.pendingAction`; this field keeps
    /// the value type spec-complete and is available for richer transcripts.
    var pendingAction: PendingAction?
    let timestamp: Date
    /// Marks an inline error message so the UI can style it distinctly.
    var isError: Bool

    init(role: Role,
         text: String,
         pendingAction: PendingAction? = nil,
         timestamp: Date = Date(),
         isError: Bool = false) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.pendingAction = pendingAction
        self.timestamp = timestamp
        self.isError = isError
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text)
    }
    static func assistant(_ text: String) -> ChatMessage {
        ChatMessage(role: .assistant, text: text)
    }
}
