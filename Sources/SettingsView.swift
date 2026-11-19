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
        case .system: return L("Automatique", "Automatic")
        case .light: return L("Clair", "Light")
        case .dark: return L("Sombre", "Dark")
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

    var body: some View {
        TabView {
            Tab(L("Général", "General"), systemImage: "gearshape") {
                GeneralSettings(model: model)
                    .frame(width: 560, height: 460)
            }
            Tab(L("Cartouche", "Cartridge"), systemImage: "sdcard") {
                CartridgeSettings(model: model)
                    .frame(width: 560, height: 380)
            }
            Tab(L("Mises à jour", "Updates"), systemImage: "arrow.triangle.2.circlepath") {
                UpdateSettings(updater: updater)
                    .frame(width: 560, height: 380)
            }
            Tab(L("Crédits", "Credits"), systemImage: "heart") {
                // Hauteur naturelle : la fenêtre s'adapte, rien ne passe sous la barre d'onglets.
                AboutView(updater: updater)
                    .frame(width: 560)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
    @State private var language = AppLanguage.stored

    var body: some View {
        Form {
            Section(L("Langue", "Language")) {
                Picker(L("Langue de l'app", "App language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .onChange(of: language) { _, newValue in newValue.save() }
                if language != AppLanguage.launchChoice {
                    HStack {
                        Text(L("Redémarrez Summer Drop pour appliquer la langue.", "Restart Summer Drop to apply the language."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Redémarrer", "Restart")) { AppLanguage.relaunch() }
                    }
                }
            }

            Section(L("Apparence", "Appearance")) {
                Picker(L("Thème", "Theme"), selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(L("« Automatique » suit le réglage de macOS.", "“Automatic” follows the macOS setting."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle(L("Me prévenir à la fin des transferts, au branchement de la cartouche et quand une mise à jour est prête", "Notify me when transfers finish, when the cartridge is plugged in and when an update is ready"), isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled { Notifier.shared.requestAuthorization() }
                    }
            }

            Section(L("Fiches de jeu", "Game cards")) {
                Toggle(L("Afficher la fiche d'un jeu au survol de son nom", "Show a game's card when hovering its name"), isOn: $cardsEnabled)
                HStack {
                    Text(L("Jaquettes, captures et résumés sont gardés en cache sur le Mac.", "Box art, screenshots and summaries are cached on the Mac."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Vider le cache", "Clear Cache")) {
                        Task { await GameInfoStore.shared.clearCache() }
                        URLCache.shared.removeAllCachedResponses()
                    }
                }
            }

            Section(L("Aide", "Help")) {
                HStack {
                    Text(L("Présentation de l'app et localisation de sc64deployer.", "App walkthrough and sc64deployer setup."))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Revoir le tutoriel", "Show the Tutorial Again")) { model.showOnboarding = true }
                }
            }

            Section(L("Statistiques", "Statistics")) {
                HStack {
                    Text(L("\(model.stats.uploads) envoi(s), \(model.stats.downloads) récupération(s)", "\(model.stats.uploads) upload(s), \(model.stats.downloads) retrieval(s)"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Remettre à zéro", "Reset")) { model.resetStats() }
                }
            }

            Section(L("Téléchargements", "Downloads")) {
                LabeledContent(L("Dossier proposé", "Suggested folder")) {
                    Text(folderLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(L("Par défaut", "Default")) { downloadFolder = "" }
                        .disabled(downloadFolder.isEmpty)
                    Button(L("Choisir…", "Choose…")) { showFolderPicker = true }
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
        return model.suggestedDownloadFolder?.path ?? L("Téléchargements", "Downloads")
    }
}

// MARK: - Cartouche

struct CartridgeSettings: View {
    let model: AppModel
    @State private var showToolPicker = false

    var body: some View {
        Form {
            Section(L("Outil sc64deployer", "sc64deployer tool")) {
                LabeledContent(L("Emplacement", "Location")) {
                    Text(model.deployerURL?.path ?? "Introuvable")
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundStyle(model.deployerURL == nil ? Color.red : Color.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button(L("Recherche automatique", "Search Automatically")) { model.resetDeployer() }
                    Button(L("Choisir…", "Choose…")) { showToolPicker = true }
                        .fileImporter(isPresented: $showToolPicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                            if case .success(let urls) = result, let url = urls.first {
                                model.useDeployer(at: url)
                            }
                        }
                }
            }

            Section(L("État", "Status")) {
                LabeledContent(L("Cartouche", "Cartridge")) {
                    Text(connectionText)
                        .foregroundStyle(.secondary)
                }
                Text(L("Éteignez la console avant d'accéder à la carte SD.", "Turn the console off before accessing the SD card."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var connectionText: String {
        switch model.connection {
        case .searching: return "Recherche…"
        case .connected(let device): return L("Connectée (\(device.serial))", "Connected (\(device.serial))")
        case .disconnected: return L("Non connectée", "Not connected")
        case .missingTool: return L("sc64deployer introuvable", "sc64deployer not found")
        }
    }
}

// MARK: - Mises à jour

struct UpdateSettings: View {
    let updater: Updater
    @AppStorage(Updater.autoCheckKey) private var autoCheck = true

    var body: some View {
        Form {
            Section(L("Mises à jour", "Updates")) {
                Toggle(L("Rechercher automatiquement les mises à jour", "Automatically check for updates"), isOn: $autoCheck)
                Text(L("Vérification au lancement puis toutes les 6 heures. La mise à jour s'installe au redémarrage de l'app.", "Checked at launch, then every 6 hours. The update installs when the app restarts."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(L("Version installée", "Installed version"), value: updater.currentVersion)
                LabeledContent(L("État", "Status")) {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    if case .ready = updater.phase {
                        Button(L("Redémarrer et installer", "Restart and Install")) { updater.installAndRelaunch() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button(L("Rechercher maintenant", "Check Now")) {
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
        case .checking: return L("Recherche en cours…", "Checking…")
        case .downloading(let version): return L("Téléchargement de la version \(version)…", "Downloading version \(version)…")
        case .ready(let version): return L("Version \(version) prête", "Version \(version) ready")
        case .upToDate: return L("À jour", "Up to date")
        case .failed(let message): return message
        }
    }
}
