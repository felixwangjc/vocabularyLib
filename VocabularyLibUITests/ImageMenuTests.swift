import XCTest

final class ImageMenuTests: XCTestCase {
    @MainActor
    func testMenuOpensClosesAndRemainsAnchored() throws {
        let app = XCUIApplication()
        app.launch()
        let trigger = app.buttons["imageRecognitionTrigger"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 10))
        let triggerFrame = trigger.frame
        trigger.tap()
        let camera = app.buttons["拍照"]
        XCTAssertTrue(camera.waitForExistence(timeout: 3))
        XCTAssertTrue(camera.isHittable)
        XCTAssertTrue(app.buttons["粘贴"].isHittable)
        XCTAssertTrue(app.buttons["导入"].isHittable)
        let close = app.buttons["收起图片识词菜单"]
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(close.frame.midX, triggerFrame.midX, accuracy: 3)
        XCTAssertEqual(close.frame.midY, triggerFrame.midY, accuracy: 3)
        let paste = app.buttons["粘贴"]
        let importImage = app.buttons["导入"]
        XCTAssertFalse(camera.frame.intersects(paste.frame))
        XCTAssertFalse(paste.frame.intersects(importImage.frame))
        for button in [camera, paste, importImage] {
            XCTAssertLessThan(hypot(button.frame.midX - close.frame.midX, button.frame.midY - close.frame.midY), 125)
        }
        close.tap()
        XCTAssertTrue(camera.waitForNonExistence(timeout: 3))
        trigger.tap()
        XCTAssertTrue(camera.waitForExistence(timeout: 3))
        app.buttons["导入"].tap()
        XCTAssertTrue(app.buttons["从文件导入"].waitForExistence(timeout: 3))
    }
}
