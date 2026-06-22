import XCTest

/// Drives the full §12 acceptance demo against the real agent (live API calls)
/// and captures a screenshot at each visual milestone. Run explicitly via the
/// dedicated scheme:
///
///   xcodebuild test -scheme CueUITests \
///     -destination 'platform=iOS Simulator,name=iPhone 17'
///
/// Not part of the default suite (it makes network calls). Each agent turn waits
/// generously for the model, and every proposed action is confirmed before the
/// next request so the conversation stays well-formed.
@MainActor
final class CueUITests: XCTestCase {
    private let app = XCUIApplication()
    private let turnTimeout: TimeInterval = 60

    override func setUp() {
        continueAfterFailure = true
    }

    func testFullDemo() {
        app.launch()
        screenshot("01-empty-state")

        step("schedule a call with Marko next Tuesday at 3pm",
             confirm: "02-confirm-add", result: "03-task-added")

        step("actually move it to Wednesday same time",
             confirm: "04-confirm-reschedule", result: "05-rescheduled")

        step("add buy groceries and finish the report by Friday",
             confirm: "06-confirm-multi", result: "08-tasks-added")

        step("mark the Marko call done",
             confirm: "09-confirm-complete", result: "10-completed")

        // Ambiguous / no target → the agent asks instead of acting (no card).
        waitUntilIdle()
        send("move my meeting to 4pm")
        settle(seconds: 8)
        screenshot("11-clarifying-question")
    }

    // MARK: - Step driver

    /// Sends a request, screenshots the first confirmation card, confirms every
    /// card the turn proposes (handles multi-action turns), then screenshots the
    /// settled result.
    private func step(_ text: String, confirm: String, result: String) {
        waitUntilIdle()
        send(text)
        if app.buttons["confirmAction"].waitForExistence(timeout: turnTimeout) {
            settle(seconds: 2)               // let the spring-in settle before the shot
            screenshot(confirm)
            var guardCount = 0
            repeat {
                tapConfirm()
                _ = app.buttons["confirmAction"].waitForNonExistence(timeout: 15)
                guardCount += 1
            } while app.buttons["confirmAction"].waitForExistence(timeout: 8) && guardCount < 5
        }
        waitUntilIdle()
        settle(seconds: 2)
        screenshot(result)
    }

    // MARK: - Helpers

    private func send(_ text: String) {
        let field = composer()
        XCTAssertTrue(field.waitForExistence(timeout: 15), "Composer not found")
        field.tap()
        field.typeText(text)
        let sendButton = app.buttons["composerSend"]
        if sendButton.waitForExistence(timeout: 5), sendButton.isEnabled { sendButton.tap() }
    }

    private func composer() -> XCUIElement {
        if app.textViews["composerField"].exists { return app.textViews["composerField"] }
        if app.textFields["composerField"].exists { return app.textFields["composerField"] }
        return app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
    }

    private func tapConfirm() {
        let button = app.buttons["confirmAction"]
        if button.exists { button.tap() }
    }

    /// Drains any pending confirmation cards so the next message can be sent into a
    /// clean state (the app refuses to send while a card is awaiting a decision).
    private func waitUntilIdle() {
        var guardCount = 0
        while app.buttons["confirmAction"].waitForExistence(timeout: 4), guardCount < 6 {
            tapConfirm()
            _ = app.buttons["confirmAction"].waitForNonExistence(timeout: 15)
            guardCount += 1
        }
    }

    private func settle(seconds: UInt32 = 3) { sleep(seconds) }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
