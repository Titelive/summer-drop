import SwiftUI
import AppKit
import QuartzCore

// MARK: - Bouton de thème clair / sombre (barre d'outils), commun aux apps Titelive
//
// Un clic bascule Clair ↔ Sombre (depuis Automatique : passe au mode opposé à l'apparence
// actuelle). Le chevron ouvre le menu Automatique / Clair / Sombre. ⌘⇧L bascule aussi.
// Le choix est mémorisé sous la même clé que le sélecteur des Réglages de l'app.
//
//   ToolbarItem { ThemeToggleButton(storageKey: "appearance") }                      // thème générique
//   ToolbarItem { ThemeToggleButton(storageKey: AppTheme.key) { AppTheme.select(…) } } // thème de l'app
// Fichier identique dans toutes les apps Titelive.

enum ThemeChoice: CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }

    var label: String {
        switch self {
        case .system: ThemeText.system
        case .light: ThemeText.light
        case .dark: ThemeText.dark
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// Summer Drop est traduite : les textes passent par L() (Resources/Translations).
enum ThemeText {
    static var menu: String { L("Appearance") }
    static var system: String { L("Automatic") }
    static var light: String { L("Light") }
    static var dark: String { L("Dark") }
    static var toggle: String { L("Switch between light and dark mode") }
    static var help: String { toggle + " (⇧⌘L)" }
}

struct ThemeToggleButton: View {
    @AppStorage private var raw: String
    private let values: [ThemeChoice: String]
    private let fades: Bool
    private let apply: @MainActor (ThemeChoice) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - storageKey : la clé déjà utilisée par le sélecteur des Réglages de l'app.
    /// - system/light/dark : les valeurs enregistrées sous cette clé.
    /// - fades : fondu des fenêtres par ce bouton (false si `apply` fait déjà son propre fondu).
    /// - apply : applique le thème (par défaut NSApp.appearance). La valeur est déjà enregistrée.
    init(storageKey: String, system: String = "system", light: String = "light", dark: String = "dark",
         fades: Bool = true, apply: @escaping @MainActor (ThemeChoice) -> Void = { NSApp.appearance = $0.nsAppearance }) {
        _raw = AppStorage(wrappedValue: system, storageKey)
        values = [.system: system, .light: light, .dark: dark]
        self.fades = fades
        self.apply = apply
    }

    private var choice: ThemeChoice { values.first { $0.value == raw }?.key ?? .system }

    var body: some View {
        Menu {
            Picker(ThemeText.menu, selection: Binding(get: { choice }, set: { select($0) })) {
                ForEach(ThemeChoice.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Button(ThemeText.toggle, action: toggle)
        } label: {
            Label(ThemeText.menu, systemImage: choice.symbol)
                .contentTransition(.symbolEffect(.replace))
        } primaryAction: {
            toggle()
        }
        .menuIndicator(.visible)
        .help(ThemeText.help)
        .accessibilityLabel("\(ThemeText.menu) : \(choice.label)")
        .accessibilityHint(ThemeText.toggle)
        .background {
            // Raccourci ⇧⌘L (bouton invisible, hors VoiceOver)
            Button(ThemeText.toggle, action: toggle)
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private func toggle() {
        select(Self.isDark(choice) ? .light : .dark)
    }

    private func select(_ new: ThemeChoice) {
        guard let value = values[new] else { return }
        if fades && !reduceMotion { Self.fadeWindows() }
        withAnimation(.snappy) { raw = value }
        apply(new)
    }

    /// Apparence réellement affichée (Automatique : celle du Mac).
    @MainActor static func isDark(_ choice: ThemeChoice) -> Bool {
        switch choice {
        case .light: false
        case .dark: true
        case .system: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    /// Fondu enchaîné doux sur chaque fenêtre visible.
    @MainActor static func fadeWindows(duration: CFTimeInterval = 0.35) {
        for window in NSApp.windows where window.isVisible {
            guard let layer = window.contentView?.superview?.layer ?? window.contentView?.layer else { continue }
            let fade = CATransition()
            fade.type = .fade
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "titelive.theme")
        }
    }

    /// Pour les apps sans thème propre : applique au lancement le choix mémorisé sous `storageKey`.
    @MainActor static func applyStored(storageKey: String, light: String = "light", dark: String = "dark") {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        NSApp.appearance = stored == light ? ThemeChoice.light.nsAppearance
            : stored == dark ? ThemeChoice.dark.nsAppearance : nil
    }
}
