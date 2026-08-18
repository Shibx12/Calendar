import AppKit
import XCTest
@testable import CalendarBar

@MainActor
final class ReminderSchedulerTests: XCTestCase {
    func testCalendarAlarmsCombineWithAutomaticTenAndFiveMinuteReminders() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let event = CalendarEvent(
            id: "event-1",
            title: "散步",
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            calendarAlarmDates: [
                start.addingTimeInterval(-1_800),
                start.addingTimeInterval(-600)
            ]
        )

        let moments = ReminderScheduler.makeMoments(events: [event])
        let offsets = moments.map { Int($0.fireDate.timeIntervalSince(start)) }

        XCTAssertEqual(offsets, [-1_800, -600, -300])
    }

    func testReminderIdentityIncludesRecurringEventStartDate() {
        let firstStart = Date(timeIntervalSince1970: 2_000_000_000)
        let secondStart = firstStart.addingTimeInterval(86_400)
        let first = CalendarEvent(
            id: "recurring-event",
            title: "站会",
            startDate: firstStart,
            endDate: firstStart.addingTimeInterval(1_800)
        )
        let second = CalendarEvent(
            id: "recurring-event",
            title: "站会",
            startDate: secondStart,
            endDate: secondStart.addingTimeInterval(1_800)
        )

        let moments = ReminderScheduler.makeMoments(events: [first, second])

        XCTAssertEqual(Set(moments.map(\.id)).count, 4)
    }
}
