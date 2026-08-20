import Foundation
import XCTest
@testable import CalendarBar

@MainActor
final class PreferencesTests: XCTestCase {
    func testLookAheadDefaultsToTwentyFourHours() {
        let suiteName = "CalendarBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.lookAheadHours, 24)
        XCTAssertEqual(preferences.upcomingWhileCurrentHours, 5)
        XCTAssertTrue(preferences.showsCurrentEvent)
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertEqual(preferences.appLanguage, .system)
    }

    func testCurrentEventVisibilityPersists() {
        let suiteName = "CalendarBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)
        preferences.showsCurrentEvent = false

        XCTAssertFalse(Preferences(defaults: defaults).showsCurrentEvent)
    }

    func testUpcomingWhileCurrentRangePersists() {
        let suiteName = "CalendarBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)
        preferences.upcomingWhileCurrentHours = 8

        XCTAssertEqual(Preferences(defaults: defaults).upcomingWhileCurrentHours, 8)
    }

    func testAppearancePersists() {
        let suiteName = "CalendarBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)
        preferences.appearance = .dark

        XCTAssertEqual(Preferences(defaults: defaults).appearance, .dark)
    }

    func testAppLanguagePersists() {
        let suiteName = "CalendarBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)
        preferences.appLanguage = .simplifiedChinese

        XCTAssertEqual(
            Preferences(defaults: defaults).appLanguage,
            .simplifiedChinese
        )
    }
}
