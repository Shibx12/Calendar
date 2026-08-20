import AppKit
import EventKit
import Foundation
import SwiftUI

enum AppLayout {
    static let popoverWidth: CGFloat = 300
}

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarItemIdentifier: String
    let calendarTitle: String
    let calendarColor: NSColor
    let location: String?
    let calendarAlarmDates: [Date]

    init(event: EKEvent) {
        id = event.eventIdentifier ?? "\(event.calendar.calendarIdentifier)-\(event.startDate.timeIntervalSince1970)-\(event.title ?? "")"
        title = event.title?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? L10n.text("event.untitled")
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        calendarID = event.calendar.calendarIdentifier
        calendarItemIdentifier = event.calendarItemIdentifier
        calendarTitle = event.calendar.title
        calendarColor = NSColor(cgColor: event.calendar.cgColor) ?? .controlAccentColor
        location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        calendarAlarmDates = (event.alarms ?? []).compactMap { alarm in
            guard alarm.structuredLocation == nil else { return nil }
            return alarm.absoluteDate ?? event.startDate.addingTimeInterval(alarm.relativeOffset)
        }
    }

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        calendarID: String = "test-calendar",
        calendarItemIdentifier: String? = nil,
        calendarTitle: String = "Calendar",
        calendarColor: NSColor = .controlAccentColor,
        location: String? = nil,
        calendarAlarmDates: [Date] = []
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.calendarItemIdentifier = calendarItemIdentifier ?? id
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor
        self.location = location
        self.calendarAlarmDates = calendarAlarmDates
    }
}

enum AppleCalendarLink {
    static func eventURL(for event: CalendarEvent) -> URL? {
        guard !event.calendarItemIdentifier.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"

        var components = URLComponents()
        components.scheme = "ical"
        components.host = "ekevent"
        components.path = "/\(formatter.string(from: event.startDate))/\(event.calendarItemIdentifier)"
        components.queryItems = [
            URLQueryItem(name: "method", value: "show"),
            URLQueryItem(name: "options", value: "more")
        ]
        return components.url
    }

    static func dayURL(for event: CalendarEvent) -> URL? {
        URL(string: "calshow:\(event.startDate.timeIntervalSinceReferenceDate)")
    }
}

struct CalendarChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let color: NSColor
    let source: String

    init(calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        title = calendar.title
        color = NSColor(cgColor: calendar.cgColor) ?? .controlAccentColor
        source = calendar.source.title
    }
}

struct DayEvents: Identifiable {
    let day: Date
    let events: [CalendarEvent]
    var id: Date { day }
}

enum CalendarAccess: Equatable {
    case unknown
    case denied
    case granted
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    func menuBarTruncated(to limit: Int) -> String {
        guard count > limit else { return self }
        return String(prefix(max(1, limit - 1))) + "…"
    }
}

enum TimelineFormatter {
    static func minutes(from interval: TimeInterval) -> Int {
        max(0, Int(ceil(interval / 60)))
    }

    static func compactDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = minutes(from: interval)
        if totalMinutes < 1 { return L10n.text("duration.now") }
        if totalMinutes < 60 {
            return L10n.format("duration.minutes", Int64(totalMinutes))
        }

        let hours = totalMinutes / 60
        let remaining = totalMinutes % 60
        if remaining == 0 {
            return L10n.format("duration.hours", Int64(hours))
        }
        return L10n.format(
            "duration.hours_minutes",
            Int64(hours),
            Int64(remaining)
        )
    }

    static func menuBarDuration(_ interval: TimeInterval, usesPlural _: Bool) -> String {
        let value = minutes(from: interval)
        if value > 90 {
            let hours = value / 60
            let remainingMinutes = value % 60
            guard remainingMinutes > 0 else {
                return L10n.format("duration.hours", Int64(hours))
            }
            return L10n.format(
                "duration.hours_minutes",
                Int64(hours),
                Int64(remainingMinutes)
            )
        }
        return L10n.format("duration.minutes", Int64(value))
    }

    static func relativeLabel(for event: CalendarEvent, now: Date) -> String {
        let title = event.title.menuBarTruncated(to: 18)
        if event.isAllDay { return title }
        if event.startDate <= now, event.endDate > now {
            return L10n.format(
                "event.remaining_format",
                title,
                menuBarDuration(event.endDate.timeIntervalSince(now), usesPlural: true)
            )
        }
        return L10n.format(
            "event.upcoming_format",
            title,
            menuBarDuration(event.startDate.timeIntervalSince(now), usesPlural: false)
        )
    }
}
