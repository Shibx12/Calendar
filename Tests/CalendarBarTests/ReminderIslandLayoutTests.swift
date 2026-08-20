import XCTest
@testable import CalendarBar

final class ReminderIslandLayoutTests: XCTestCase {
    func testExpandedWidthAddsFixedMarginsToLongContent() {
        let width = ReminderIslandLayout.expandedWidth(
            contentWidth: 327,
            minimumWidth: 170,
            maximumWidth: 1_400
        )

        XCTAssertEqual(width, 377)
        XCTAssertEqual((width - 327) / 2, 25)
    }

    func testExpandedWidthKeepsShortContentAtLeastAsWideAsNotch() {
        let width = ReminderIslandLayout.expandedWidth(
            contentWidth: 80,
            minimumWidth: 170,
            maximumWidth: 1_400
        )

        XCTAssertEqual(width, 170)
    }

    func testExpandedWidthRespectsAvailableScreenWidth() {
        let width = ReminderIslandLayout.expandedWidth(
            contentWidth: 1_500,
            minimumWidth: 170,
            maximumWidth: 1_400
        )

        XCTAssertEqual(width, 1_400)
    }
}
