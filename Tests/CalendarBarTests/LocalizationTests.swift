import XCTest
@testable import CalendarBar

final class LocalizationTests: XCTestCase {
    func testInAppLanguageOverrideSelectsRequestedBundle() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: AppLanguage.defaultsKey)
        let previousSystemValue = defaults.object(forKey: AppLanguage.systemDefaultsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: AppLanguage.defaultsKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.defaultsKey)
            }
            if let previousSystemValue {
                defaults.set(previousSystemValue, forKey: AppLanguage.systemDefaultsKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.systemDefaultsKey)
            }
        }

        AppLanguage.english.persist(in: defaults)
        XCTAssertEqual(L10n.text("settings.language"), "Language")

        AppLanguage.simplifiedChinese.persist(in: defaults)
        XCTAssertEqual(L10n.text("settings.language"), "语言")
    }

    func testEnglishResourcesAreAvailable() {
        XCTAssertEqual(
            L10n.text("permission.allow", language: "en"),
            "Allow Calendar Access"
        )
        XCTAssertEqual(
            L10n.text("settings.launch_at_login", language: "en"),
            "Launch at login"
        )
        XCTAssertEqual(
            L10n.text("navigation.swipe_hint", language: "en"),
            "Swipe horizontally to switch pages"
        )
        XCTAssertEqual(
            L10n.text("appearance.system", language: "en"),
            "Follow System"
        )
    }

    func testSimplifiedChineseResourcesAreAvailable() {
        XCTAssertEqual(
            L10n.text("permission.allow", language: "zh-Hans"),
            "允许访问日历"
        )
        XCTAssertEqual(
            L10n.text("settings.launch_at_login", language: "zh-Hans"),
            "登录时启动"
        )
        XCTAssertEqual(
            L10n.text("navigation.swipe_hint", language: "zh-Hans"),
            "左右滑动以切换页面"
        )
    }
}
