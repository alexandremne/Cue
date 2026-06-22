import XCTest
@testable import Cue

/// Live, end-to-end check against the real Anthropic Messages API.
///
/// Skipped unless `CUE_LIVE=1` is set in the test environment, so the normal test
/// suite never makes a network call or spends tokens. When enabled it verifies the
/// whole networking path with the configured key: headers, request shape, and
/// decoding a real `tool_use` response into the agent's tool contract.
final class AgentLiveTests: XCTestCase {
    func testLiveCreateTaskToolCall() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CUE_LIVE"] == "1",
                          "Set CUE_LIVE=1 to run the live API test.")

        let configuration = AppConfig.configuration
        try XCTSkipUnless(configuration.hasAPIKey,
                          "No API key configured (Config/Secrets.xcconfig).")

        let client = URLSessionAnthropicClient(configuration: configuration)
        let request = MessagesRequest(
            model: configuration.model,
            maxTokens: configuration.maxTokens,
            system: ToolDefinitions.systemPrompt(tasks: []),
            messages: [APIMessage(role: "user",
                                  content: [.text("schedule a call with Marko next Tuesday at 3pm")])],
            tools: ToolDefinitions.all)

        let response = try await client.send(request)

        let tool = try XCTUnwrap(response.content.firstToolUse,
                                 "Expected a tool_use. stop_reason=\(response.stopReason ?? "nil"), "
                                 + "text=\(response.content.joinedText)")
        XCTAssertEqual(tool.name, "create_task")
        XCTAssertNotNil(tool.input["title"]?.stringValue,
                        "create_task should include a title; got \(tool.input)")
    }
}
