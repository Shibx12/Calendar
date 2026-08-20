import AppKit
import Combine
@preconcurrency import EventKit
import Foundation

private final class EventStoreBox: @unchecked Sendable {
    let store = EKEventStore()
}

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var access: CalendarAccess = .unknown
    @Published private(set) var calendars: [CalendarChoice] = []
    @Published private(set) var weekEvents: [CalendarEvent] = []
    @Published private(set) var menuEvents: [CalendarEvent] = []
    @Published private(set) var now = Date()
    @Published private(set) var isRefreshing = false

    let preferences: Preferences

    private let eventStoreBox = EventStoreBox()
    private var store: EKEventStore { eventStoreBox.store }
    private let fetchQueue = DispatchQueue(label: "com.benjamin.CalendarBar.event-fetch", qos: .userInitiated)
    private var statusUpdateTimer: Timer?
    private var eventStoreRefreshTask: Task<Void, Never>?
    private var isFetchInFlight = false
    private var needsRefreshAfterFetch = false
    private var lastSuccessfulRefresh: Date?
    private var cancellables = Set<AnyCancellable>()
    private var eventStoreObserver: NSObjectProtocol?
    private var clockObserver: NSObjectProtocol?
    private var dayObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    convenience init() {
        self.init(preferences: Preferences())
    }

    init(preferences: Preferences) {
        self.preferences = preferences
        observeChanges()
        updateAuthorizationState()
    }

    deinit {
        statusUpdateTimer?.invalidate()
        eventStoreRefreshTask?.cancel()
        if let eventStoreObserver { NotificationCenter.default.removeObserver(eventStoreObserver) }
        if let clockObserver { NotificationCenter.default.removeObserver(clockObserver) }
        if let dayObserver { NotificationCenter.default.removeObserver(dayObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
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
        guard access == .granted else { return L10n.text("status.calendar_access") }
        guard !menuEvents.isEmpty else { return L10n.text("status.free") }
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
            isRefreshing = false
            isFetchInFlight = false
            needsRefreshAfterFetch = false
            scheduleNextStatusUpdate()
            return
        }

        if isFetchInFlight {
            needsRefreshAfterFetch = true
            rebuildMenuEvents()
            return
        }

        isFetchInFlight = true
        isRefreshing = true
        let eventStoreBox = self.eventStoreBox
        let fetchDate = now
        let storedSelection = preferences.selectedCalendarIDs

        fetchQueue.async { [weak self] in
            let store = eventStoreBox.store
            let allEventCalendars = store.calendars(for: .event)
            let unsortedChoices: [CalendarChoice] = allEventCalendars.map {
                CalendarChoice(calendar: $0)
            }
            let choices: [CalendarChoice] = unsortedChoices.sorted { lhs, rhs in
                if lhs.source == rhs.source {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.source < rhs.source
            }

            let availableIDs = Set(allEventCalendars.map(\.calendarIdentifier))
            let storedAvailable = storedSelection.intersection(availableIDs)
            let selectedIDs = storedAvailable.isEmpty ? availableIDs : storedAvailable
            let selectedCalendars = allEventCalendars.filter {
                selectedIDs.contains($0.calendarIdentifier)
            }

            let calendar = Calendar.autoupdatingCurrent
            let today = calendar.startOfDay(for: fetchDate)
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: today)
                ?? fetchDate.addingTimeInterval(7 * 86_400)
            let predicate = store.predicateForEvents(
                withStart: today,
                end: weekEnd,
                calendars: selectedCalendars
            )
            let events = store.events(matching: predicate)
                .map(CalendarEvent.init)
                .sorted { lhs, rhs in
                    if lhs.startDate == rhs.startDate { return lhs.endDate < rhs.endDate }
                    return lhs.startDate < rhs.startDate
                }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isFetchInFlight = false
                guard self.access == .granted else {
                    self.isRefreshing = false
                    return
                }
                self.now = Date()
                self.calendars = choices
                self.weekEvents = events
                self.lastSuccessfulRefresh = self.now
                self.rebuildMenuEvents()
                self.isRefreshing = false

                if self.needsRefreshAfterFetch {
                    self.needsRefreshAfterFetch = false
                    self.refresh()
                }
            }
        }
    }

    /// EventKit change notifications keep the cache current. Opening the panel
    /// only falls back to a fetch when the cache is genuinely old.
    func refreshIfStale(maxAge: TimeInterval = 30 * 60) {
        guard let lastSuccessfulRefresh,
              Date().timeIntervalSince(lastSuccessfulRefresh) < maxAge else {
            refresh()
            return
        }

        now = Date()
        rebuildMenuEvents()
    }

    private func rebuildMenuEvents() {
        let selection = MenuEventSelector.select(
            from: weekEvents,
            now: now,
            lookAheadHours: preferences.lookAheadHours,
            upcomingWhileCurrentHours: preferences.upcomingWhileCurrentHours,
            includesCurrentTimedEvent: preferences.showsCurrentEvent
        )
        if menuEvents != selection {
            menuEvents = selection
        }
        scheduleNextStatusUpdate()
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

    private func scheduleNextStatusUpdate() {
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = nil

        let currentDate = Date()
        guard access == .granted,
              let nextDate = StatusUpdatePlanner.nextUpdateDate(
                events: weekEvents,
                menuEvents: menuEvents,
                now: currentDate,
                lookAheadHours: preferences.lookAheadHours,
                upcomingWhileCurrentHours: preferences.upcomingWhileCurrentHours
              ) else { return }

        let interval = max(0.5, nextDate.timeIntervalSince(currentDate))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.rebuildMenuEvents()
            }
        }
        timer.tolerance = min(3, max(0.25, interval * 0.02))
        RunLoop.main.add(timer, forMode: .common)
        statusUpdateTimer = timer
    }

    private func scheduleEventStoreRefresh() {
        eventStoreRefreshTask?.cancel()
        eventStoreRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self?.refresh()
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

        preferences.$upcomingWhileCurrentHours
            .dropFirst()
            .sink { [weak self] _ in self?.rebuildMenuEvents() }
            .store(in: &cancellables)

        preferences.$showsCurrentEvent
            .dropFirst()
            .sink { [weak self] _ in self?.rebuildMenuEvents() }
            .store(in: &cancellables)

        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleEventStoreRefresh() }
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

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}

enum StatusUpdatePlanner {
    static func nextUpdateDate(
        events: [CalendarEvent],
        menuEvents: [CalendarEvent],
        now: Date,
        lookAheadHours: Int,
        upcomingWhileCurrentHours: Int
    ) -> Date? {
        var candidates: [Date] = []
        let minimumDelay: TimeInterval = 0.25

        for event in menuEvents where !event.isAllDay {
            let target = event.startDate > now ? event.startDate : event.endDate
            guard target > now else { continue }

            let interval = target.timeIntervalSince(now)
            let displayedMinutes = TimelineFormatter.minutes(from: interval)
            let nextMinuteDelay = interval - TimeInterval(max(0, displayedMinutes - 1) * 60)
            if nextMinuteDelay > minimumDelay {
                candidates.append(now.addingTimeInterval(nextMinuteDelay))
            }
            candidates.append(target)
        }

        for event in events {
            if event.startDate.timeIntervalSince(now) > minimumDelay {
                candidates.append(event.startDate)
            }
            if event.endDate.timeIntervalSince(now) > minimumDelay {
                candidates.append(event.endDate)
            }

            guard !event.isAllDay else { continue }
            let lookAheadEntry = event.startDate.addingTimeInterval(
                -TimeInterval(lookAheadHours * 3_600)
            )
            if lookAheadEntry.timeIntervalSince(now) > minimumDelay {
                candidates.append(lookAheadEntry)
            }

            let concurrentEntry = event.startDate.addingTimeInterval(
                -TimeInterval(upcomingWhileCurrentHours * 3_600)
            )
            if concurrentEntry.timeIntervalSince(now) > minimumDelay {
                candidates.append(concurrentEntry)
            }
        }

        return candidates.min()
    }
}

enum MenuEventSelector {
    static func select(
        from events: [CalendarEvent],
        now: Date,
        lookAheadHours: Int,
        upcomingWhileCurrentHours: Int,
        includesCurrentTimedEvent: Bool
    ) -> [CalendarEvent] {
        let limit = now.addingTimeInterval(TimeInterval(lookAheadHours * 3_600))

        let allDay = events
            .filter { $0.isAllDay && $0.startDate <= now && $0.endDate > now }
            .min { lhs, rhs in
                if lhs.startDate == rhs.startDate { return lhs.endDate < rhs.endDate }
                return lhs.startDate < rhs.startDate
            }

        let timed = events.filter {
            !$0.isAllDay && $0.endDate > now && $0.startDate <= limit
        }
        let currentEvents = includesCurrentTimedEvent
            ? timed
                .filter { $0.startDate <= now && $0.endDate > now }
                .sorted { lhs, rhs in
                    if lhs.startDate == rhs.startDate { return lhs.endDate < rhs.endDate }
                    return lhs.startDate < rhs.startDate
                }
            : []
        let nearestUpcoming = timed
            .filter { $0.startDate > now }
            .min { $0.startDate < $1.startDate }
        let upcoming: CalendarEvent?
        if !currentEvents.isEmpty {
            let concurrentLimit = now.addingTimeInterval(
                TimeInterval(upcomingWhileCurrentHours * 3_600)
            )
            upcoming = nearestUpcoming.flatMap { $0.startDate <= concurrentLimit ? $0 : nil }
        } else {
            upcoming = nearestUpcoming
        }

        return [allDay].compactMap { $0 } + currentEvents + [upcoming].compactMap { $0 }
    }
}
