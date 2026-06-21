import Foundation

/// The user-facing verb for a proposed action, with display + styling metadata
/// for the confirmation card.
enum ActionVerb: String, Sendable {
    case add
    case update
    case reschedule
    case complete
    case delete

    var title: String {
        switch self {
        case .add: return "Add"
        case .update: return "Update"
        case .reschedule: return "Reschedule"
        case .complete: return "Complete"
        case .delete: return "Delete"
        }
    }

    /// Delete uses destructive (red) styling and copy.
    var isDestructive: Bool { self == .delete }

    var systemImage: String {
        switch self {
        case .add: return "plus.circle.fill"
        case .update: return "pencil.circle.fill"
        case .reschedule: return "calendar.badge.clock"
        case .complete: return "checkmark.circle.fill"
        case .delete: return "trash.fill"
        }
    }
}

/// A tool call the agent proposes, held pending the user's confirmation. Carries
/// both the human-readable summary (for the card) and the raw input (replayed
/// verbatim into `ToolExecutor` on confirm).
struct PendingAction: Identifiable, Equatable, Sendable {
    /// The Anthropic `tool_use` id; also the card's identity for matching/animation.
    let id: String
    let toolName: String
    let verb: ActionVerb
    /// One-line plain-language summary, e.g. "Call with Marko".
    let summary: String
    /// Parsed detail fields surfaced as read-only rows on the card.
    let title: String?
    let datetime: Date?
    /// `true` when the time was defaulted to 9:00 AM (date given without a time).
    let datetimeWasDefaulted: Bool
    let notes: String?
    /// Original tool input, replayed into `ToolExecutor` on confirm.
    let rawInput: JSONValue

    var isDestructive: Bool { verb.isDestructive }
}
