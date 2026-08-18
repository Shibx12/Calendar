import Foundation

@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let selectedCalendarIDs = "selectedCalendarIDs"
        static let lookAheadHours = "lookAheadHours"
        static let launchAtLoginHintDismissed = "launchAtLoginHintDismissed"
    }

    private let defaults: UserDefaults

    @Published var selectedCalendarIDs: Set<String> {
        didSet { defaults.set(Array(selectedCalendarIDs), forKey: Key.selectedCalendarIDs) }
    }

    @Published var lookAheadHours: Int {
        didSet { defaults.set(lookAheadHours, forKey: Key.lookAheadHours) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedCalendarIDs = Set(defaults.stringArray(forKey: Key.selectedCalendarIDs) ?? [])
        let storedHours = defaults.integer(forKey: Key.lookAheadHours)
        lookAheadHours = storedHours == 0 ? 24 : storedHours
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
