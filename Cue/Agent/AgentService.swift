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
        guard !trimmed.isEmpty, !isThinking else { return }

        messages.append(.user(trimmed))
        wire.append(APIMessage(role: "user", content: [.text(trimmed)]))

        guard isConfigured else {
            appendError(APIError.missingAPIKey.errorDescription ?? "Missing API key.")
            return
        }
        await runTurn()
    }

    /// Confirms a pending action: executes it against the store, reports the
    /// outcome to the model, and surfaces the model's closing line.
    func confirm(_ action: PendingAction) async {
        guard pendingAction == action else { return }
        pendingAction = nil
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

        wire.append(APIMessage(role: "user",
                               content: [.toolResult(toolUseID: action.id,
                                                     content: outcome,
                                                     isError: isError)]))
        await runTurn()
    }

    /// Cancels a pending action: tells the model the user declined and surfaces
    /// the acknowledgement.
    func cancel(_ action: PendingAction) async {
        guard pendingAction == action else { return }
        pendingAction = nil
        Haptics.light()
        wire.append(APIMessage(role: "user",
                               content: [.toolResult(toolUseID: action.id,
                                                     content: "The user declined this action.",
                                                     isError: false)]))
        await runTurn()
    }

    /// Clears the conversation thread and any pending action. Does not touch tasks.
    func clearConversation() {
        messages.removeAll()
        wire.removeAll()
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

            if let toolUse = response.content.firstToolUse {
                let lead = response.content.joinedText
                if !lead.isEmpty { messages.append(.assistant(lead)) }
                pendingAction = makePendingAction(from: toolUse, tasks: tasks)
            } else {
                let text = response.content.joinedText
                messages.append(.assistant(text.isEmpty ? "Done." : text))
            }
        } catch {
            let message = (error as? APIError)?.errorDescription
                ?? "Something went wrong reaching the model. Please try again."
            appendError(message)
        }
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
