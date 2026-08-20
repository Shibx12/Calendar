import Foundation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: L10n.text("appearance.system")
        case .light: L10n.text("appearance.light")
        case .dark: L10n.text("appearance.dark")
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let defaultsKey = "appLanguage"
    static let systemDefaultsKey = "AppleLanguages"

    var id: Self { self }

    var localizationIdentifier: String? {
        self == .system ? nil : rawValue
    }

    static func stored(in defaults: UserDefaults) -> AppLanguage {
        guard let identifier = defaults.string(forKey: defaultsKey) else {
            return .system
        }
        if identifier.hasPrefix("zh-Hans") { return .simplifiedChinese }
        if identifier.hasPrefix("en") { return .english }
        return .system
    }

    func persist(in defaults: UserDefaults) {
        if let localizationIdentifier {
            defaults.set(rawValue, forKey: Self.defaultsKey)
            defaults.set([localizationIdentifier], forKey: Self.systemDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
            defaults.removeObject(forKey: Self.systemDefaultsKey)
        }
    }

    var title: String {
        switch self {
        case .system: L10n.text("language.system")
        case .english: L10n.text("language.english")
        case .simplifiedChinese: L10n.text("language.simplified_chinese")
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let selectedCalendarIDs = "selectedCalendarIDs"
        static let lookAheadHours = "lookAheadHours"
        static let upcomingWhileCurrentHours = "upcomingWhileCurrentHours"
        static let showsCurrentEvent = "showsCurrentEvent"
        static let appearance = "appearance"
        static let launchAtLoginHintDismissed = "launchAtLoginHintDismissed"
    }

    private let defaults: UserDefaults

    @Published var selectedCalendarIDs: Set<String> {
        didSet { defaults.set(Array(selectedCalendarIDs), forKey: Key.selectedCalendarIDs) }
    }

    @Published var lookAheadHours: Int {
        didSet { defaults.set(lookAheadHours, forKey: Key.lookAheadHours) }
    }

    @Published var upcomingWhileCurrentHours: Int {
        didSet { defaults.set(upcomingWhileCurrentHours, forKey: Key.upcomingWhileCurrentHours) }
    }

    @Published var showsCurrentEvent: Bool {
        didSet { defaults.set(showsCurrentEvent, forKey: Key.showsCurrentEvent) }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published var appLanguage: AppLanguage {
        didSet { appLanguage.persist(in: defaults) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedCalendarIDs = Set(defaults.stringArray(forKey: Key.selectedCalendarIDs) ?? [])
        let storedHours = defaults.integer(forKey: Key.lookAheadHours)
        lookAheadHours = storedHours == 0 ? 24 : storedHours
        let storedConcurrentHours = defaults.integer(forKey: Key.upcomingWhileCurrentHours)
        upcomingWhileCurrentHours = storedConcurrentHours == 0 ? 5 : storedConcurrentHours
        showsCurrentEvent = defaults.object(forKey: Key.showsCurrentEvent) == nil
            ? true
            : defaults.bool(forKey: Key.showsCurrentEvent)
        appearance = defaults.string(forKey: Key.appearance)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        appLanguage = AppLanguage.stored(in: defaults)
    }

    func toggleCalendar(_ id: String) {
        if selectedCalendarIDs.contains(id) {
            selectedCalendarIDs.remove(id)
        } else {
            selectedCalendarIDs.insert(id)
        }
    }

    func selectAll(_ ids: [String]) {
        selectedCalendarIDs = Set(ids)
    }
}
