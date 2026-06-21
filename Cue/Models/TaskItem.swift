import Foundation
import SwiftData

/// A single task / agenda item, persisted with SwiftData.
///
/// Named `TaskItem` rather than `Task` deliberately: a module-level type called
/// `Task` would shadow Swift Concurrency's `Task`, breaking every `Task { … }`
/// in the app. The spec's field set is preserved exactly.
@Model
final class TaskItem {
    /// Stable identifier surfaced to the agent in the task snapshot and used to
    /// target the update / complete / delete tools.
    var id: UUID
    var title: String
    /// `nil` means the task has no scheduled time.
    var datetime: Date?
    var notes: String?
    var isComplete: Bool
    var createdAt: Date

    init(id: UUID = UUID(),
         title: String,
         datetime: Date? = nil,
         notes: String? = nil,
         isComplete: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.datetime = datetime
        self.notes = notes
        self.isComplete = isComplete
        self.createdAt = createdAt
    }
}
