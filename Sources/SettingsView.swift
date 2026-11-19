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
        case .system: return "Automatique"
        case .light: return "Clair"
        case .dark: return "Sombre"
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
            Tab("Général", systemImage: "gearshape") {
                GeneralSettings(model: model)
                    .frame(width: 560, height: 380)
            }
            Tab("Cartouche", systemImage: "sdcard") {
                CartridgeSettings(model: model)
                    .frame(width: 560, height: 380)
            }
            Tab("Mises à jour", systemImage: "arrow.triangle.2.circlepath") {
                UpdateSettings(updater: updater)
                    .frame(width: 560, height: 380)
            }
            Tab("Crédits", systemImage: "heart") {
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

    var body: some View {
        Form {
            Section("Apparence") {
                Picker("Thème", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("« Automatique » suit le réglage de macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Me prévenir à la fin des transferts, au branchement de la cartouche et quand une mise à jour est prête", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled { Notifier.shared.requestAuthorization() }
                    }
            }

            Section("Fiches de jeu") {
                Toggle("Afficher la fiche d'un jeu au survol de son nom", isOn: $cardsEnabled)
                HStack {
                    Text("Jaquettes, captures et résumés sont gardés en cache sur le Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Vider le cache") {
                        Task { await GameInfoStore.shared.clearCache() }
                        URLCache.shared.removeAllCachedResponses()
                    }
                }
            }

            Section("Aide") {
                HStack {
                    Text("Présentation de l'app et localisation de sc64deployer.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Revoir le tutoriel") { model.showOnboarding = true }
                }
            }

            Section("Statistiques") {
                HStack {
                    Text("\(model.stats.uploads) envoi(s), \(model.stats.downloads) récupération(s)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remettre à zéro") { model.resetStats() }
                }
            }

            Section("Téléchargements") {
                LabeledContent("Dossier proposé") {
                    Text(folderLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Par défaut") { downloadFolder = "" }
                        .disabled(downloadFolder.isEmpty)
                    Button("Choisir…") { showFolderPicker = true }
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
        return model.suggestedDownloadFolder?.path ?? "Téléchargements"
    }
}

// MARK: - Cartouche

struct CartridgeSettings: View {
    let model: AppModel
    @State private var showToolPicker = false

    var body: some View {
        Form {
            Section("Outil sc64deployer") {
                LabeledContent("Emplacement") {
                    Text(model.deployerURL?.path ?? "Introuvable")
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundStyle(model.deployerURL == nil ? Color.red : Color.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("Recherche automatique") { model.resetDeployer() }
                    Button("Choisir…") { showToolPicker = true }
                        .fileImporter(isPresented: $showToolPicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                            if case .success(let urls) = result, let url = urls.first {
                                model.useDeployer(at: url)
                            }
                        }
                }
            }

            Section("État") {
                LabeledContent("Cartouche") {
                    Text(connectionText)
                        .foregroundStyle(.secondary)
                }
                Text("Éteignez la console avant d'accéder à la carte SD.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var connectionText: String {
        switch model.connection {
        case .searching: return "Recherche…"
        case .connected(let device): return "Connectée (\(device.serial))"
        case .disconnected: return "Non connectée"
        case .missingTool: return "sc64deployer introuvable"
        }
    }
}

// MARK: - Mises à jour

struct UpdateSettings: View {
    let updater: Updater
    @AppStorage(Updater.autoCheckKey) private var autoCheck = true

    var body: some View {
        Form {
            Section("Mises à jour") {
                Toggle("Rechercher automatiquement les mises à jour", isOn: $autoCheck)
                Text("Vérification au lancement puis toutes les 6 heures. La mise à jour s'installe au redémarrage de l'app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Version installée", value: updater.currentVersion)
                LabeledContent("État") {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    if case .ready = updater.phase {
                        Button("Redémarrer et installer") { updater.installAndRelaunch() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Rechercher maintenant") {
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
        case .checking: return "Recherche en cours…"
        case .downloading(let version): return "Téléchargement de la version \(version)…"
        case .ready(let version): return "Version \(version) prête"
        case .upToDate: return "À jour"
        case .failed(let message): return message
        }
    }
}
