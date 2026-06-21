import XCTest
@testable import Cue

/// Verifies the wire-format Codable models: decoding a representative `tool_use`
/// response, encoding a `tool_result`, and the request's snake_case keys.
final class APIModelsTests: XCTestCase {

    func testDecodesToolUseResponse() throws {
        let json = Data("""
        {
          "id": "msg_1",
          "type": "message",
          "role": "assistant",
          "model": "claude-sonnet-4-6",
          "stop_reason": "tool_use",
          "content": [
            { "type": "text", "text": "Sure, scheduling that." },
            { "type": "tool_use", "id": "toolu_1", "name": "create_task",
              "input": { "title": "Call Marko", "datetime": "2026-06-23T15:00:00" } }
          ]
        }
        """.utf8)

        let response = try JSONDecoder().decode(MessagesResponse.self, from: json)
        XCTAssertEqual(response.stopReason, "tool_use")
        XCTAssertEqual(response.content.count, 2)

        let tool = try XCTUnwrap(response.content.firstToolUse)
        XCTAssertEqual(tool.id, "toolu_1")
        XCTAssertEqual(tool.name, "create_task")
        XCTAssertEqual(tool.input["title"]?.stringValue, "Call Marko")
        XCTAssertEqual(tool.input["datetime"]?.stringValue, "2026-06-23T15:00:00")
    }

    func testDecodesUnknownBlockGracefully() throws {
        let json = Data("""
        { "id": "msg_2", "role": "assistant", "stop_reason": "end_turn",
          "content": [ { "type": "thinking", "thinking": "hmm" }, { "type": "text", "text": "Hi" } ] }
        """.utf8)
        let response = try JSONDecoder().decode(MessagesResponse.self, from: json)
        XCTAssertEqual(response.content.joinedText, "Hi")
        XCTAssertEqual(response.content.filter { $0.isKnown }.count, 1)
    }

    func testEncodesToolResult() throws {
        let message = APIMessage(role: "user",
                                 content: [.toolResult(toolUseID: "toolu_1",
                                                       content: "created task X",
                                                       isError: false)])
        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let content = try XCTUnwrap(object["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "tool_result")
        XCTAssertEqual(content.first?["tool_use_id"] as? String, "toolu_1")
        XCTAssertEqual(content.first?["content"] as? String, "created task X")
        XCTAssertEqual(content.first?["is_error"] as? Bool, false)
    }

    func testEncodesRequestWithSnakeCaseAndSchema() throws {
        let request = MessagesRequest(model: "claude-sonnet-4-6", maxTokens: 1024,
                                      system: "system prompt", messages: [],
                                      tools: ToolDefinitions.all)
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["max_tokens"] as? Int, 1024)
        XCTAssertEqual(object["model"] as? String, "claude-sonnet-4-6")

        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 4)
        XCTAssertEqual(tools.first?["name"] as? String, "create_task")
        XCTAssertNotNil(tools.first?["input_schema"])
    }

    func testDecodesErrorResponse() throws {
        let json = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad request"}}"#.utf8)
        let error = try JSONDecoder().decode(APIErrorResponse.self, from: json)
        XCTAssertEqual(error.error?.message, "bad request")
        XCTAssertEqual(error.error?.type, "invalid_request_error")
    }
}
