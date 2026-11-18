import AppKit
import SwiftUI

/// Fenêtre « À propos » avec les crédits (aussi utilisée dans l'onglet Crédits des réglages).
struct AboutView: View {
    let updater: Updater

    private let credits: [(role: String, name: String)] = [
        ("Idée et conception", "Titelive"),
        ("Développement", "Titelive, avec Claude (Anthropic)"),
        ("SummerCart64 et sc64deployer", "Mateusz Faderewski (Polprzewodnikowy)"),
        ("Console", "Analogue 3D, par Analogue"),
    ]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Summer Drop")
                    .font(.title2.weight(.bold))
                Text("Version \(updater.currentVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Envoyez et récupérez vos ROM N64 sur la SummerCart64.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CreatorBar()

            Divider()
                .frame(maxWidth: 360)

            Grid(horizontalSpacing: 28, verticalSpacing: 14) {
                GridRow {
                    credit(credits[0])
                    credit(credits[1])
                }
                GridRow {
                    credit(credits[2])
                    credit(credits[3])
                }
            }

            Divider()
                .frame(maxWidth: 360)

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
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    private func credit(_ item: (role: String, name: String)) -> some View {
        VStack(spacing: 2) {
            Text(item.role)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(item.name)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 220)
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
