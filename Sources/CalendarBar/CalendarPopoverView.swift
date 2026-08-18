import AppKit
import SwiftUI

struct CalendarPopoverView: View {
    @ObservedObject var service: CalendarService
    let onPreferredHeightChange: (CGFloat) -> Void
    let onTestReminder: () -> Void
    @State private var showingSettings = false

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        ZStack {
            if showingSettings {
                SettingsView(
                    service: service,
                    onDone: { showingSettings = false },
                    onTestReminder: onTestReminder
                )
            } else {
                schedulePage
            }
        }
        .frame(width: AppLayout.popoverWidth, height: preferredHeight)
        .preferredColorScheme(nil)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { reportPreferredHeight() }
        .onChange(of: preferredHeight) { _ in reportPreferredHeight() }
    }

    private var schedulePage: some View {
        ZStack {
            VisualEffectView(material: .popover)
                .ignoresSafeArea()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.access {
        case .unknown:
            PermissionView(
                symbol: "calendar.badge.exclamationmark",
                title: "让日程出现在菜单栏",
                detail: "CalendarBar 只在本机读取你选择的日历，不会上传任何数据。",
                buttonTitle: "允许访问日历",
                action: service.requestAccess
            )
        case .denied:
            PermissionView(
                symbol: "lock.fill",
                title: "日历访问已关闭",
                detail: "请在“系统设置 → 隐私与安全性 → 日历”中允许 CalendarBar。",
                buttonTitle: "打开系统设置",
                action: service.openCalendarPrivacySettings
            )
        case .granted:
            schedule
        }
    }

    private var schedule: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(daysWithEvents, id: \.self) { day in
                    DaySection(
                        day: day,
                        events: events(on: day),
                        now: service.now
                    )
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button(action: openCalendarApp) {
                        Image(systemName: "calendar")
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("打开 Apple 日历")

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("设置")
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private var preferredHeight: CGFloat {
        min(rawContentHeight, maximumPopoverHeight)
    }

    private var rawContentHeight: CGFloat {
        if showingSettings { return 620 }

        switch service.access {
        case .unknown, .denied:
            return 360
        case .granted:
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

    private var daysInWeek: [Date] {
        let start = calendar.startOfDay(for: service.now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var daysWithEvents: [Date] {
        daysInWeek.filter { !events(on: $0).isEmpty }
    }

    private func events(on day: Date) -> [CalendarEvent] {
        service.weekEvents.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
    }

    private func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
    }
}

private struct DaySection: View {
    let day: Date
    let events: [CalendarEvent]
    let now: Date

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(day, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            VStack(spacing: 5) {
                ForEach(events) { event in
                    EventRow(event: event, now: now)
                }
            }
        }
    }

    private var dayTitle: String {
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInTomorrow(day) { return "明天" }
        return day.formatted(.dateTime.weekday(.wide))
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(nsColor: event.calendarColor))
                .frame(width: 3.5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(event.title)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                        .lineLimit(1)
                    if isActive {
                        Text("NOW")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                HStack(spacing: 6) {
                    Text(timeLabel)
                    if let location = event.location {
                        Text("•")
                        Text(location).lineLimit(1)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035))
        )
    }

    private var isActive: Bool {
        !event.isAllDay && event.startDate <= now && event.endDate > now
    }

    private var timeLabel: String {
        if event.isAllDay { return "全天" }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))"
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
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 12))
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
