import AppKit
import XCTest
@testable import Glancie

/// The rules that decide where a re-measured bar lands. Pure geometry, so the
/// launch behaviour is pinned without a window on screen.
final class PanelPlacementTests: XCTestCase {

    // MARK: - Re-anchoring during a session

    func testCentrePinKeepsTheBarBreathingAroundItsOwnCentre() {
        let anchor = NSRect(x: 748, y: 997, width: 351, height: 94)
        let grown = PanelReanchor.frame(
            anchor: anchor, size: NSSize(width: 422, height: 94),
            opensUpward: false, horizontal: .center
        )
        XCTAssertEqual(grown.midX, anchor.midX, accuracy: 0.5)
        XCTAssertEqual(grown.maxY, anchor.maxY, "downward card: the bar's top edge stays")
    }

    func testCentrePinKeepsTheBottomEdgeWhenTheCardOpensUpward() {
        let anchor = NSRect(x: 100, y: 40, width: 280, height: 94)
        let grown = PanelReanchor.frame(
            anchor: anchor, size: NSSize(width: 351, height: 94),
            opensUpward: true, horizontal: .center
        )
        XCTAssertEqual(grown.minY, anchor.minY)
        XCTAssertEqual(grown.midX, anchor.midX, accuracy: 0.5)
    }

    /// Re-centring around the window's *guessed* starting width is what used to
    /// shove the bar sideways at launch: half the guess's error, every time.
    func testLeadingPinRestoresTheParkedCornerInsteadOfRecentring() {
        let parked = NSRect(x: 1470, y: 947, width: 351, height: 94)
        let measured = NSSize(width: 351, height: 94)

        let restored = PanelReanchor.frame(
            anchor: parked, size: measured, opensUpward: false, horizontal: .leading
        )
        XCTAssertEqual(restored, parked)

        let guessed = NSRect(x: 1470, y: 947, width: 380, height: 58)
        let recentred = PanelReanchor.frame(
            anchor: guessed, size: measured, opensUpward: false, horizontal: .center
        )
        XCTAssertEqual(recentred.origin.x, 1485, "the old behaviour, kept here as the contrast")
    }

    func testFramesLandOnWholePointsSoTheAnchorCannotDriftOffTheWindow() {
        // 351 -> 422 is an odd growth around an odd width: the exact centre is
        // half a point away from anything the window can store.
        let anchor = NSRect(x: 748, y: 997, width: 351, height: 94)
        let grown = PanelReanchor.frame(
            anchor: anchor, size: NSSize(width: 422, height: 95),
            opensUpward: false, horizontal: .center
        )
        XCTAssertEqual(grown.origin.x, grown.origin.x.rounded())
        XCTAssertEqual(grown.origin.y, grown.origin.y.rounded())
    }

    // MARK: - The first measured layout after launch

    @MainActor
    func testRestoredPlacementKeepsThePinnedEdgeWhenTheHeightChanged() {
        // Pixel cat switched off between launches: 20pt shorter, same corner.
        let parked = NSRect(x: 1470, y: 947, width: 351, height: 94)
        let anchor = FloatingPanelController.initialAnchorFrame(
            for: .restored(parked), size: NSSize(width: 351, height: 74), screen: nil
        )
        let frame = PanelReanchor.frame(
            anchor: anchor, size: NSSize(width: 351, height: 74),
            opensUpward: false, horizontal: .leading
        )
        XCTAssertEqual(frame.origin.x, 1470)
        XCTAssertEqual(frame.maxY, parked.maxY, "the bar hangs from the same top edge")
    }

    @MainActor
    func testPreferencesWithoutASavedSizeStillRestoreTheExactCorner() {
        let anchor = FloatingPanelController.initialAnchorFrame(
            for: .restoredOrigin(NSPoint(x: 1470, y: 947)),
            size: NSSize(width: 351, height: 94), screen: nil
        )
        let frame = PanelReanchor.frame(
            anchor: anchor, size: NSSize(width: 351, height: 94),
            opensUpward: false, horizontal: .leading
        )
        XCTAssertEqual(frame.origin, NSPoint(x: 1470, y: 947))
    }

    @MainActor
    func testFirstEverLaunchCentresOnTheMeasuredWidthNotTheGuessedOne() {
        let size = NSSize(width: 351, height: 94)
        let anchor = FloatingPanelController.initialAnchorFrame(
            for: .topCenter, size: size, screen: nil
        )
        // Falls back to a 1440x900 sheet when there is no screen to ask.
        XCTAssertEqual(anchor.midX, 720, accuracy: 0.5)
        XCTAssertEqual(anchor.maxY, 900 - 4)
        XCTAssertEqual(anchor.size, size)
    }

    // MARK: - Rounding truce with SwiftUI

    /// SwiftUI pushes the laid-out content size back onto the window truncated to
    /// whole points, and the bar's ideal width lands on a half point. Asking for
    /// a width the window will never keep left the two resizing each other.
    @MainActor
    func testSubPointDisagreementIsNotTreatedAsAResize() {
        let measured: CGFloat = 351.5
        let target = measured.rounded(.down)
        XCTAssertEqual(target, 351)
        XCTAssertLessThanOrEqual(abs(target - 351), FloatingPanelController.sizeTolerance)
        // Even if the window came back a point the other way, it is absorbed.
        XCTAssertLessThanOrEqual(abs(352 - target), FloatingPanelController.sizeTolerance)
        // A real change — one provider chip — never is.
        XCTAssertGreaterThan(abs(422 - target), FloatingPanelController.sizeTolerance)
    }
}
