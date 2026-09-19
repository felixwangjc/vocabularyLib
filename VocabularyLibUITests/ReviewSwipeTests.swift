import XCTest

final class ReviewSwipeTests: XCTestCase {
    @MainActor
    func testCheckInWallRemainsStableAfterScrolling() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["REVIEW_UI_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["UI_TEST_DARK"] = "1"
        app.launch()
        app.tabBars.buttons["徽章"].tap()
        let title = app.staticTexts["今日打卡完成"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let initialY = title.frame.minY
        let scroll = app.scrollViews.firstMatch
        let wallTitle = app.staticTexts["打卡墙 · 最近 30 天"]
        var previousY = wallTitle.frame.minY
        // Short drags cross the header/catalog boundary without returning to
        // the top. A correct final position alone cannot catch mid-scroll jumps.
        for _ in 0..<8 {
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.57)))
            let currentY = wallTitle.frame.minY
            XCTAssertLessThanOrEqual(currentY, previousY + 3, "Calendar moved backwards during upward scrolling")
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "打卡墙 · 最近 30 天")).count, 1)
            previousY = currentY
        }
        for _ in 0..<5 { scroll.swipeDown() }
        for _ in 0..<3 {
            scroll.swipeUp()
            scroll.swipeUp()
            for _ in 0..<5 { scroll.swipeDown() }
            XCTAssertTrue(title.isHittable)
            XCTAssertEqual(title.frame.minY, initialY, accuracy: 3)
            XCTAssertTrue(app.staticTexts["打卡墙 · 最近 30 天"].isHittable)
            XCTAssertTrue(app.descendants(matching: .any)["checkInDay-0"].isHittable)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Check-in wall after repeated scrolling"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testChineseSpellingExercise() { runObjectiveExercise(mode: "chineseSpelling", answer: "apple") }

    @MainActor
    func testListeningSpellingExercise() { runObjectiveExercise(mode: "listeningSpelling", answer: "apple") }

    @MainActor
    func testMissingLettersExercise() { runObjectiveExercise(mode: "missingLetters", answer: "pl") }

    @MainActor
    private func runObjectiveExercise(mode: String, answer: String) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["REVIEW_UI_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["EXERCISE_UI_TEST_MODE"] = mode
        app.launchEnvironment["READING_CONTEXT_UI_TEST"] = "1"
        if mode == "missingLetters" { app.launchEnvironment["UI_TEST_DARK"] = "1" }
        app.launch()
        openReview(app)
        let field = app.textFields["exerciseAnswer"]
        if mode == "missingLetters" {
            XCTAssertTrue(app.buttons["candidate-p"].waitForExistence(timeout: 5))
            XCTAssertFalse(field.exists)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "candidate-")).count, 10)
        } else { XCTAssertTrue(field.waitForExistence(timeout: 5)) }
        XCTAssertFalse(app.staticTexts["apple"].exists)
        let contexts = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "阅读语境")).firstMatch
        XCTAssertFalse(contexts.exists)
        if mode == "missingLetters" {
            for letter in answer { app.buttons["candidate-\(letter)"].tap() }
            XCTAssertEqual(app.buttons["missingSlot-0"].value as? String, "p")
            XCTAssertEqual(app.buttons["missingSlot-1"].value as? String, "l")
            assertLetterAlignment(app)
            app.buttons["missingSlot-0"].tap()
            app.buttons["清除当前格"].tap()
            XCTAssertFalse(app.buttons["exerciseCheck"].isEnabled)
            app.buttons["candidate-p"].tap()
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            let choicesShot = XCTAttachment(screenshot: app.screenshot())
            choicesShot.name = "Inline blanks and ten letter choices"
            choicesShot.lifetime = .keepAlways
            add(choicesShot)
            let check = app.buttons["exerciseCheck"]
            if !check.isHittable { app.swipeUp() }
            check.tap()
        } else {
            field.tap()
            field.typeText(answer + "\n")
        }
        XCTAssertTrue(app.staticTexts["回答正确"].waitForExistence(timeout: 5))
        if mode == "missingLetters" { assertLetterAlignment(app) }
        XCTAssertTrue(contexts.exists)
        let next = app.buttons["exerciseContinue"]
        if !next.isHittable { app.swipeUp() }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Exercise-\(mode)"
        shot.lifetime = .keepAlways
        add(shot)
        next.tap()
        XCTAssertTrue(app.staticTexts["今日已学 1 词"].waitForExistence(timeout: 5))
        if mode == "missingLetters" { XCTAssertTrue(app.buttons["missingSlot-0"].exists) }
        else { XCTAssertTrue(app.textFields["exerciseAnswer"].exists) }
    }

    @MainActor
    private func assertLetterAlignment(_ app: XCUIApplication) {
        let cells = [app.staticTexts["fixedLetter-0"], app.buttons["missingSlot-0"],
                     app.staticTexts["fixedLetter-2"], app.buttons["missingSlot-1"], app.staticTexts["fixedLetter-4"]]
        // AX reports tight glyph bounds for static Text, but the whole cell for a
        // Button. Compare vertical size only between blank cells of the same type.
        let aligned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(cells[1].frame.midY - cells[3].frame.midY) <= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [aligned], timeout: 5), .completed)
        let frames = cells.map(\.frame)
        let step = frames[1].midX - frames[0].midX
        for index in 1..<frames.count {
            XCTAssertEqual(frames[index].midX - frames[index - 1].midX, step, accuracy: 1)
        }
        XCTAssertEqual(frames[1].midY, frames[3].midY, accuracy: 1)
        XCTAssertEqual(frames[1].width, frames[3].width, accuracy: 1)
        XCTAssertEqual(frames[1].height, frames[3].height, accuracy: 1)
    }

    @MainActor
    func testWordSearchAndPlanSettings() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["REVIEW_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["单词本"].tap()
        let search = app.textFields["wordSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("apple")
        XCTAssertTrue(app.staticTexts["apple"].exists)
        XCTAssertFalse(app.staticTexts["book"].exists)
        app.buttons["清空搜索"].tap()
        search.typeText("\n")
        XCTAssertTrue(app.staticTexts["book"].exists)
        let searchShot = XCTAttachment(screenshot: app.screenshot())
        searchShot.name = "Word search and filters"
        searchShot.lifetime = .keepAlways
        add(searchShot)
        openReview(app)
        app.buttons["调整计划"].tap()
        let stepper = app.steppers["dailyNewWordLimit"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        stepper.buttons.firstMatch.tap()
        app.buttons["完成"].tap()
        app.buttons["调整计划"].tap()
        XCTAssertTrue(app.staticTexts["每天新词：9 个"].exists)
        let planShot = XCTAttachment(screenshot: app.screenshot())
        planShot.name = "Daily study plan settings"
        planShot.lifetime = .keepAlways
        add(planShot)
    }

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
        XCTAssertTrue(app.staticTexts["稍后继续重练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今日已学 3 词"].exists)

        // Relaunch the same isolated store: each answer is persisted exactly once.
        app.terminate()
        app.launch()
        openReview(app)
        XCTAssertTrue(app.staticTexts["稍后继续重练"].waitForExistence(timeout: 5))
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
