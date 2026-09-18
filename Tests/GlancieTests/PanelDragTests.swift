import AppKit
import XCTest
@testable import Glancie

final class PanelDragTests: XCTestCase {
    func testFirstDragIncludesTravelSincePress() {
        let anchor = PanelDragAnchor(
            pointer: NSPoint(x: 130, y: 420),
            panelFrame: NSRect(x: 100, y: 400, width: 200, height: 40),
            barSize: NSSize(width: 200, height: 40), opensUpward: false, isPopoverOpen: false
        )
        XCTAssertEqual(anchor.origin(for: NSPoint(x: 140, y: 425)), NSPoint(x: 110, y: 405))
        XCTAssertEqual(anchor.origin(for: NSPoint(x: 141, y: 426)), NSPoint(x: 111, y: 406))
        XCTAssertEqual(anchor.origin(for: anchor.pointer), anchor.barOrigin)
    }

    func testClosedBarDoesNotJumpUpWhenCachedHeightIsStale() {
        // Initial hit-test band is shorter than the laid-out bar with shadow
        // padding and the cat. Starting a horizontal drag must preserve its Y.
        let actualFrame = NSRect(x: 100, y: 400, width: 260, height: 94)
        for opensUpward in [false, true] {
            let anchor = PanelDragAnchor(
                pointer: NSPoint(x: 150, y: 440), panelFrame: actualFrame,
                barSize: NSSize(width: 380, height: 58),
                opensUpward: opensUpward, isPopoverOpen: false
            )
            XCTAssertEqual(anchor.barFrame, actualFrame)
            XCTAssertEqual(anchor.origin(for: NSPoint(x: 160, y: 440)), NSPoint(x: 110, y: 400))
        }
    }

    func testClosingDownwardCardPreservesVisibleBarGrabPoint() {
        let anchor = PanelDragAnchor(
            pointer: NSPoint(x: 250, y: 580),
            panelFrame: NSRect(x: 100, y: 300, width: 400, height: 300),
            barSize: NSSize(width: 200, height: 40), opensUpward: false, isPopoverOpen: true
        )
        XCTAssertEqual(anchor.barOrigin, NSPoint(x: 200, y: 560))
        let origin = anchor.origin(for: NSPoint(x: 275, y: 570))
        XCTAssertEqual(origin, NSPoint(x: 225, y: 550))
        XCTAssertEqual(275 - origin.x, 250 - anchor.barOrigin.x)
        XCTAssertEqual(570 - origin.y, 580 - anchor.barOrigin.y)
    }

    func testUpwardCardAndNegativeDisplayCoordinates() {
        let anchor = PanelDragAnchor(
            pointer: NSPoint(x: -650, y: -180),
            panelFrame: NSRect(x: -800, y: -200, width: 400, height: 300),
            barSize: NSSize(width: 200, height: 40), opensUpward: true, isPopoverOpen: true
        )
        XCTAssertEqual(anchor.barOrigin, NSPoint(x: -700, y: -200))
        XCTAssertEqual(anchor.origin(for: NSPoint(x: -640, y: -160)), NSPoint(x: -690, y: -180))
    }
}
