import XCTest

final class ImageCropFlowTests: XCTestCase {
    @MainActor
    func testOCRSavesContextForExistingWordAndEditsNotes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OCR_CROP_UI_TEST"] = "1"
        app.launchEnvironment["REVIEW_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        let word = app.descendants(matching: .any).matching(identifier: "ocrWord-apple").firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 15))
        word.press(forDuration: 2.3)
        let contexts = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "阅读语境")).firstMatch
        for _ in 0..<5 {
            if contexts.exists && contexts.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(contexts.exists)
        contexts.tap()
        let edit = app.buttons["editReadingContext"].firstMatch
        for _ in 0..<4 {
            if edit.isHittable { break }
            app.swipeUp()
        }
        edit.tap()
        let book = app.textFields["sourceBookTitle"]
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        book.tap(); book.typeText("My Reader")
        app.textFields["sourcePage"].tap(); app.textFields["sourcePage"].typeText("12")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["My Reader · 第 12 页"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "OCR reading context"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testCropAndRestoreOriginalImage() {
        let app = XCUIApplication()
        app.launchEnvironment["OCR_CROP_UI_TEST"] = "1"
        app.launch()

        let cropMenu = app.buttons["ocrCropMenu"]
        XCTAssertTrue(cropMenu.waitForExistence(timeout: 10))
        cropMenu.tap()
        app.buttons["裁剪识别区域"].tap()

        let canvas = app.otherElements["cropCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        app.segmentedControls.buttons["1:1"].tap()
        canvas.pinch(withScale: 1.6, velocity: 1)
        canvas.swipeLeft()
        app.buttons["使用此区域"].tap()

        XCTAssertTrue(cropMenu.waitForExistence(timeout: 5))
        cropMenu.tap()
        let restore = app.buttons["恢复原图"]
        XCTAssertTrue(restore.exists)
        XCTAssertTrue(restore.isEnabled)
        restore.tap()
        XCTAssertTrue(cropMenu.waitForExistence(timeout: 5))
    }
}
