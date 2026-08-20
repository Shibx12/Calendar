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

    func testAllDayAutomaticReminderUsesNinePMOnPreviousDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(
            from: DateComponents(year: 2033, month: 5, day: 18)
        )!
        let event = CalendarEvent(
            id: "all-day",
            title: "全天事件",
            startDate: start,
            endDate: calendar.date(byAdding: .day, value: 1, to: start)!,
            isAllDay: true
        )

        let moments = ReminderScheduler.makeMoments(events: [event], calendar: calendar)
        let expected = calendar.date(
            from: DateComponents(year: 2033, month: 5, day: 17, hour: 21)
        )!

        XCTAssertEqual(moments.map(\.fireDate), [expected])
    }

    func testNextReminderSleepsDirectlyUntilItsFireDate() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let nextDate = now.addingTimeInterval(8 * 3_600)

        XCTAssertEqual(
            ReminderScheduler.nextCheckInterval(nextDate: nextDate, now: now),
            8 * 3_600
        )
    }
}
