import AppKit
import Combine
import EventKit
import Foundation

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var access: CalendarAccess = .unknown
    @Published private(set) var calendars: [CalendarChoice] = []
    @Published private(set) var weekEvents: [CalendarEvent] = []
    @Published private(set) var menuEvents: [CalendarEvent] = []
    @Published private(set) var now = Date()
    @Published private(set) var isRefreshing = false

    let preferences: Preferences

    private let store = EKEventStore()
    private var timer: Timer?
    private var timerTicks = 0
    private var cancellables = Set<AnyCancellable>()
    private var eventStoreObserver: NSObjectProtocol?
    private var clockObserver: NSObjectProtocol?
    private var dayObserver: NSObjectProtocol?

    convenience init() {
        self.init(preferences: Preferences())
    }

    init(preferences: Preferences) {
        self.preferences = preferences
        observeChanges()
        updateAuthorizationState()
        startTimer()
    }

    deinit {
        timer?.invalidate()
        if let eventStoreObserver { NotificationCenter.default.removeObserver(eventStoreObserver) }
        if let clockObserver { NotificationCenter.default.removeObserver(clockObserver) }
        if let dayObserver { NotificationCenter.default.removeObserver(dayObserver) }
    }

    var selectedCalendarIDs: Set<String> {
        let available = Set(calendars.map(\.id))
        let stored = preferences.selectedCalendarIDs.intersection(available)
        return stored.isEmpty ? available : stored
    }

    var groupedWeekEvents: [DayEvents] {
        let calendar = Calendar.autoupdatingCurrent
        return Dictionary(grouping: weekEvents) { calendar.startOfDay(for: $0.startDate) }
            .map { DayEvents(day: $0.key, events: $0.value.sorted { $0.startDate < $1.startDate }) }
            .sorted { $0.day < $1.day }
    }

    var statusText: String {
        guard access == .granted else { return "Calendar access" }
        guard !menuEvents.isEmpty else { return "Free" }
        return menuEvents.map { TimelineFormatter.relativeLabel(for: $0, now: now) }.joined(separator: "  ·  ")
    }

    func requestAccess() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.access = granted ? .granted : .denied
                    self?.refresh()
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.access = granted ? .granted : .denied
                    self?.refresh()
                }
            }
        }
    }

    func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    func refresh() {
        now = Date()
        updateAuthorizationState()
        guard access == .granted else {
            calendars = []
            weekEvents = []
            menuEvents = []
            return
        }

        isRefreshing = true
        let allEventCalendars = store.calendars(for: .event)
        calendars = allEventCalendars
            .map(CalendarChoice.init)
            .sorted { lhs, rhs in
                lhs.source == rhs.source ? lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending : lhs.source < rhs.source
            }

        let selected = Set(selectedCalendarIDs)
        let ekCalendars = store.calendars(for: .event).filter { selected.contains($0.calendarIdentifier) }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? now.addingTimeInterval(7 * 86_400)
        let predicate = store.predicateForEvents(withStart: today, end: weekEnd, calendars: ekCalendars)

        let events = store.events(matching: predicate).map(CalendarEvent.init)
        weekEvents = events.sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate { return lhs.endDate < rhs.endDate }
            return lhs.startDate < rhs.startDate
        }
        rebuildMenuEvents()
        isRefreshing = false
    }

    private func rebuildMenuEvents() {
        let limit = now.addingTimeInterval(TimeInterval(preferences.lookAheadHours * 3_600))
        let timed = weekEvents.filter { !$0.isAllDay && $0.endDate > now && $0.startDate <= limit }
        let current = timed
            .filter { $0.startDate <= now && $0.endDate > now }
            .min { $0.endDate < $1.endDate }
        let upcoming = timed
            .filter { $0.startDate > now }
            .min { $0.startDate < $1.startDate }
        menuEvents = [current, upcoming].compactMap { $0 }
    }

    private func updateAuthorizationState() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess, .authorized:
                access = .granted
            case .denied, .restricted, .writeOnly:
                access = .denied
            case .notDetermined:
                access = .unknown
            @unknown default:
                access = .denied
            }
        } else {
            switch status {
            case .authorized, .fullAccess:
                access = .granted
            case .denied, .restricted, .writeOnly:
                access = .denied
            case .notDetermined:
                access = .unknown
            @unknown default:
                access = .denied
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 3
    }

    private func tick() {
        now = Date()
        rebuildMenuEvents()
        timerTicks += 1
        if timerTicks >= 10 {
            timerTicks = 0
            refresh()
        }
    }

    private func observeChanges() {
        preferences.$selectedCalendarIDs
            .dropFirst()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        preferences.$lookAheadHours
            .dropFirst()
            .sink { [weak self] _ in self?.rebuildMenuEvents() }
            .store(in: &cancellables)

        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        clockObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        dayObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}
