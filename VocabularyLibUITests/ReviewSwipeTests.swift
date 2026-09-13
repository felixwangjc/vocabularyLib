import XCTest

final class ReviewSwipeTests: XCTestCase {
    @MainActor
    func testSwipeDirectionsCancellationAndPersistence() throws {
        XCUIDevice.shared.orientation = .portrait
        try runReviewScenario()
    }

    @MainActor
    func testLandscapeReview() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        try runReviewScenario()
    }

    @MainActor
    private func runReviewScenario() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["REVIEW_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        openReview(app)

        let card = app.otherElements["reviewSwipeCard"].firstMatch
        XCTAssertTrue(app.staticTexts["apple"].waitForExistence(timeout: 5))
        XCTAssertTrue(card.exists)
        let originalFrame = card.frame

        // A short horizontal drag must spring back without recording an answer.
        drag(card, from: CGVector(dx: 0.5, dy: 0.35), to: CGVector(dx: 0.6, dy: 0.35))
        XCTAssertTrue(app.staticTexts["待学习 3"].exists)
        XCTAssertEqual(card.frame.midX, originalFrame.midX, accuracy: 3)

        // Vertical reading/scrolling must not become a review answer.
        drag(card, from: CGVector(dx: 0.5, dy: 0.7), to: CGVector(dx: 0.5, dy: 0.35))
        XCTAssertTrue(app.staticTexts["待学习 3"].exists)

        drag(card, from: CGVector(dx: 0.85, dy: 0.35), to: CGVector(dx: 0.15, dy: 0.35))
        XCTAssertTrue(app.staticTexts["book"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["待学习 2"].exists)

        app.buttons["查看释义与发音"].tap()
        XCTAssertTrue(app.buttons["播放发音"].exists)
        XCTAssertTrue(app.staticTexts["名词 · n."].exists)
        XCTAssertTrue(app.staticTexts["动词 · v."].exists)
        // The revealed answer supports the same gesture, including its audio control.
        drag(card, from: CGVector(dx: 0.15, dy: 0.3), to: CGVector(dx: 0.85, dy: 0.3))
        XCTAssertTrue(app.staticTexts["cloud"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["待学习 1"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Swipe review card"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["reviewRemembered"].tap()
        XCTAssertTrue(app.staticTexts["当前学习任务已完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今日已学 3 词"].exists)

        // Relaunch the same isolated store: each answer is persisted exactly once.
        app.terminate()
        app.launch()
        openReview(app)
        XCTAssertTrue(app.staticTexts["当前学习任务已完成"].waitForExistence(timeout: 5))
        if app.buttons["完成"].exists { app.buttons["完成"].tap() }
        if app.tabBars.buttons["单词本"].exists {
            app.tabBars.buttons["单词本"].tap()
        } else if app.buttons["单词本"].firstMatch.exists {
            app.buttons["单词本"].firstMatch.tap()
        }
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "熟悉 · 已复习 1 次")).count, 2)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "不认识 · 已复习 1 次")).count, 1)
    }

    @MainActor
    private func openReview(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["每日复习"]
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
        } else {
            app.buttons["每日复习"].firstMatch.tap()
        }
    }

    @MainActor
    private func drag(_ card: XCUIElement, from: CGVector, to: CGVector) {
        let app = XCUIApplication()
        let frame = card.frame
        var visible = frame.intersection(app.windows.firstMatch.frame)
        let nav = app.navigationBars.firstMatch
        let top = nav.exists ? nav.frame.maxY + 8 : visible.minY
        let tabs = app.tabBars.firstMatch
        let bottom = tabs.exists ? tabs.frame.minY - 8 : visible.maxY - 16
        visible = visible.intersection(CGRect(x: visible.minX, y: top, width: visible.width, height: max(0, bottom - top)))
        XCTAssertGreaterThan(visible.height, 30)
        let origin = card.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.width * from.dx, dy: visible.minY - frame.minY + visible.height * from.dy))
        let end = origin.withOffset(CGVector(dx: frame.width * to.dx, dy: visible.minY - frame.minY + visible.height * to.dy))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
