import Foundation

enum L10n {
    private static let resourceBundle: Bundle = {
        if Bundle.main.path(forResource: "en", ofType: "lproj") != nil {
            return .main
        }
        return .module
    }()

    private static var currentBundle: Bundle {
        guard let identifier = AppLanguage.stored(in: .standard).localizationIdentifier,
              let path = resourceBundle.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return resourceBundle
        }
        return bundle
    }

    static func text(_ key: String) -> String {
        currentBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static var locale: Locale {
        Locale(identifier: currentBundle.preferredLocalizations.first ?? "en")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: locale,
            arguments: arguments
        )
    }

    static func text(_ key: String, language: String) -> String {
        guard let path = resourceBundle.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
