import AppKit
import EventKit
import Foundation
import SwiftUI

enum AppLayout {
    static let popoverWidth: CGFloat = 336
}

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let calendarColor: NSColor
    let location: String?
    let calendarAlarmDates: [Date]

    init(event: EKEvent) {
        id = event.eventIdentifier ?? "\(event.calendar.calendarIdentifier)-\(event.startDate.timeIntervalSince1970)-\(event.title ?? "")"
        title = event.title?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "未命名日程"
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        calendarID = event.calendar.calendarIdentifier
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
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor
        self.location = location
        self.calendarAlarmDates = calendarAlarmDates
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
        if totalMinutes < 1 { return "now" }
        if totalMinutes < 60 { return "\(totalMinutes)m" }

        let hours = totalMinutes / 60
        let remaining = totalMinutes % 60
        if remaining == 0 { return "\(hours)h" }
        return "\(hours)h \(remaining)m"
    }

    static func menuBarDuration(_ interval: TimeInterval, usesPlural _: Bool) -> String {
        let value = minutes(from: interval)
        if value > 90 {
            let hours = value / 60
            let remainingMinutes = value % 60
            guard remainingMinutes > 0 else { return "\(hours)h" }
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(value)m"
    }

    static func relativeLabel(for event: CalendarEvent, now: Date) -> String {
        let title = event.title.menuBarTruncated(to: 18)
        if event.startDate <= now, event.endDate > now {
            return "\(title) \(menuBarDuration(event.endDate.timeIntervalSince(now), usesPlural: true)) left"
        }
        return "\(title) in \(menuBarDuration(event.startDate.timeIntervalSince(now), usesPlural: false))"
    }
}
