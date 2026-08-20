import XCTest
@testable import CalendarBar

final class PopoverEventSelectorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        Date(timeIntervalSince1970: 2_000_000_000)
    }

    func testEndedEventsAreExcludedFromPopover() {
        let day = calendar.startOfDay(for: now)
        let ended = event(
            id: "ended",
            start: now.addingTimeInterval(-2 * 3_600),
            end: now.addingTimeInterval(-60)
        )
        let ongoing = event(
            id: "ongoing",
            start: now.addingTimeInterval(-30 * 60),
            end: now.addingTimeInterval(30 * 60)
        )
        let upcoming = event(
            id: "upcoming",
            start: now.addingTimeInterval(60 * 60),
            end: now.addingTimeInterval(2 * 3_600)
        )

        let selection = PopoverEventSelector.events(
            on: day,
            from: [ended, ongoing, upcoming],
            now: now,
            until: now.addingTimeInterval(48 * 3_600),
            calendar: calendar
        )

        XCTAssertEqual(selection.map(\.id), ["ongoing", "upcoming"])
    }

    func testCurrentAllDayEventRemainsVisible() {
        let day = calendar.startOfDay(for: now)
        let allDay = event(
            id: "all-day",
            start: day,
            end: calendar.date(byAdding: .day, value: 1, to: day)!,
            isAllDay: true
        )

        let selection = PopoverEventSelector.events(
            on: day,
            from: [allDay],
            now: now,
            until: now.addingTimeInterval(48 * 3_600),
            calendar: calendar
        )

        XCTAssertEqual(selection.map(\.id), ["all-day"])
    }

    func testEventsFromAnotherDayAreExcluded() {
        let day = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        let event = event(
            id: "tomorrow",
            start: tomorrow.addingTimeInterval(60 * 60),
            end: tomorrow.addingTimeInterval(2 * 3_600)
        )

        let selection = PopoverEventSelector.events(
            on: day,
            from: [event],
            now: now,
            until: now.addingTimeInterval(48 * 3_600),
            calendar: calendar
        )

        XCTAssertTrue(selection.isEmpty)
    }

    func testEventsAtOrBeyondFortyEightHourLimitAreExcluded() {
        let limit = now.addingTimeInterval(48 * 3_600)
        let day = calendar.startOfDay(for: limit)
        let inside = event(
            id: "inside",
            start: now.addingTimeInterval(47 * 3_600),
            end: now.addingTimeInterval(49 * 3_600)
        )
        let atLimit = event(
            id: "at-limit",
            start: limit,
            end: limit.addingTimeInterval(3_600)
        )

        let selection = PopoverEventSelector.events(
            on: day,
            from: [inside, atLimit],
            now: now,
            until: limit,
            calendar: calendar
        )

        XCTAssertEqual(selection.map(\.id), ["inside"])
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
