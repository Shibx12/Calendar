import XCTest
@testable import CalendarBar

final class AppleCalendarLinkTests: XCTestCase {
    func testEventLinkIncludesOccurrenceDateAndCalendarItemIdentifier() {
        let event = CalendarEvent(
            id: "event",
            title: "会议",
            startDate: Date(timeIntervalSince1970: 2_000_000_000),
            endDate: Date(timeIntervalSince1970: 2_000_003_600),
            calendarItemIdentifier: "ITEM-ID"
        )

        XCTAssertEqual(
            AppleCalendarLink.eventURL(for: event)?.absoluteString,
            "ical://ekevent/20330518T033320Z/ITEM-ID?method=show&options=more"
        )
    }
}
