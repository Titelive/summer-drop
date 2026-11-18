import AppKit
import SwiftUI

/// Fenêtre « À propos » avec les crédits.
struct AboutView: View {
    let updater: Updater

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 2) {
                Text("Summer Drop")
                    .font(.title.weight(.bold))
                Text("Version \(updater.currentVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Envoyez et récupérez vos ROM N64 sur la SummerCart64, par USB-C.")
                .font(.callout)
                .multilineTextAlignment(.center)

            Divider()

            CreatorBar()

            VStack(alignment: .leading, spacing: 10) {
                credit("Idée et conception", "Titelive")
                credit("Développement", "Titelive, avec Claude (Anthropic)")
                credit("SummerCart64 et sc64deployer", "Mateusz Faderewski (Polprzewodnikowy)")
                credit("Console", "Analogue 3D, par Analogue")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Link("Summer Drop sur GitHub", destination: URL(string: "https://github.com/Titelive/summer-drop")!)
                Text("·").foregroundStyle(.secondary)
                Link("Projet SummerCart64", destination: URL(string: "https://github.com/Polprzewodnikowy/SummerCart64")!)
            }
            .font(.callout)

            Button("Rechercher des mises à jour") {
                Task { await updater.checkForUpdates(userInitiated: true) }
            }
            .buttonStyle(.glass)

            Text("Summer Drop n'est affilié ni à Nintendo, ni à Analogue.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 420)
    }

    private func credit(_ role: String, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(role)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.callout.weight(.medium))
        }
    }
}

/// Commandes du menu de l'app : « À propos » et « Rechercher des mises à jour… ».
struct AppMenuCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("À propos de Summer Drop") {
            openWindow(id: "about")
        }
        Button("Rechercher des mises à jour…") {
            Task { await Updater.shared.checkForUpdates(userInitiated: true) }
        }
    }
}
