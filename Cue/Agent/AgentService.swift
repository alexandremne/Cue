import Foundation
import Observation
import SwiftData

/// Orchestrates the conversational agent loop and owns the conversation state.
///
/// `@MainActor` + `@Observable` so SwiftUI binds directly to it. Networking runs
/// off the main actor inside the injected `AnthropicClient`. The store is reached
/// through a `ModelContext` (bound by the view) so the service can build the task
/// snapshot and apply confirmed actions via `ToolExecutor`.
@MainActor
@Observable
final class AgentService {
    /// Chat transcript surfaced in the UI (assistant lines, clarifying questions,
    /// the user's own turns, and inline errors).
    private(set) var messages: [ChatMessage] = []
    /// The action currently awaiting confirmation, if any. Drives the card.
    private(set) var pendingAction: PendingAction?
    /// `true` while a model request is in flight. Drives the thinking indicator and
    /// disables sending (so rapid sends are ignored).
    private(set) var isThinking = false

    /// The SwiftData context, bound by the view once the environment is available.
    @ObservationIgnored var modelContext: ModelContext?

    /// Running wire-format history sent to the model each turn.
    @ObservationIgnored private var wire: [APIMessage] = []
    /// Remaining proposed actions from the current assistant turn (a turn can
    /// propose several). The head is shown as `pendingAction`.
    @ObservationIgnored private var pendingQueue: [PendingAction] = []
    /// Accumulated `tool_result` blocks for the current turn; all are sent back
    /// together once every proposed action has been confirmed or cancelled.
    @ObservationIgnored private var pendingResults: [ContentBlock] = []
    @ObservationIgnored private let client: any AnthropicClient
    @ObservationIgnored private let configuration: AnthropicConfiguration

    init(client: any AnthropicClient, configuration: AnthropicConfiguration) {
        self.client = client
        self.configuration = configuration
    }

    /// Whether an API key is configured. The UI shows a setup hint when `false`.
    var isConfigured: Bool { configuration.hasAPIKey }

    // MARK: - Intents

    /// Submits a free-text user request. Ignored if empty/whitespace or while a
    /// request is already in flight.
    func submit(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ignore empty input, sends while a request is in flight, and — critically —
        // sends while an action is awaiting confirmation. Appending a new user turn
        // before the pending tool_use is answered would corrupt the wire history
        // (every tool_use must be followed by its tool_result).
        guard !trimmed.isEmpty, !isThinking, pendingAction == nil else { return }

        messages.append(.user(trimmed))
        wire.append(APIMessage(role: "user", content: [.text(trimmed)]))

        guard isConfigured else {
            appendError(APIError.missingAPIKey.errorDescription ?? "Missing API key.")
            return
        }
        await runTurn()
    }

    /// Confirms a pending action: executes it against the store and records the
    /// outcome. If more actions are queued from the same turn, the next is shown;
    /// otherwise all results are sent back and the model's closing line surfaces.
    func confirm(_ action: PendingAction) async {
        guard pendingAction == action else { return }
        Haptics.success()

        var outcome: String
        var isError = false
        if let modelContext {
            do {
                outcome = try ToolExecutor(context: modelContext)
                    .execute(toolName: action.toolName, input: action.rawInput)
            } catch {
                outcome = "The action could not be completed: \(error.localizedDescription)"
                isError = true
            }
        } else {
            outcome = "No data store is available."
            isError = true
        }

        pendingResults.append(.toolResult(toolUseID: action.id, content: outcome, isError: isError))
        await advancePending()
    }

    /// Cancels a pending action: records the decline. Advances to the next queued
    /// action, or sends all results back once the turn's actions are resolved.
    func cancel(_ action: PendingAction) async {
        guard pendingAction == action else { return }
        Haptics.light()
        pendingResults.append(.toolResult(toolUseID: action.id,
                                          content: "The user declined this action.",
                                          isError: false))
        await advancePending()
    }

    /// Clears the conversation thread and any pending action. Does not touch tasks.
    func clearConversation() {
        messages.removeAll()
        wire.removeAll()
        pendingQueue.removeAll()
        pendingResults.removeAll()
        pendingAction = nil
    }

    // MARK: - Loop

    private func runTurn() async {
        isThinking = true
        defer { isThinking = false }

        let tasks = currentTasks()
        let request = MessagesRequest(
            model: configuration.model,
            maxTokens: configuration.maxTokens,
            system: ToolDefinitions.systemPrompt(tasks: tasks),
            messages: wire,
            tools: ToolDefinitions.all
        )

        do {
            let response = try await client.send(request)
            // Echo the assistant turn into the wire history (known blocks only, so
            // we never send back an unknown/empty block the API would reject).
            wire.append(APIMessage(role: "assistant", content: response.content.filter { $0.isKnown }))

            // Surface any prose the model included (clarifying questions, lead-ins).
            let lead = response.content.joinedText
            if !lead.isEmpty { messages.append(.assistant(lead)) }

            let toolUses = response.content.allToolUses
            if toolUses.isEmpty {
                if lead.isEmpty { messages.append(.assistant("Done.")) }
            } else {
                pendingResults = []
                pendingQueue = toolUses.map { makePendingAction(from: $0, tasks: tasks) }
                pendingAction = pendingQueue.first
            }
        } catch {
            let message = (error as? APIError)?.errorDescription
                ?? "Something went wrong reaching the model. Please try again."
            appendError(message)
        }
    }

    /// Advances the per-turn action queue: shows the next proposed action, or —
    /// when all are resolved — sends every `tool_result` back in one message and
    /// asks the model for its closing line.
    private func advancePending() async {
        if !pendingQueue.isEmpty { pendingQueue.removeFirst() }
        if let next = pendingQueue.first {
            pendingAction = next
            return
        }
        pendingAction = nil
        guard !pendingResults.isEmpty else { return }
        wire.append(APIMessage(role: "user", content: pendingResults))
        pendingResults = []
        await runTurn()
    }

    private func appendError(_ text: String) {
        messages.append(ChatMessage(role: .assistant, text: text, isError: true))
    }

    private func currentTasks() -> [TaskItem] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Pending action construction

    /// Builds the confirmation-card payload from a `tool_use` block, parsing the
    /// details and resolving the target task (for update/complete/delete) so the
    /// card can show its title and current date.
    private func makePendingAction(from toolUse: (id: String, name: String, input: JSONValue),
                                   tasks: [TaskItem]) -> PendingAction {
        let input = toolUse.input
        switch toolUse.name {
        case "create_task":
            let title = input["title"]?.stringValue ?? "New task"
            let parsed = ToolExecutor.parseDatetime(input["datetime"])
            return PendingAction(
                id: toolUse.id, toolName: toolUse.name, verb: .add,
                summary: title, title: title,
                datetime: parsed?.date, datetimeWasDefaulted: parsed?.wasDefaulted ?? false,
                notes: input["notes"]?.stringValue, rawInput: input)

        case "update_task":
            let target = resolveTask(input, in: tasks)
            let newTitle = input["title"]?.stringValue
            let parsed = ToolExecutor.parseDatetime(input["datetime"])
            let verb: ActionVerb = parsed != nil ? .reschedule : .update
            return PendingAction(
                id: toolUse.id, toolName: toolUse.name, verb: verb,
                summary: newTitle ?? target?.title ?? "this task",
                title: newTitle ?? target?.title,
                datetime: parsed?.date ?? target?.datetime,
                datetimeWasDefaulted: parsed?.wasDefaulted ?? false,
                notes: input["notes"]?.stringValue ?? target?.notes, rawInput: input)

        case "complete_task":
            let target = resolveTask(input, in: tasks)
            return PendingAction(
                id: toolUse.id, toolName: toolUse.name, verb: .complete,
                summary: target?.title ?? "this task", title: target?.title,
                datetime: target?.datetime, datetimeWasDefaulted: false,
                notes: target?.notes, rawInput: input)

        case "delete_task":
            let target = resolveTask(input, in: tasks)
            return PendingAction(
                id: toolUse.id, toolName: toolUse.name, verb: .delete,
                summary: target?.title ?? "this task", title: target?.title,
                datetime: target?.datetime, datetimeWasDefaulted: false,
                notes: target?.notes, rawInput: input)

        default:
            return PendingAction(
                id: toolUse.id, toolName: toolUse.name, verb: .update,
                summary: "this task", title: nil, datetime: nil,
                datetimeWasDefaulted: false, notes: nil, rawInput: input)
        }
    }

    private func resolveTask(_ input: JSONValue, in tasks: [TaskItem]) -> TaskItem? {
        guard let idString = input["task_id"]?.stringValue,
              let uuid = UUID(uuidString: idString) else { return nil }
        return tasks.first { $0.id == uuid }
    }
}

#if DEBUG
extension AgentService {
    /// Seeds conversation state for SwiftUI previews (the stored properties are
    /// `private(set)`, so previews go through this DEBUG-only hook).
    func previewSeed(messages: [ChatMessage] = [],
                     pendingAction: PendingAction? = nil,
                     isThinking: Bool = false) {
        self.messages = messages
        self.pendingAction = pendingAction
        self.isThinking = isThinking
    }
}
#endif
