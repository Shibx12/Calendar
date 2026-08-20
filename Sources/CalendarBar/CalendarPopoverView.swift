import AppKit
import SwiftUI

@MainActor
final class PopoverNavigationModel: ObservableObject {
    @Published var showingSettings = false

    func resetToCalendar() {
        showingSettings = false
    }
}

struct CalendarPopoverView: View {
    @ObservedObject var service: CalendarService
    @ObservedObject var navigation: PopoverNavigationModel
    @ObservedObject private var preferences: Preferences
    let onPreferredHeightChange: (CGFloat) -> Void
    let onTestReminder: () -> Void
    let onOpenEvent: (CalendarEvent) -> Void
    @State private var scheduleContentHeight: CGFloat = 0
    @State private var settingsContentHeight: CGFloat = 0

    private let calendar = Calendar.autoupdatingCurrent
    private let pageAnimation = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.34)
    private let popoverLookAhead: TimeInterval = 48 * 3_600

    init(
        service: CalendarService,
        navigation: PopoverNavigationModel,
        onPreferredHeightChange: @escaping (CGFloat) -> Void,
        onTestReminder: @escaping () -> Void,
        onOpenEvent: @escaping (CalendarEvent) -> Void
    ) {
        self.service = service
        self.navigation = navigation
        preferences = service.preferences
        self.onPreferredHeightChange = onPreferredHeightChange
        self.onTestReminder = onTestReminder
        self.onOpenEvent = onOpenEvent
    }

    var body: some View {
        ZStack(alignment: .top) {
            VisualEffectView(material: .popover)
                .ignoresSafeArea()

            ZStack(alignment: .top) {
                if navigation.showingSettings {
                    SettingsView(
                        service: service,
                        onTestReminder: onTestReminder,
                        onSelectCalendar: hideSettings,
                        onContentHeightChange: { height in
                            guard abs(settingsContentHeight - height) >= 1 else { return }
                            settingsContentHeight = height
                        }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        )
                    )
                    .zIndex(1)
                } else {
                    schedulePage
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                        )
                        .zIndex(0)
                }
            }
            .clipped()
        }
        // The AppKit panel owns height animation. Filling its current bounds
        // avoids a second, competing SwiftUI size animation during page swaps.
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(width: AppLayout.popoverWidth)
        .background(
            TrackpadSwipeMonitor(
                onSwipeLeft: hideSettingsFromSwipe,
                onSwipeRight: showSettingsFromSwipe
            )
        )
        .preferredColorScheme(nil)
        .environment(\.locale, selectedLocale)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { reportPreferredHeight() }
        .onChange(of: preferredHeight) { _ in reportPreferredHeight() }
    }

    private var selectedLocale: Locale {
        _ = preferences.appLanguage
        return L10n.locale
    }

    private var schedulePage: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch service.access {
        case .unknown:
            PermissionView(
                symbol: "calendar.badge.exclamationmark",
                title: L10n.text("permission.title"),
                detail: L10n.text("permission.detail"),
                buttonTitle: L10n.text("permission.allow"),
                action: service.requestAccess
            )
        case .denied:
            PermissionView(
                symbol: "lock.fill",
                title: L10n.text("permission.denied_title"),
                detail: L10n.text("permission.denied_detail"),
                buttonTitle: L10n.text("permission.open_settings"),
                action: service.openCalendarPrivacySettings
            )
        case .granted:
            schedule
        }
    }

    private var schedule: some View {
        ScrollView {
            VStack(spacing: 10) {
                LazyVStack(spacing: 16) {
                    ForEach(daysWithEvents, id: \.self) { day in
                        DaySection(
                            day: day,
                            events: events(on: day),
                            now: service.now,
                            onOpenEvent: onOpenEvent
                        )
                    }
                }

                PagePositionIndicator(
                    showingSettings: false,
                    onSwitchPage: showSettings
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 10)
            .onContentHeightChange { height in
                guard abs(scheduleContentHeight - height) >= 1 else { return }
                scheduleContentHeight = height
            }
        }
        .scrollIndicators(.hidden)
    }

    private var preferredHeight: CGFloat {
        min(rawContentHeight, maximumPopoverHeight)
    }

    private var rawContentHeight: CGFloat {
        if navigation.showingSettings {
            if settingsContentHeight > 0 { return settingsContentHeight }
            return 383 + CGFloat(service.calendars.count) * 34.5
        }

        switch service.access {
        case .unknown, .denied:
            return 360
        case .granted:
            if scheduleContentHeight > 0 { return scheduleContentHeight }
            let dayHeights = daysWithEvents.reduce(CGFloat.zero) { total, day in
                let count = events(on: day).count
                let rows = CGFloat(count) * 51
                let rowSpacing = CGFloat(max(0, count - 1)) * 5
                return total + 25 + rows + rowSpacing
            }
            let sectionSpacing = CGFloat(daysWithEvents.count) * 16
            return 38 + dayHeights + sectionSpacing + 40
        }
    }

    private var maximumPopoverHeight: CGFloat {
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        return floor((activeScreen?.visibleFrame.height ?? 900) / 2)
    }

    private func reportPreferredHeight() {
        let height = preferredHeight
        DispatchQueue.main.async {
            onPreferredHeightChange(height)
        }
    }

    private func showSettings() {
        guard !navigation.showingSettings else { return }
        withAnimation(pageAnimation) {
            navigation.showingSettings = true
        }
    }

    private func hideSettings() {
        guard navigation.showingSettings else { return }
        withAnimation(pageAnimation) {
            navigation.showingSettings = false
        }
    }

    private func showSettingsFromSwipe() {
        guard !navigation.showingSettings else { return }
        withAnimation(pageAnimation) {
            navigation.showingSettings = true
        }
    }

    private func hideSettingsFromSwipe() {
        hideSettings()
    }

    /// Include every calendar date touched by the rolling 48-hour window.
    /// Depending on the current time, this spans portions of three dates.
    private var visibleDays: [Date] {
        let start = calendar.startOfDay(for: service.now)
        let last = calendar.startOfDay(for: popoverEnd)
        let dayCount = calendar.dateComponents([.day], from: start, to: last).day ?? 0
        return (0...max(0, dayCount)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private var popoverEnd: Date {
        service.now.addingTimeInterval(popoverLookAhead)
    }

    private var daysWithEvents: [Date] {
        visibleDays.filter { !events(on: $0).isEmpty }
    }

    private func events(on day: Date) -> [CalendarEvent] {
        PopoverEventSelector.events(
            on: day,
            from: service.weekEvents,
            now: service.now,
            until: popoverEnd,
            calendar: calendar
        )
    }
}

struct PagePositionIndicator: View {
    let showingSettings: Bool
    let onSwitchPage: () -> Void

    private let trackWidth: CGFloat = 42
    private let thumbWidth: CGFloat = 18
    private let inset: CGFloat = 2

    var body: some View {
        Button(action: onSwitchPage) {
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
                    )
                    .frame(width: trackWidth, height: 7)

                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.16))
                    .frame(width: thumbWidth, height: 3.5)
                    .offset(
                        x: showingSettings
                            ? trackWidth - thumbWidth - inset
                            : inset
                    )
            }
            .frame(width: 58, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(
            .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.34),
            value: showingSettings
        )
        .help(L10n.text("navigation.swipe_hint"))
        .accessibilityLabel(L10n.text("navigation.page_control"))
        .accessibilityValue(
            L10n.text(
                showingSettings
                    ? "navigation.settings_page"
                    : "navigation.calendar_page"
            )
        )
        .accessibilityHint(L10n.text("navigation.swipe_hint"))
    }
}

enum PopoverEventSelector {
    static func events(
        on day: Date,
        from events: [CalendarEvent],
        now: Date,
        until end: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [CalendarEvent] {
        events.filter {
            $0.endDate > now
                && $0.startDate < end
                && calendar.isDate($0.startDate, inSameDayAs: day)
        }
    }
}

private struct DaySection: View {
    let day: Date
    let events: [CalendarEvent]
    let now: Date
    let onOpenEvent: (CalendarEvent) -> Void

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle)
                    .font(.headline)
                Text(
                    day,
                    format: .dateTime
                        .month(.abbreviated)
                        .day()
                        .locale(L10n.locale)
                )
                    .font(.headline)
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            VStack(spacing: 5) {
                ForEach(events) { event in
                    EventRow(event: event, now: now, onOpen: { onOpenEvent(event) })
                }
            }
        }
    }

    private var dayTitle: String {
        if calendar.isDateInToday(day) { return L10n.text("day.today") }
        if calendar.isDateInTomorrow(day) { return L10n.text("day.tomorrow") }
        return day.formatted(.dateTime.weekday(.wide).locale(L10n.locale))
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(nsColor: event.calendarColor))
                    .frame(width: 3.5)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(timeLabel)
                        if let location = event.location {
                            Text("•")
                            Text(location).lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(L10n.text("action.open_in_calendar"))
    }

    private var isActive: Bool {
        !event.isAllDay && event.startDate <= now && event.endDate > now
    }

    private var timeLabel: String {
        if event.isAllDay { return L10n.text("event.all_day") }
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
            .locale(L10n.locale)
        return "\(event.startDate.formatted(style)) – \(event.endDate.formatted(style))"
    }

    private var accessibilityLabel: String {
        let state = isActive ? L10n.text("event.active_suffix") : ""
        let location = event.location.map { L10n.format("event.location_suffix", $0) } ?? ""
        return L10n.format(
            "event.accessibility_format",
            event.title,
            state,
            timeLabel,
            location
        )
    }
}

private struct PermissionView: View {
    let symbol: String
    let title: String
    let detail: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 15) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 68, height: 68)
                .background(Circle().fill(.white.opacity(0.08)))
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 280)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
