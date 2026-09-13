import XCTest
import UIKit
@testable import VocabularyLib

final class ImageCropModelTests: XCTestCase {
    @MainActor
    func testSquareCropUsesVisibleCenterAndZoom() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 200, y: 0, width: 200, height: 300))
        }
        let model = ImageCropModel(image: source)
        model.setViewport(CGSize(width: 200, height: 200))

        let center = try XCTUnwrap(model.croppedImage()?.cgImage)
        XCTAssertEqual(CGFloat(center.width) / CGFloat(center.height), 1, accuracy: 0.01)
        XCTAssertEqual(CGFloat(center.width) / CGFloat(model.image.cgImage!.width), 0.75, accuracy: 0.01)

        model.magnify(2)
        model.finishMagnifying()
        let zoomed = try XCTUnwrap(model.croppedImage()?.cgImage)
        XCTAssertEqual(CGFloat(zoomed.width) / CGFloat(zoomed.height), 1, accuracy: 0.01)
        XCTAssertEqual(CGFloat(zoomed.width) / CGFloat(center.width), 0.5, accuracy: 0.01)
    }

    @MainActor
    func testDragIsClampedAndProducesValidPixels() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 400)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        }
        let model = ImageCropModel(image: source)
        model.setViewport(CGSize(width: 300, height: 400))
        model.drag(CGSize(width: 10_000, height: -10_000))
        model.finishDragging()

        XCTAssertLessThan(abs(model.offset.width), 10_000)
        XCTAssertEqual(model.offset.height, 0, accuracy: 0.01)
        let cropped = try XCTUnwrap(model.croppedImage()?.cgImage)
        XCTAssertEqual(CGFloat(cropped.width) / CGFloat(cropped.height), 0.75, accuracy: 0.01)
        XCTAssertEqual(cropped.height, model.image.cgImage!.height, accuracy: 1)
    }
}
