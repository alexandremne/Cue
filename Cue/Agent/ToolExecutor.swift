import Foundation
import SwiftData

/// Applies the agent's confirmed tool calls to the SwiftData store.
///
/// `@MainActor` because it mutates the model context, which must happen on the
/// main actor. Each method returns a short outcome string that is sent back to
/// the model as a `tool_result` so it can produce a natural confirmation line.
@MainActor
struct ToolExecutor {
    let context: ModelContext

    /// Failures that must not mutate the store; surfaced gracefully so the user
    /// can rephrase and the agent can recover.
    enum ExecutionError: LocalizedError, Equatable {
        case missingTitle
        case missingTaskID
        case taskNotFound(String)
        case noFieldsToUpdate
        case unknownTool(String)

        var errorDescription: String? {
            switch self {
            case .missingTitle: return "A title is required to create a task."
            case .missingTaskID: return "No task was specified."
            case .taskNotFound: return "I couldn't find that task — it may have changed."
            case .noFieldsToUpdate: return "There was nothing to change."
            case .unknownTool(let name): return "Unsupported action: \(name)."
            }
        }
    }

    /// Executes a tool by name with the model-provided input. Throws on malformed
    /// input or a missing target so nothing is mutated on error.
    @discardableResult
    func execute(toolName: String, input: JSONValue) throws -> String {
        switch toolName {
        case "create_task": return try create(input)
        case "update_task": return try update(input)
        case "complete_task": return try complete(input)
        case "delete_task": return try delete(input)
        default: throw ExecutionError.unknownTool(toolName)
        }
    }

    // MARK: - Tools

    private func create(_ input: JSONValue) throws -> String {
        guard let title = input["title"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw ExecutionError.missingTitle
        }
        let parsed = ToolExecutor.parseDatetime(input["datetime"])
        let notes = input["notes"]?.stringValue
        let task = TaskItem(title: title, datetime: parsed?.date, notes: notes)
        context.insert(task)
        try save()
        return "created task \(task.id.uuidString) titled \"\(title)\""
    }

    private func update(_ input: JSONValue) throws -> String {
        let task = try findTask(input)
        var changed = false
        if let title = input["title"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            task.title = title
            changed = true
        }
        if let parsed = ToolExecutor.parseDatetime(input["datetime"]) {
            task.datetime = parsed.date
            changed = true
        }
        if let notes = input["notes"]?.stringValue {
            task.notes = notes
            changed = true
        }
        guard changed else { throw ExecutionError.noFieldsToUpdate }
        try save()
        return "updated task \(task.id.uuidString)"
    }

    private func complete(_ input: JSONValue) throws -> String {
        let task = try findTask(input)
        task.isComplete = true
        try save()
        return "completed task \(task.id.uuidString) (\"\(task.title)\")"
    }

    private func delete(_ input: JSONValue) throws -> String {
        let task = try findTask(input)
        let id = task.id.uuidString
        let title = task.title
        context.delete(task)
        try save()
        return "deleted task \(id) (\"\(title)\")"
    }

    // MARK: - Helpers

    private func findTask(_ input: JSONValue) throws -> TaskItem {
        guard let idString = input["task_id"]?.stringValue, !idString.isEmpty else {
            throw ExecutionError.missingTaskID
        }
        guard let uuid = UUID(uuidString: idString) else {
            throw ExecutionError.taskNotFound(idString)
        }
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == uuid })
        guard let task = try context.fetch(descriptor).first else {
            throw ExecutionError.taskNotFound(idString)
        }
        return task
    }

    private func save() throws {
        if context.hasChanges { try context.save() }
    }

    /// Parses a datetime tool argument into a `Date`, applying the 9:00 AM default
    /// for date-only values. Returns `nil` for absent, blank, or `null` input.
    static func parseDatetime(_ value: JSONValue?) -> (date: Date, wasDefaulted: Bool)? {
        guard let value else { return nil }
        if case .null = value { return nil }
        guard let raw = value.stringValue,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let parsed = DateParsing.parse(raw) else { return nil }
        return (parsed.date, parsed.timeWasDefaulted)
    }
}
