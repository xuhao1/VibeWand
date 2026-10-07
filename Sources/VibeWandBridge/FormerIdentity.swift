import AppKit
import InputLink

/// VibeWand was `org.vibekey.bridge` until 0.11.0. macOS keeps an app's settings under its identifier and tells
/// two copies apart by it, so the first launch under the new one takes over what the former one left, and a copy
/// of the former one that is still running is asked to quit: both would answer the same devices.
enum FormerIdentity {
    static let adopted = "formerSettingsAdopted"
    /// Settings whose own names carried the former name.
    static let renamed = ["VibeKeyBridge.overlayOrigin": "VibeWandBridge.overlayOrigin",
                          "VibeKeyBridge.overlayAnchor": "VibeWandBridge.overlayAnchor",
                          "VibeKeyBridge.overlayDeviceBelow": "VibeWandBridge.overlayDeviceBelow"]

    /// Once, before anything reads a setting. What is already set under the new identifier wins, and the former
    /// settings stay where they are for a version that still looks there.
    static func adopt(from former: String = InputLink.formerOwner, as domain: String? = Bundle.main.bundleIdentifier, in defaults: UserDefaults = .standard) {
        guard let domain, domain != former else { return }
        let own = defaults.persistentDomain(forName: domain) ?? [:]
        guard own[adopted] == nil else { return }
        var settings = defaults.persistentDomain(forName: former) ?? [:]
        for (old, new) in renamed { settings[new] = settings.removeValue(forKey: old) }
        settings.merge(own) { _, mine in mine }
        settings[adopted] = true
        defaults.setPersistentDomain(settings, forName: domain)
    }
    static func retire() {
        NSRunningApplication.runningApplications(withBundleIdentifier: InputLink.formerOwner).forEach { $0.terminate() }
    }
}
