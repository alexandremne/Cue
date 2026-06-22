#if DEBUG
import Foundation
import SwiftData

/// A scripted `AnthropicClient` for SwiftUI previews — never makes a network call.
struct MockAnthropicClient: AnthropicClient {
    enum Behavior: Sendable {
        case text(String)
        case toolUse(name: String, input: JSONValue)
        case failure(APIError)
    }

    var behavior: Behavior = .text("Done.")

    func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        switch behavior {
        case .text(let text):
            return MessagesResponse(id: "msg_preview", role: "assistant", model: request.model,
                                    stopReason: "end_turn", content: [.text(text)])
        case .toolUse(let name, let input):
            return MessagesResponse(id: "msg_preview", role: "assistant", model: request.model,
                                    stopReason: "tool_use",
                                    content: [.toolUse(id: "toolu_preview", name: name, input: input)])
        case .failure(let error):
            throw error
        }
    }
}

extension AgentService {
    /// A preview-configured service backed by the mock client.
    static func previewService(behavior: MockAnthropicClient.Behavior = .text("Done.")) -> AgentService {
        AgentService(client: MockAnthropicClient(behavior: behavior),
                     configuration: AnthropicConfiguration(apiKey: "preview-key"))
    }
}

/// In-memory SwiftData containers + sample tasks for previews.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        context.insert(TaskItem(title: "Call with Marko",
                                datetime: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: Date())))
        context.insert(TaskItem(title: "Finish the report",
                                datetime: calendar.date(byAdding: .day, value: 3, to: Date())))
        context.insert(TaskItem(title: "Buy groceries"))
        context.insert(TaskItem(title: "Renew passport", isComplete: true))
        return container
    }()

    static let emptyContainer: ModelContainer = { makeContainer() }()

    private static func makeContainer() -> ModelContainer {
        // A unique temp on-disk store per preview keeps each preview isolated and
        // avoids a SwiftData in-memory-store quirk where save() can trap.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-preview-\(UUID().uuidString).store")
        let configuration = ModelConfiguration(url: url)
        do {
            return try ModelContainer(for: TaskItem.self, configurations: configuration)
        } catch {
            fatalError("Failed to build preview ModelContainer: \(error)")
        }
    }
}
#endif
