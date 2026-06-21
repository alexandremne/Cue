import Foundation

/// The four agent tools (function-calling schemas) plus the system-prompt builder.
///
/// Tool descriptions are written *for the model* and kept close to the spec. The
/// system prompt carries the agent's role + rules, the current date/time/timezone,
/// and a compact JSON snapshot of all tasks so the model can resolve references
/// and relative dates.
enum ToolDefinitions {
    /// All four tools, in the order they're offered to the model.
    static let all: [ToolDefinition] = [createTask, updateTask, completeTask, deleteTask]

    static let createTask = ToolDefinition(
        name: "create_task",
        description: "Create a new task. Use when the user wants to add something to their list.",
        inputSchema: [
            "type": "object",
            "properties": [
                "title": [
                    "type": "string",
                    "description": "Short imperative title for the task, e.g. \"Call with Marko\"."
                ],
                "datetime": [
                    "type": "string",
                    "description": "ISO 8601 local datetime, e.g. 2026-06-23T15:00:00. Omit entirely if the user gave no date. If a date is given without a time, return only the date as YYYY-MM-DD."
                ],
                "notes": [
                    "type": "string",
                    "description": "Optional free-form notes."
                ]
            ],
            "required": ["title"]
        ]
    )

    static let updateTask = ToolDefinition(
        name: "update_task",
        description: "Edit an existing task. Covers rescheduling and retitling. Provide at least one of title, datetime, or notes.",
        inputSchema: [
            "type": "object",
            "properties": [
                "task_id": [
                    "type": "string",
                    "description": "The id of the task to edit, taken from the provided task snapshot. Never invent an id."
                ],
                "title": [
                    "type": "string",
                    "description": "New title for the task."
                ],
                "datetime": [
                    "type": "string",
                    "description": "New ISO 8601 local datetime, or just the date as YYYY-MM-DD if no time was given."
                ],
                "notes": [
                    "type": "string",
                    "description": "New notes for the task."
                ]
            ],
            "required": ["task_id"]
        ]
    )

    static let completeTask = ToolDefinition(
        name: "complete_task",
        description: "Mark an existing task as complete.",
        inputSchema: [
            "type": "object",
            "properties": [
                "task_id": [
                    "type": "string",
                    "description": "The id of the task to complete, from the task snapshot. Never invent an id."
                ]
            ],
            "required": ["task_id"]
        ]
    )

    static let deleteTask = ToolDefinition(
        name: "delete_task",
        description: "Delete an existing task permanently.",
        inputSchema: [
            "type": "object",
            "properties": [
                "task_id": [
                    "type": "string",
                    "description": "The id of the task to delete, from the task snapshot. Never invent an id."
                ]
            ],
            "required": ["task_id"]
        ]
    )
}

extension ToolDefinitions {
    /// Builds the system prompt: role + rules, current date/time/timezone, and a
    /// compact JSON snapshot of all tasks (id, title, datetime, status).
    static func systemPrompt(tasks: [TaskItem],
                             now: Date = Date(),
                             timeZone: TimeZone = .current) -> String {
        let nowISO = DateParsing.iso(from: now, timeZone: timeZone)
        let snapshot = tasksSnapshot(tasks, timeZone: timeZone)
        return """
        You are Cue, a calm, precise in-app assistant that manages the user's tasks by calling tools.

        Current context:
        - Current date and time (ISO 8601): \(nowISO)
        - Timezone: \(timeZone.identifier)

        Tasks snapshot — a JSON array of the user's current tasks:
        \(snapshot)

        How to behave:
        - When the user wants to add, change, complete, or delete a task, call exactly one of the provided tools. Prefer a single tool call per turn; only make multiple calls if the user clearly asked for several actions at once.
        - For update_task, complete_task, and delete_task, the task_id MUST be one of the ids in the snapshot above. Never invent an id.
        - Map natural references (e.g. "the Marko call") to a task id using the snapshot. If no task matches, say so plainly. If more than one task plausibly matches, DO NOT guess — ask one short clarifying question naming the options (e.g. "You have two calls Tuesday — Marko or Ana?").
        - Resolve relative dates ("tomorrow", "next Tuesday at 3") to absolute ISO 8601 datetimes using the current date/time above. If the user gives a date but no time, return just the date as YYYY-MM-DD; the app defaults it to 9:00 AM and lets the user adjust.
        - If a request is ambiguous or missing a key detail, ask one concise clarifying question instead of calling a tool.
        - If no action is needed, reply briefly and conversationally.
        - After a tool runs you'll receive a tool_result. Reply with one short, natural confirmation line, e.g. "Done — added 'Call with Marko' for Tue 3:00 PM." If the user declined, acknowledge briefly.
        - Keep every reply short and free of preamble. Never mention tool names, ids, or JSON to the user.
        """
    }

    /// Compact JSON snapshot of the tasks (id, title, datetime, status). Datetime
    /// is an ISO 8601 local string or `null`.
    static func tasksSnapshot(_ tasks: [TaskItem], timeZone: TimeZone = .current) -> String {
        let objects: [JSONValue] = tasks.map { task in
            var fields: [String: JSONValue] = [
                "id": .string(task.id.uuidString),
                "title": .string(task.title),
                "status": .string(task.isComplete ? "completed" : "active")
            ]
            if let datetime = task.datetime {
                fields["datetime"] = .string(DateParsing.iso(from: datetime, timeZone: timeZone))
            } else {
                fields["datetime"] = .null
            }
            return .object(fields)
        }
        return compactJSON(.array(objects))
    }

    private static func compactJSON(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}
