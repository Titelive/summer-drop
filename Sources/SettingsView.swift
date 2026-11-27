import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Apparence choisie dans les réglages.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("Automatic")
        case .light: return L("Light")
        case .dark: return L("Dark")
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    static var current: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// `nil` in Automatic mode: AppKit then follows the Mac live, with no restart.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }
}

/// Cross-fades every window when the app's look changes, whether the user picked a theme
/// or macOS switched between light and dark on its own (Automatic mode).
@MainActor
final class AppearanceTransition {
    static let shared = AppearanceTransition()

    private var observation: NSKeyValueObservation?
    private var lastName: NSAppearance.Name?

    func start() {
        lastName = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        // Fired before the windows redraw, so the fade starts from what is on screen.
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { app, _ in
            MainActor.assumeIsolated {
                let name = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                guard name != AppearanceTransition.shared.lastName else { return }
                AppearanceTransition.shared.lastName = name
                AppearanceTransition.shared.fadeWindows()
            }
        }
    }

    private func fadeWindows() {
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.15 : 0.35
        for window in NSApp.windows where window.isVisible {
            guard let layer = window.contentView?.superview?.layer ?? window.contentView?.layer else { continue }
            let fade = CATransition()
            fade.type = .fade
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "appearanceFade")
        }
    }
}

struct SettingsView: View {
    let model: AppModel
    let updater: Updater
    @Bindable private var router = AppRouter.shared
    @AppStorage(AppLanguage.storageKey) private var languageSetting = AppLanguage.systemValue

    var body: some View {
        TabView(selection: $router.settingsTab) {
            Tab(L("General"), systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettings(model: model)
                    .frame(width: 560, height: 460)
            }
            Tab(L("Notifications"), systemImage: "bell.badge", value: SettingsTab.notifications) {
                NotificationSettings()
                    .frame(width: 560, height: 400)
            }
            Tab(L("Cartridge"), systemImage: "sdcard", value: SettingsTab.cartridge) {
                CartridgeSettings(model: model)
                    .frame(width: 560, height: 380)
            }
            Tab(L("Updates"), systemImage: "arrow.triangle.2.circlepath", value: SettingsTab.updates) {
                UpdateSettings(updater: updater)
                    .frame(width: 560, height: 380)
            }
            Tab(L("Credits"), systemImage: "heart", value: SettingsTab.credits) {
                // Hauteur naturelle : la fenêtre s'adapte, rien ne passe sous la barre d'onglets.
                AboutView(updater: updater)
                    .frame(width: 560)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Rebuilt when the language changes, so every label is translated at once.
        .id(languageSetting)
    }
}

// MARK: - Général

struct GeneralSettings: View {
    let model: AppModel
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system
    @AppStorage("lastDownloadFolder") private var downloadFolder = ""
    @State private var showFolderPicker = false
    @AppStorage("gameCardsEnabled") private var cardsEnabled = true

    var body: some View {
        Form {
            Section(L("Language")) {
                LanguagePicker()
                Text(L("The standard menus (Edit, Window…) switch at the next launch."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Appearance")) {
                Picker(L("Theme"), selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(L("“Automatic” follows the macOS setting and switches with it, even while the app is open."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Game cards")) {
                Toggle(L("Show a game's card when hovering its name"), isOn: $cardsEnabled)
                HStack {
                    Text(L("Box art, screenshots and summaries are cached on the Mac."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Clear Cache")) {
                        Task { await GameInfoStore.shared.clearCache() }
                        GameEmojiStore.shared.clear()
                        URLCache.shared.removeAllCachedResponses()
                    }
                }
            }

            Section(L("Help")) {
                HStack {
                    Text(L("App walkthrough and sc64deployer setup."))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Show the Tutorial Again")) { model.showOnboarding = true }
                }
            }

            Section(L("Statistics")) {
                HStack {
                    Text(L("{0} upload(s), {1} retrieval(s)", "\(model.stats.uploads)", "\(model.stats.downloads)"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Reset")) { model.resetStats() }
                }
            }

            Section(L("Downloads")) {
                LabeledContent(L("Suggested folder")) {
                    Text(folderLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(L("Default")) { downloadFolder = "" }
                        .disabled(downloadFolder.isEmpty)
                    Button(L("Choose…")) { showFolderPicker = true }
                        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                            if case .success(let urls) = result, let folder = urls.first {
                                downloadFolder = folder.path
                            }
                        }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { _, newValue in
            newValue.apply()
        }
        .onChange(of: downloadFolder) { _, _ in
            model.downloadFolderVersion += 1
        }
    }

    private var folderLabel: String {
        if !downloadFolder.isEmpty { return downloadFolder }
        return model.suggestedDownloadFolder?.path ?? L("Downloads")
    }
}

// MARK: - Notifications

struct NotificationSettings: View {
    private let notifier = Notifier.shared

    var body: some View {
        Form {
            Section {
                ForEach(NotificationKind.allCases) { kind in
                    NotificationKindToggle(kind: kind)
                }
            } header: {
                Text(L("Notify me when…"))
            } footer: {
                Text(L("Notifications follow Focus: transfers use standard banners, the others arrive silently in Notification Center."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Permission")) {
                switch notifier.authorization {
                case .notDetermined:
                    HStack {
                        Text(L("Summer Drop will ask for permission the first time you send or retrieve a file."))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Allow Now")) { notifier.requestAuthorizationIfNeeded() }
                    }
                case .denied:
                    HStack {
                        Label(L("Notifications are turned off for Summer Drop in System Settings."), systemImage: "bell.slash")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Open System Settings")) { notifier.openSystemSettings() }
                    }
                default:
                    HStack {
                        Label(L("Allowed. Banner style and sounds are set in System Settings."), systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Open System Settings")) { notifier.openSystemSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await notifier.refreshAuthorization() }
    }
}

private struct NotificationKindToggle: View {
    let kind: NotificationKind
    @State private var isOn: Bool

    init(kind: NotificationKind) {
        self.kind = kind
        _isOn = State(initialValue: kind.isEnabled)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label)
                    Text(kind.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: kind.systemImage)
            }
        }
        .onChange(of: isOn) { _, enabled in
            UserDefaults.standard.set(enabled, forKey: kind.defaultsKey)
            if enabled { Notifier.shared.requestAuthorizationIfNeeded() }
        }
    }
}

// MARK: - Cartouche

struct CartridgeSettings: View {
    let model: AppModel
    @State private var showToolPicker = false

    var body: some View {
        Form {
            Section(L("sc64deployer tool")) {
                LabeledContent(L("Location")) {
                    Text(model.deployerURL?.path ?? "Introuvable")
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundStyle(model.deployerURL == nil ? Color.red : Color.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button(L("Search Automatically")) { model.resetDeployer() }
                    Button(L("Choose…")) { showToolPicker = true }
                        .fileImporter(isPresented: $showToolPicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                            if case .success(let urls) = result, let url = urls.first {
                                model.useDeployer(at: url)
                            }
                        }
                }
            }

            Section(L("Status")) {
                LabeledContent(L("Cartridge")) {
                    Text(connectionText)
                        .foregroundStyle(.secondary)
                }
                Text(L("Turn the console off before accessing the SD card."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var connectionText: String {
        switch model.connection {
        case .searching: return "Recherche…"
        case .connected(let device): return L("Connected ({0})", "\(device.serial)")
        case .disconnected: return L("Not connected")
        case .missingTool: return L("sc64deployer not found")
        }
    }
}

// MARK: - Mises à jour

struct UpdateSettings: View {
    let updater: Updater
    @AppStorage(Updater.autoCheckKey) private var autoCheck = true

    var body: some View {
        Form {
            Section(L("Updates")) {
                Toggle(L("Automatically check for updates"), isOn: $autoCheck)
                Text(L("Checked at launch, then every 6 hours. The update installs when the app restarts."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(L("Installed version"), value: updater.currentVersion)
                LabeledContent(L("Status")) {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    if case .ready = updater.phase {
                        Button(L("Restart and Install")) { updater.installAndRelaunch() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button(L("Check Now")) {
                        Task { await updater.checkForUpdates(userInitiated: true) }
                    }
                    .disabled(updater.phase == .checking)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch updater.phase {
        case .idle: return "—"
        case .checking: return L("Checking…")
        case .downloading(let version): return L("Downloading version {0}…", "\(version)")
        case .ready(let version): return L("Version {0} ready", "\(version)")
        case .upToDate: return L("Up to date")
        case .failed(let message): return message
        }
    }
}
