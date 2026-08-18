import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var service: CalendarService
    @ObservedObject private var preferences: Preferences
    let onDone: () -> Void
    let onTestReminder: () -> Void

    init(
        service: CalendarService,
        onDone: @escaping () -> Void,
        onTestReminder: @escaping () -> Void
    ) {
        self.service = service
        preferences = service.preferences
        self.onDone = onDone
        self.onTestReminder = onTestReminder
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onDone) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("返回日程")

                    VStack(alignment: .leading, spacing: 2) {
                        Text("设置")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                    }
                    Spacer()
                }
                .padding(20)

                Divider().opacity(0.35)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        refreshSection
                        calendarsSection
                        visibilitySection
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var refreshSection: some View {
        VStack(spacing: 0) {
            Button {
                service.refresh()
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("刷新日历")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)

            Divider().opacity(0.25)
                .padding(.vertical, 10)

            Button(action: onTestReminder) {
                HStack(spacing: 11) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("测试提醒岛")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        }
        .glassCard()
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("显示范围")

            VStack(spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("显示未来事件")
                            .font(.system(size: 13, weight: .medium))
                        Text("只显示这个时间范围内的下一个日程")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField(
                        "24",
                        value: Binding(
                            get: { preferences.lookAheadHours },
                            set: { preferences.lookAheadHours = min(max($0, 1), 72) }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    Text("小时")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }

            }
            .glassCard()
        }
    }

    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("日历")
                Spacer()
                Button("全部选择") {
                    preferences.selectedCalendarIDs = []
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 0) {
                ForEach(Array(service.calendars.enumerated()), id: \.element.id) { index, calendar in
                    Button {
                        toggle(calendar.id)
                    } label: {
                        HStack(spacing: 11) {
                            Circle()
                                .fill(Color(nsColor: calendar.color))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(calendar.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(calendar.source)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: isSelected(calendar.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected(calendar.id) ? Color.accentColor : Color.secondary.opacity(0.5))
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if index < service.calendars.count - 1 {
                        Divider().opacity(0.25)
                    }
                }
            }
            .glassCard(padding: 12)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.7)
    }

    private func isSelected(_ id: String) -> Bool {
        preferences.selectedCalendarIDs.isEmpty || preferences.selectedCalendarIDs.contains(id)
    }

    private func toggle(_ id: String) {
        if preferences.selectedCalendarIDs.isEmpty {
            preferences.selectedCalendarIDs = Set(service.calendars.map(\.id))
        }

        if preferences.selectedCalendarIDs.contains(id) {
            guard preferences.selectedCalendarIDs.count > 1 else { return }
            preferences.selectedCalendarIDs.remove(id)
        } else {
            preferences.selectedCalendarIDs.insert(id)
        }
    }
}
