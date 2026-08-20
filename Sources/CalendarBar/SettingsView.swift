import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var service: CalendarService
    @ObservedObject private var preferences: Preferences
    @StateObject private var loginItemManager = LoginItemManager()
    let onTestReminder: () -> Void
    let onSelectCalendar: () -> Void
    let onContentHeightChange: (CGFloat) -> Void
    @ScaledMetric(relativeTo: .body) private var numericFieldWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var numericFieldHeight: CGFloat = 28

    init(
        service: CalendarService,
        onTestReminder: @escaping () -> Void,
        onSelectCalendar: @escaping () -> Void,
        onContentHeightChange: @escaping (CGFloat) -> Void
    ) {
        self.service = service
        preferences = service.preferences
        self.onTestReminder = onTestReminder
        self.onSelectCalendar = onSelectCalendar
        self.onContentHeightChange = onContentHeightChange
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 18) {
                    actionsGroup
                    calendarsSection
                    displaySection
                    systemSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PagePositionIndicator(
                    showingSettings: true,
                    onSwitchPage: onSelectCalendar
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .onContentHeightChange(onContentHeightChange)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loginItemManager.refresh()
        }
    }

    private var actionsGroup: some View {
        SettingsGroup {
            SettingsActionRow(
                symbol: "bell",
                title: L10n.text("settings.test_reminder"),
                action: onTestReminder
            )
        }
    }

    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SettingsSectionLabel(L10n.text("settings.calendars"))
                Spacer()
                Button(L10n.text("settings.select_all")) {
                    preferences.selectedCalendarIDs = []
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 2)

            SettingsGroup {
                ForEach(Array(service.calendars.enumerated()), id: \.element.id) { index, calendar in
                    Button {
                        toggle(calendar.id)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(nsColor: calendar.color))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)

                            Text(calendar.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .opacity(isSelected(calendar.id) ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SettingsRowButtonStyle())
                    .accessibilityLabel(calendar.title)
                    .accessibilityValue(
                        isSelected(calendar.id)
                            ? L10n.text("settings.selected")
                            : L10n.text("settings.not_selected")
                    )

                    if index < service.calendars.count - 1 {
                        SettingsDivider(leadingInset: 30)
                    }
                }
            }
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(L10n.text("settings.display"))
                .padding(.horizontal, 2)

            SettingsGroup {
                HStack(spacing: 12) {
                    Text(L10n.text("settings.appearance"))
                        .font(.body)

                    Spacer(minLength: 8)

                    Menu {
                        ForEach(AppAppearance.allCases) { appearance in
                            Button {
                                preferences.appearance = appearance
                            } label: {
                                if preferences.appearance == appearance {
                                    Label(appearance.title, systemImage: "checkmark")
                                } else {
                                    Text(appearance.title)
                                }
                            }
                        }
                    } label: {
                        Text(preferences.appearance.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(minHeight: numericFieldHeight)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(L10n.text("settings.appearance"))
                    .accessibilityValue(preferences.appearance.title)
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, 12)

                SettingsDivider(leadingInset: 12)

                HStack(spacing: 12) {
                    Text(L10n.text("settings.language"))
                        .font(.body)

                    Spacer(minLength: 8)

                    Menu {
                        ForEach(AppLanguage.allCases) { language in
                            Button {
                                preferences.appLanguage = language
                            } label: {
                                if preferences.appLanguage == language {
                                    Label(language.title, systemImage: "checkmark")
                                } else {
                                    Text(language.title)
                                }
                            }
                        }
                    } label: {
                        Text(preferences.appLanguage.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(minHeight: numericFieldHeight)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(L10n.text("settings.language"))
                    .accessibilityValue(preferences.appLanguage.title)
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, 12)

                SettingsDivider(leadingInset: 12)

                HStack(spacing: 12) {
                    Text(L10n.text("settings.future_event_range"))
                        .font(.body)

                    Spacer(minLength: 8)

                    HStack(spacing: 5) {
                        TextField(
                            "24",
                            value: Binding(
                                get: { preferences.lookAheadHours },
                                set: { preferences.lookAheadHours = min(max($0, 1), 72) }
                            ),
                            format: .number
                        )
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.body)
                        .monospacedDigit()
                        .frame(width: numericFieldWidth)
                        .frame(minHeight: numericFieldHeight)
                        .contentShape(Rectangle())

                        Text(L10n.text("settings.hours"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, 12)

                SettingsDivider(leadingInset: 12)

                HStack(spacing: 12) {
                    Text(L10n.text("settings.show_next_event"))
                        .font(.body)

                    Spacer(minLength: 8)

                    HStack(spacing: 5) {
                        TextField(
                            "5",
                            value: Binding(
                                get: { preferences.upcomingWhileCurrentHours },
                                set: { preferences.upcomingWhileCurrentHours = min(max($0, 1), 72) }
                            ),
                            format: .number
                        )
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.body)
                        .monospacedDigit()
                        .frame(width: numericFieldWidth)
                        .frame(minHeight: numericFieldHeight)
                        .contentShape(Rectangle())

                        Text(L10n.text("settings.hours"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, 12)

                SettingsDivider(leadingInset: 12)

                HStack(spacing: 12) {
                    Text(L10n.text("settings.show_current_event"))
                        .font(.body)

                    Spacer(minLength: 8)

                    Toggle(
                        L10n.text("settings.show_current_event"),
                        isOn: $preferences.showsCurrentEvent
                    )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, 12)
            }
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(L10n.text("settings.system"))
                .padding(.horizontal, 2)

            SettingsGroup {
                SettingsActionRow(
                    symbol: "arrow.clockwise",
                    title: L10n.text("action.refresh_calendar"),
                    symbolPlacement: .trailing,
                    isAnimating: service.isRefreshing,
                    action: service.refresh
                )

                SettingsDivider(leadingInset: 12)

                HStack(spacing: 12) {
                    Text(L10n.text("settings.launch_at_login"))
                        .font(.body)

                    Spacer(minLength: 8)

                    Toggle(
                        L10n.text("settings.launch_at_login"),
                        isOn: Binding(
                            get: { loginItemManager.isEnabled },
                            set: { loginItemManager.setEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, 12)
            }
        }
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

private struct SettingsSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

private struct SettingsGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.038))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SettingsActionRow: View {
    let symbol: String
    let title: String
    var symbolPlacement: SymbolPlacement = .leading
    var isAnimating = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if symbolPlacement == .leading {
                    actionIcon
                }

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                if symbolPlacement == .trailing {
                    actionIcon
                }
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private var actionIcon: some View {
        RefreshableActionIcon(symbol: symbol, isAnimating: isAnimating)
    }

    enum SymbolPlacement {
        case leading
        case trailing
    }
}

private struct RefreshableActionIcon: View {
    let symbol: String
    let isAnimating: Bool
    @State private var rotation = 0.0

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 18)
            .rotationEffect(.degrees(rotation))
            .onAppear(perform: updateAnimation)
            .onChange(of: isAnimating) { _ in
                updateAnimation()
            }
            .accessibilityHidden(true)
    }

    private func updateAnimation() {
        if isAnimating {
            rotation = 0
            withAnimation(.linear(duration: 0.75).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                rotation = 0
            }
        }
    }
}

private struct SettingsDivider: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, leadingInset)
    }
}

private struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.primary.opacity(0.06)
                    : Color.clear
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
