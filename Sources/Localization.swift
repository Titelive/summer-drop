import AppKit
import Foundation
import SwiftUI

/// Interface languages. English is the source language; the others are loaded
/// from Resources/Translations/<code>.json, keyed by the English text.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case japanese = "ja"
    case chinese = "zh-Hans"

    static let storageKey = "appLanguage"
    /// Value stored when the app follows the Mac's language.
    static let systemValue = "system"

    var id: String { rawValue }

    /// Name of the language, written in that language.
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .french: return "Français"
        case .spanish: return "Español"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .japanese: return "日本語"
        case .chinese: return "简体中文"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .french: return "🇫🇷"
        case .spanish: return "🇪🇸"
        case .german: return "🇩🇪"
        case .italian: return "🇮🇹"
        case .portuguese: return "🇧🇷"
        case .japanese: return "🇯🇵"
        case .chinese: return "🇨🇳"
        }
    }

    /// Wikipedia subdomain and sitelink prefix.
    var wikiCode: String { self == .chinese ? "zh" : rawValue }
    /// Wikidata label language.
    var wikidataCode: String { self == .chinese ? "zh-hans" : rawValue }

    /// The setting: "system" or a language code.
    static var storedSetting: String {
        UserDefaults.standard.string(forKey: storageKey) ?? systemValue
    }

    /// The Mac's own language, if Summer Drop speaks it (English otherwise).
    static var systemLanguage: AppLanguage {
        let list = (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String])
            ?? Locale.preferredLanguages
        for code in list {
            let lower = code.lowercased()
            if lower.hasPrefix("zh") { return lower.contains("hant") || lower.hasSuffix("-tw") || lower.hasSuffix("-hk") ? .english : .chinese }
            if let match = allCases.first(where: { lower.hasPrefix($0.rawValue) }) { return match }
        }
        return .english
    }

    /// The language in use right now.
    static var current: AppLanguage { Translations.shared.language }

    /// Applies a setting ("system" or a code) immediately and saves it.
    static func apply(setting: String) {
        let defaults = UserDefaults.standard
        let language = AppLanguage(rawValue: setting) ?? systemLanguage
        Translations.shared.load(language)
        defaults.set(setting, forKey: storageKey)
        // Standard menus (Edit, Window…) follow AppleLanguages at the next launch.
        if setting == systemValue {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
    }
}

/// Holds the translation table of the current language. Thread-safe, so actors can use it.
final class Translations: @unchecked Sendable {
    static let shared = Translations()

    private let lock = NSLock()
    private var _language: AppLanguage = .english
    private var table: [String: String] = [:]

    private init() {
        let setting = AppLanguage.storedSetting
        load(AppLanguage(rawValue: setting) ?? AppLanguage.systemLanguage)
    }

    var language: AppLanguage {
        lock.lock(); defer { lock.unlock() }
        return _language
    }

    func load(_ language: AppLanguage) {
        var newTable: [String: String] = [:]
        if language != .english,
           let url = Bundle.main.url(forResource: language.rawValue, withExtension: "json", subdirectory: "Translations"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            newTable = decoded
        }
        lock.lock()
        _language = language
        table = newTable
        lock.unlock()
    }

    func lookup(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return table[key] ?? key
    }
}

/// Translates an English string. Placeholders {0}, {1}… are replaced by `args`.
func L(_ english: String, _ args: String...) -> String {
    var text = Translations.shared.lookup(english)
    for (index, value) in args.enumerated() {
        text = text.replacingOccurrences(of: "{\(index)}", with: value)
    }
    return text
}

// MARK: - Pickers

/// Compact picker for Settings.
struct LanguagePicker: View {
    @AppStorage(AppLanguage.storageKey) private var setting = AppLanguage.systemValue

    var body: some View {
        Picker(L("App language"), selection: Binding(
            get: { setting },
            set: { AppLanguage.apply(setting: $0) }
        )) {
            Text(L("Same as the Mac ({0})", AppLanguage.systemLanguage.nativeName)).tag(AppLanguage.systemValue)
            Divider()
            ForEach(AppLanguage.allCases) { language in
                Text("\(language.flag)  \(language.nativeName)").tag(language.rawValue)
            }
        }
    }
}

/// Grid of language chips, shown on the first page of the tutorial.
struct LanguageChoiceGrid: View {
    @AppStorage(AppLanguage.storageKey) private var setting = AppLanguage.systemValue

    private let columns = Array(repeating: GridItem(.fixed(118), spacing: 8), count: 4)

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AppLanguage.allCases) { language in
                    chip(language)
                }
            }
        }
    }

    private func chip(_ language: AppLanguage) -> some View {
        let selected = AppLanguage.current == language
        return Button {
            withAnimation(.spring(duration: 0.35)) {
                AppLanguage.apply(setting: language.rawValue)
            }
        } label: {
            HStack(spacing: 6) {
                Text(language.flag)
                Text(language.nativeName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.callout.weight(selected ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(
            selected ? Glass.regular.tint(Color.accentColor.opacity(0.35)).interactive() : Glass.regular.interactive(),
            in: .capsule
        )
        .help(language.nativeName)
    }
}
