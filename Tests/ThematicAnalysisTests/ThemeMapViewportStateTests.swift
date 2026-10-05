import CoreGraphics
import XCTest
@testable import ThematicAnalysis

final class ThemeMapViewportStateTests: XCTestCase {
    func testResizePreservesZoomAndVisibleCenter() async {
        await MainActor.run {
            let state = ThemeMapViewportState()
            state.fit(layoutSize: CGSize(width: 1_200, height: 800), in: CGSize(width: 1_000, height: 700))
            state.zoom = 0.73
            state.baseZoom = 0.73
            state.panOffset = CGSize(width: 40, height: -25)
            state.basePanOffset = state.panOffset

            state.preserveCenter(
                from: CGSize(width: 1_000, height: 700),
                to: CGSize(width: 640, height: 700)
            )

            XCTAssertEqual(state.zoom, 0.73, accuracy: 0.0001)
            XCTAssertEqual(state.baseZoom, 0.73, accuracy: 0.0001)
            XCTAssertEqual(state.panOffset.width, -140, accuracy: 0.0001)
            XCTAssertEqual(state.panOffset.height, -25, accuracy: 0.0001)
            XCTAssertEqual(state.basePanOffset, state.panOffset)
        }
    }

    func testExplicitFitUpdatesCamera() async {
        await MainActor.run {
            let state = ThemeMapViewportState()

            state.fit(layoutSize: CGSize(width: 900, height: 600), in: CGSize(width: 970, height: 670))

            XCTAssertEqual(state.zoom, 1, accuracy: 0.0001)
            XCTAssertEqual(state.baseZoom, 1, accuracy: 0.0001)
            XCTAssertEqual(state.panOffset, CGSize(width: 35, height: 35))
            XCTAssertTrue(state.hasInitialFit)
        }
    }
}
