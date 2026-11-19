import AppKit
import SwiftUI

/// Fenêtre « À propos » avec les crédits (aussi utilisée dans l'onglet Crédits des réglages).
struct AboutView: View {
    let updater: Updater
    @AppStorage(AppLanguage.storageKey) private var languageSetting = AppLanguage.systemValue

    private var credits: [(role: String, name: String)] { [
        (L("Idea and design"), "Titelive"),
        (L("Development"), L("Titelive, with Claude (Anthropic)")),
        (L("SummerCart64 and sc64deployer"), "Mateusz Faderewski (Polprzewodnikowy)"),
        ("Console", L("Analogue 3D, by Analogue")),
    ] }

    var body: some View {
        content.id(languageSetting)
    }

    private var content: some View {
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
                Text(L("Send and retrieve your N64 ROMs on the SummerCart64."))
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
                Link(L("Summer Drop on GitHub"), destination: URL(string: "https://github.com/Titelive/summer-drop")!)
                Text("·").foregroundStyle(.secondary)
                Link(L("SummerCart64 project"), destination: URL(string: "https://github.com/Polprzewodnikowy/SummerCart64")!)
            }
            .font(.callout)

            Button(L("Check for Updates")) {
                Task { await updater.checkForUpdates(userInitiated: true) }
            }
            .buttonStyle(.glass)

            Text(L("Summer Drop is not affiliated with Nintendo or Analogue."))
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
    /// Passed in so the menu is rebuilt when the language changes.
    let language: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L("About Summer Drop")) {
            openWindow(id: "about")
        }
        Button(L("Check for Updates…")) {
            Task { await Updater.shared.checkForUpdates(userInitiated: true) }
        }
    }
}
