import AppKit
import Foundation

/// Interface language. English is the default; French is used when chosen,
/// or when "System" is selected and the Mac's first preferred language is French.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case french = "fr"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    /// The value chosen in Settings (not necessarily the one in use until relaunch).
    static var stored: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// The choice in effect for this launch.
    static let launchChoice: AppLanguage = stored

    /// Resolved once at launch, so the whole interface stays consistent.
    static let isFrench: Bool = {
        switch launchChoice {
        case .french: return true
        case .english: return false
        case .system:
            // AppleLanguages may have been overridden by us; read the system list instead.
            let system = (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String])
                ?? Locale.preferredLanguages
            return system.first?.lowercased().hasPrefix("fr") ?? false
        }
    }()

    /// Code used for online sources (Wikipedia, Wikidata).
    static var code: String { isFrench ? "fr" : "en" }

    var label: String {
        switch self {
        case .system: return L("Langue du système", "System language")
        case .english: return "English"
        case .french: return "Français"
        }
    }

    /// Saves the choice and aligns the system menus (Edit, Window…) with it.
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(rawValue, forKey: Self.storageKey)
        switch self {
        case .system: defaults.removeObject(forKey: "AppleLanguages")
        case .english: defaults.set(["en"], forKey: "AppleLanguages")
        case .french: defaults.set(["fr"], forKey: "AppleLanguages")
        }
    }

    /// Relaunches the app so the new language applies everywhere.
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Picks the French or English version of a user-facing string.
func L(_ french: String, _ english: String) -> String {
    AppLanguage.isFrench ? french : english
}
