import AppKit
import Foundation

struct ScheduledReminder: Identifiable, Equatable {
    let event: CalendarEvent
    let fireDate: Date

    var id: String {
        "\(event.id)|\(Int(event.startDate.timeIntervalSince1970))|\(Int(fireDate.timeIntervalSince1970))"
    }

    var eventInstanceID: String {
        "\(event.id)|\(Int(event.startDate.timeIntervalSince1970))"
    }
}

@MainActor
final class ReminderScheduler {
    var onReminder: ((ScheduledReminder) -> Void)?

    private enum Key {
        static let firedReminders = "firedReminderDates.v1"
    }

    private let defaults: UserDefaults
    private var moments: [ScheduledReminder] = []
    private var firedReminderDates: [String: TimeInterval]
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var clockObserver: NSObjectProtocol?

    convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        firedReminderDates = defaults.dictionary(forKey: Key.firedReminders)?
            .compactMapValues { $0 as? TimeInterval } ?? [:]
        observeSystemTime()
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let clockObserver { NotificationCenter.default.removeObserver(clockObserver) }
    }

    func update(events: [CalendarEvent]) {
        moments = Self.makeMoments(events: events)
        pruneHistory(now: Date())
        checkDueReminders()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    static func makeMoments(
        events: [CalendarEvent],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ScheduledReminder] {
        events.flatMap { event -> [ScheduledReminder] in
            let automaticDates: [Date]
            if event.isAllDay {
                let previousDay = calendar.date(
                    byAdding: .day,
                    value: -1,
                    to: event.startDate
                ) ?? event.startDate.addingTimeInterval(-86_400)
                automaticDates = calendar.date(
                    bySettingHour: 21,
                    minute: 0,
                    second: 0,
                    of: previousDay
                ).map { [$0] } ?? []
            } else {
                automaticDates = [
                    event.startDate.addingTimeInterval(-10 * 60),
                    event.startDate.addingTimeInterval(-5 * 60)
                ]
            }
            let allDates = event.calendarAlarmDates + automaticDates
            var seenSeconds = Set<Int64>()

            return allDates.compactMap { date in
                let second = Int64(date.timeIntervalSince1970.rounded())
                guard seenSeconds.insert(second).inserted else { return nil }
                return ScheduledReminder(event: event, fireDate: date)
            }
        }
        .sorted { lhs, rhs in
            lhs.fireDate == rhs.fireDate
                ? lhs.event.startDate < rhs.event.startDate
                : lhs.fireDate < rhs.fireDate
        }
    }

    private func checkDueReminders(now: Date = Date()) {
        let due = moments.filter {
            $0.fireDate <= now && firedReminderDates[$0.id] == nil
        }
        let grouped = Dictionary(grouping: due, by: \.eventInstanceID)
        var remindersToShow: [ScheduledReminder] = []

        for group in grouped.values {
            let sorted = group.sorted { $0.fireDate < $1.fireDate }
            sorted.forEach { firedReminderDates[$0.id] = $0.fireDate.timeIntervalSince1970 }

            guard let latest = sorted.last else { continue }
            let lateness = now.timeIntervalSince(latest.fireDate)
            if lateness <= 5 * 60, latest.event.endDate > now {
                remindersToShow.append(latest)
            }
        }

        if !due.isEmpty {
            persistHistory()
        }

        remindersToShow
            .sorted { $0.fireDate < $1.fireDate }
            .forEach { onReminder?($0) }

        scheduleNextCheck(now: now)
    }

    private func scheduleNextCheck(now: Date) {
        timer?.invalidate()
        let nextDate = moments
            .filter { $0.fireDate > now && firedReminderDates[$0.id] == nil }
            .map(\.fireDate)
            .min()
        guard let nextDate else { return }

        // Sleep directly until the next reminder. Waking once a minute for an
        // event that is hours away wastes energy and does not improve accuracy.
        let interval = Self.nextCheckInterval(nextDate: nextDate, now: now)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.checkDueReminders() }
        }
        timer.tolerance = min(5, max(0.25, interval * 0.01))
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    static func nextCheckInterval(nextDate: Date, now: Date) -> TimeInterval {
        max(1, nextDate.timeIntervalSince(now))
    }

    private func pruneHistory(now: Date) {
        let cutoff = now.addingTimeInterval(-2 * 86_400).timeIntervalSince1970
        firedReminderDates = firedReminderDates.filter { $0.value >= cutoff }
        persistHistory()
    }

    private func persistHistory() {
        defaults.set(firedReminderDates, forKey: Key.firedReminders)
    }

    private func observeSystemTime() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkDueReminders() }
        }

        clockObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkDueReminders() }
        }
    }
}
