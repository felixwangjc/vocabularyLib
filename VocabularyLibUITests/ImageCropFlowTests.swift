import XCTest

final class ImageCropFlowTests: XCTestCase {
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
