import Foundation

/// Device errors also appear outside the app, so read the shared preference
/// without depending on SwiftUI or the executable target.
enum DeviceLocalization {
    static func tr(_ chinese: String, _ english: String) -> String {
        let saved = UserDefaults.standard.string(forKey: "vibeWand.language")
        let chineseSelected: Bool
        switch saved {
        case "zhHans": chineseSelected = true
        case "english": chineseSelected = false
        default: chineseSelected = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        }
        return chineseSelected ? chinese : english
    }
}
