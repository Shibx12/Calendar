import XCTest
@testable import CalendarBar

final class TimelineFormatterTests: XCTestCase {
    func testMinutesRoundUpToNextWholeMinute() {
        XCTAssertEqual(TimelineFormatter.minutes(from: 1), 1)
        XCTAssertEqual(TimelineFormatter.minutes(from: 60), 1)
        XCTAssertEqual(TimelineFormatter.minutes(from: 61), 2)
    }

    func testCompactDurationUsesHoursWhenUseful() {
        XCTAssertEqual(TimelineFormatter.compactDuration(0), "now")
        XCTAssertEqual(TimelineFormatter.compactDuration(87 * 60), "1h 27m")
        XCTAssertEqual(TimelineFormatter.compactDuration(120 * 60), "2h")
    }

    func testNegativeDurationsDoNotProduceNegativeMinutes() {
        XCTAssertEqual(TimelineFormatter.compactDuration(-5), "now")
    }

    func testMenuBarDurationMatchesRequestedWording() {
        XCTAssertEqual(TimelineFormatter.menuBarDuration(87 * 60, usesPlural: false), "87m")
        XCTAssertEqual(TimelineFormatter.menuBarDuration(88 * 60, usesPlural: true), "88m")
        XCTAssertEqual(TimelineFormatter.menuBarDuration(60, usesPlural: true), "1m")
    }

    func testMenuBarDurationSwitchesToHoursAfterNinetyMinutes() {
        XCTAssertEqual(TimelineFormatter.menuBarDuration(90 * 60, usesPlural: false), "90m")
        XCTAssertEqual(TimelineFormatter.menuBarDuration(91 * 60, usesPlural: false), "1h 31m")
        XCTAssertEqual(TimelineFormatter.menuBarDuration(123 * 60, usesPlural: false), "2h 3m")
        XCTAssertEqual(TimelineFormatter.menuBarDuration(121 * 60, usesPlural: true), "2h 1m")
        XCTAssertEqual(TimelineFormatter.menuBarDuration(120 * 60, usesPlural: true), "2h")
    }

    func testAllDayMenuBarLabelUsesOnlyItsTitle() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let event = CalendarEvent(
            id: "all-day",
            title: "全天计划",
            startDate: now.addingTimeInterval(-8 * 3_600),
            endDate: now.addingTimeInterval(16 * 3_600),
            isAllDay: true
        )

        XCTAssertEqual(TimelineFormatter.relativeLabel(for: event, now: now), "全天计划")
    }

    func testStatusUpdatePlannerUsesNextVisibleMinuteBoundary() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let event = CalendarEvent(
            id: "upcoming",
            title: "散步",
            startDate: now.addingTimeInterval(87 * 60 + 20),
            endDate: now.addingTimeInterval(2 * 3_600)
        )

        let nextDate = StatusUpdatePlanner.nextUpdateDate(
            events: [event],
            menuEvents: [event],
            now: now,
            lookAheadHours: 24,
            upcomingWhileCurrentHours: 5
        )

        XCTAssertEqual(nextDate, now.addingTimeInterval(20))
    }
}
