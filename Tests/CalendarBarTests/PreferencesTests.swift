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
    }
}
