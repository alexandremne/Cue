import SwiftData
import XCTest
@testable import Cue

/// Verifies each of the four tools mutates the SwiftData store correctly.
@MainActor
final class ToolExecutorTests: XCTestCase {

    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-test-\(UUID().uuidString).store")
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(for: TaskItem.self, configurations: configuration)
        containers.append(container) // keep alive for the duration of the test
        return container.mainContext
    }

    func testCreateTaskInsertsTaskWithParsedDate() throws {
        let context = try makeContext()
        let executor = ToolExecutor(context: context)

        let outcome = try executor.execute(
            toolName: "create_task",
            input: ["title": "Call Marko", "datetime": "2026-06-23T15:00:00"])

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "Call Marko")
        XCTAssertNotNil(tasks.first?.datetime)
        XCTAssertFalse(tasks.first?.isComplete ?? true)
        XCTAssertTrue(outcome.contains("created task"))
    }

    func testCreateTaskWithoutDateLeavesDatetimeNil() throws {
        let context = try makeContext()
        let executor = ToolExecutor(context: context)

        _ = try executor.execute(toolName: "create_task", input: ["title": "Buy groceries"])

        let task = try context.fetch(FetchDescriptor<TaskItem>()).first
        XCTAssertEqual(task?.title, "Buy groceries")
        XCTAssertNil(task?.datetime)
    }

    func testCreateTaskRequiresTitle() throws {
        let context = try makeContext()
        let executor = ToolExecutor(context: context)
        XCTAssertThrowsError(
            try executor.execute(toolName: "create_task", input: ["notes": "no title here"]))
    }

    func testUpdateTaskReschedulesAndRetitles() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Old title")
        context.insert(task)
        try context.save()

        let executor = ToolExecutor(context: context)
        _ = try executor.execute(
            toolName: "update_task",
            input: ["task_id": .string(task.id.uuidString),
                    "title": "New title",
                    "datetime": "2026-07-01T09:00:00"])

        XCTAssertEqual(task.title, "New title")
        XCTAssertNotNil(task.datetime)
    }

    func testUpdateWithNoFieldsThrows() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Untouched")
        context.insert(task)
        try context.save()

        let executor = ToolExecutor(context: context)
        XCTAssertThrowsError(
            try executor.execute(toolName: "update_task",
                                 input: ["task_id": .string(task.id.uuidString)]))
    }

    func testCompleteTaskMarksComplete() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Do the thing")
        context.insert(task)
        try context.save()

        let executor = ToolExecutor(context: context)
        _ = try executor.execute(toolName: "complete_task",
                                 input: ["task_id": .string(task.id.uuidString)])

        XCTAssertTrue(task.isComplete)
    }

    func testDeleteTaskRemovesTask() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Remove me")
        context.insert(task)
        try context.save()

        let executor = ToolExecutor(context: context)
        _ = try executor.execute(toolName: "delete_task",
                                 input: ["task_id": .string(task.id.uuidString)])

        let remaining = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertTrue(remaining.isEmpty)
    }

    func testUnknownTaskIDThrows() throws {
        let context = try makeContext()
        let executor = ToolExecutor(context: context)
        XCTAssertThrowsError(
            try executor.execute(toolName: "complete_task",
                                 input: ["task_id": .string(UUID().uuidString)]))
    }

    func testUnknownToolThrows() throws {
        let context = try makeContext()
        let executor = ToolExecutor(context: context)
        XCTAssertThrowsError(try executor.execute(toolName: "frobnicate", input: ["x": "y"]))
    }
}
