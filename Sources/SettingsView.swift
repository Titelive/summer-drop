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

    static var current: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    let model: AppModel
    let updater: Updater
    @AppStorage(AppLanguage.storageKey) private var languageSetting = AppLanguage.systemValue

    var body: some View {
        TabView {
            Tab(L("General"), systemImage: "gearshape") {
                GeneralSettings(model: model)
                    .frame(width: 560, height: 460)
            }
            Tab(L("Cartridge"), systemImage: "sdcard") {
                CartridgeSettings(model: model)
                    .frame(width: 560, height: 380)
            }
            Tab(L("Updates"), systemImage: "arrow.triangle.2.circlepath") {
                UpdateSettings(updater: updater)
                    .frame(width: 560, height: 380)
            }
            Tab(L("Credits"), systemImage: "heart") {
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
    @AppStorage(Notifier.enabledKey) private var notificationsEnabled = true

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
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(L("“Automatic” follows the macOS setting."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle(L("Notify me when transfers finish, when the cartridge is plugged in and when an update is ready"), isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled { Notifier.shared.requestAuthorization() }
                    }
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
