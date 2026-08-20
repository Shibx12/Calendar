import XCTest
@testable import CalendarBar

final class MenuEventSelectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testAllDayCurrentAndUpcomingUseRequestedOrder() {
        let allDay = event(
            id: "all-day",
            start: now.addingTimeInterval(-8 * 3_600),
            end: now.addingTimeInterval(16 * 3_600),
            isAllDay: true
        )
        let current = event(
            id: "current",
            start: now.addingTimeInterval(-20 * 60),
            end: now.addingTimeInterval(40 * 60)
        )
        let upcoming = event(
            id: "upcoming",
            start: now.addingTimeInterval(60 * 60),
            end: now.addingTimeInterval(2 * 3_600)
        )

        let selection = MenuEventSelector.select(
            from: [upcoming, current, allDay],
            now: now,
            lookAheadHours: 24,
            upcomingWhileCurrentHours: 5,
            includesCurrentTimedEvent: true
        )

        XCTAssertEqual(selection.map(\.id), ["all-day", "current", "upcoming"])
    }

    func testAllDayAndUpcomingRemainWhenCurrentEventsAreHidden() {
        let allDay = event(
            id: "all-day",
            start: now.addingTimeInterval(-8 * 3_600),
            end: now.addingTimeInterval(16 * 3_600),
            isAllDay: true
        )
        let current = event(
            id: "current",
            start: now.addingTimeInterval(-20 * 60),
            end: now.addingTimeInterval(40 * 60)
        )
        let upcoming = event(
            id: "upcoming",
            start: now.addingTimeInterval(60 * 60),
            end: now.addingTimeInterval(2 * 3_600)
        )

        let selection = MenuEventSelector.select(
            from: [current, upcoming, allDay],
            now: now,
            lookAheadHours: 24,
            upcomingWhileCurrentHours: 5,
            includesCurrentTimedEvent: false
        )

        XCTAssertEqual(selection.map(\.id), ["all-day", "upcoming"])
    }

    func testFutureAllDayEventDoesNotAppearToday() {
        let tomorrow = event(
            id: "tomorrow",
            start: now.addingTimeInterval(8 * 3_600),
            end: now.addingTimeInterval(32 * 3_600),
            isAllDay: true
        )

        let selection = MenuEventSelector.select(
            from: [tomorrow],
            now: now,
            lookAheadHours: 24,
            upcomingWhileCurrentHours: 5,
            includesCurrentTimedEvent: true
        )

        XCTAssertTrue(selection.isEmpty)
    }

    func testDistantUpcomingEventIsHiddenWhileCurrentEventIsDisplayed() {
        let current = event(
            id: "current",
            start: now.addingTimeInterval(-20 * 60),
            end: now.addingTimeInterval(40 * 60)
        )
        let upcoming = event(
            id: "upcoming",
            start: now.addingTimeInterval(6 * 3_600),
            end: now.addingTimeInterval(7 * 3_600)
        )

        let selection = MenuEventSelector.select(
            from: [current, upcoming],
            now: now,
            lookAheadHours: 24,
            upcomingWhileCurrentHours: 5,
            includesCurrentTimedEvent: true
        )

        XCTAssertEqual(selection.map(\.id), ["current"])
    }

    func testUpcomingEventAppearsAfterCurrentEventEndsRegardlessOfConcurrentRange() {
        let current = event(
            id: "ended-current",
            start: now.addingTimeInterval(-2 * 3_600),
            end: now.addingTimeInterval(-60)
        )
        let upcoming = event(
            id: "upcoming",
            start: now.addingTimeInterval(6 * 3_600),
            end: now.addingTimeInterval(7 * 3_600)
        )

        let selection = MenuEventSelector.select(
            from: [current, upcoming],
            now: now,
            lookAheadHours: 24,
            upcomingWhileCurrentHours: 5,
            includesCurrentTimedEvent: true
        )

        XCTAssertEqual(selection.map(\.id), ["upcoming"])
    }

    func testMultipleOverlappingCurrentEventsAreAllIncluded() {
        let first = event(
            id: "first-current",
            start: now.addingTimeInterval(-40 * 60),
            end: now.addingTimeInterval(20 * 60)
        )
        let second = event(
            id: "second-current",
            start: now.addingTimeInterval(-10 * 60),
            end: now.addingTimeInterval(50 * 60)
        )
        let upcoming = event(
            id: "upcoming",
            start: now.addingTimeInterval(2 * 3_600),
            end: now.addingTimeInterval(3 * 3_600)
        )

        let selection = MenuEventSelector.select(
            from: [second, upcoming, first],
            now: now,
            lookAheadHours: 24,
            upcomingWhileCurrentHours: 5,
            includesCurrentTimedEvent: true
        )

        XCTAssertEqual(
            selection.map(\.id),
            ["first-current", "second-current", "upcoming"]
        )
    }

    private func event(
        id: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: id,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay
        )
    }
}
