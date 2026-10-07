import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Codable {
    case zhHans, english

    var label: String { self == .zhHans ? "简体中文" : "English" }
    var locale: Locale { Locale(identifier: self == .zhHans ? "zh-Hans" : "en") }

    static func preferred(in languages: [String]) -> AppLanguage {
        languages.first?.lowercased().hasPrefix("zh") == true ? .zhHans : .english
    }
}

/// One explicit preference is shared by SwiftUI, AppKit and device diagnostics.
/// Strings are resolved at presentation time; stored mappings remain language independent.
final class L10n: ObservableObject {
    static let storageKey = "vibeWand.language"
    static let languageDidChange = Notification.Name("VibeWand.languageDidChange")
    static let shared = L10n()
    private let defaults: UserDefaults
    private let presentationLock = NSLock()
    private var presentationLanguage: AppLanguage

    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            presentationLock.lock()
            presentationLanguage = language
            presentationLock.unlock()
            defaults.set(language.rawValue, forKey: Self.storageKey)
            NotificationCenter.default.post(name: Self.languageDidChange, object: self)
        }
    }

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        let initialLanguage = defaults.string(forKey: Self.storageKey).flatMap(AppLanguage.init(rawValue:))
            ?? AppLanguage.preferred(in: preferredLanguages)
        presentationLanguage = initialLanguage
        language = initialLanguage
    }

    func translate(_ chinese: String, _ english: String) -> String {
        // Accessibility inspection resolves status text on a background queue;
        // it must not read SwiftUI's mutable @Published storage directly.
        presentationLock.lock()
        let selectedLanguage = presentationLanguage
        presentationLock.unlock()
        return selectedLanguage == .zhHans ? chinese : english
    }

    static func tr(_ chinese: String, _ english: String) -> String {
        shared.translate(chinese, english)
    }
}
