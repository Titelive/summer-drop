import AppKit
import SwiftUI

/// Tutoriel affiché au premier lancement (et rejouable depuis Aide ou les Réglages).
struct OnboardingView: View {
    let model: AppModel
    @State private var step = 0
    @State private var showToolPicker = false

    static let doneKey = "onboardingDone"

    private struct Page {
        let systemImage: String
        let color: Color
        let title: String
        let text: String
    }

    private let pages: [Page] = [
        Page(systemImage: "sun.max.fill", color: .yellow,
             title: L("Bienvenue dans Summer Drop", "Welcome to Summer Drop"),
             text: L("Summer Drop **envoie** vos **ROM Nintendo 64** sur la carte SD de votre **SummerCart64**, et les **récupère**, directement depuis le Mac, par **USB-C**. Plus besoin de retirer la carte **microSD** ni d'ouvrir le **Terminal**.", "Summer Drop **sends** your **Nintendo 64 ROMs** to the SD card of your **SummerCart64**, and **retrieves** them, straight from the Mac over **USB-C**. No more pulling out the **microSD card** or opening **Terminal**.")),
        Page(systemImage: "cable.connector", color: .green,
             title: L("Branchez la cartouche", "Plug in the cartridge"),
             text: L("Reliez la **SummerCart64** au Mac avec un câble **USB-C**, **console éteinte**. La pastille en haut à droite passe au **vert** dès que la cartouche est détectée.", "Connect the **SummerCart64** to the Mac with a **USB-C** cable, **console off**. The pill at the top right turns **green** as soon as the cartridge is detected.")),
        Page(systemImage: "rectangle.split.2x1", color: .orange,
             title: L("Le Mac à gauche, la carte à droite", "Mac on the left, card on the right"),
             text: L("À **gauche**, un dossier de votre **Mac** (par défaut **Jeux › Nintendo 64**). À **droite**, la **carte SD** de la cartouche. Pour **envoyer**, **glissez** des ROM de gauche à droite, ou depuis le **Finder**, ou cochez-les puis **« Envoyer »**. Les dossiers entiers sont acceptés.", "On the **left**, a folder on your **Mac** (by default **Jeux › Nintendo 64**). On the **right**, the cartridge's **SD card**. To **send**, **drag** ROMs from left to right, or from the **Finder**, or check them and click **“Send”**. Whole folders work too.")),
        Page(systemImage: "arrow.down.to.line", color: .blue,
             title: L("Récupérez-les sur le Mac", "Retrieve them to the Mac"),
             text: L("**Glissez** des ROM de la **carte** vers le panneau **Mac**, ou cochez-les puis **« Récupérer »**. Raccourcis : **⌘A** tout sélectionner, **⌘C** copier (**⌘X** déplacer), puis cliquez sur l'autre panneau et **⌘V** coller. Aucun fichier du Mac n'est **jamais écrasé**.", "**Drag** ROMs from the **card** to the **Mac** pane, or check them and click **“Retrieve”**. Shortcuts: **⌘A** select all, **⌘C** copy (**⌘X** move), then click the other pane and **⌘V** paste. No file on the Mac is **ever overwritten**.")),
        Page(systemImage: "wrench.and.screwdriver.fill", color: .purple,
             title: L("L'outil sc64deployer", "The sc64deployer tool"),
             text: L("Summer Drop s'appuie sur **sc64deployer**, l'**outil officiel** de la SummerCart64. Il est normalement **inclus dans l'app**. Vérifiez ci-dessous qu'il est bien **trouvé**.", "Summer Drop relies on **sc64deployer**, the SummerCart64's **official tool**. It normally **comes with the app**. Check below that it is **found**.")),
        Page(systemImage: "sparkles", color: .pink,
             title: L("C'est parti !", "Let's go!"),
             text: L("**Réglages** avec **⌘,** (thème clair ou sombre, dossier de téléchargement…), **recherche** avec **⌘K**, **fiches de jeu** au survol d'un nom, **statistiques** avec le bouton graphique, et **mises à jour automatiques**. Pensez à **éteindre la console** avant chaque transfert.", "**Settings** with **⌘,** (language, light or dark theme, download folder…), **search** with **⌘K**, **game cards** when hovering a name, **sort and group** from the list menu, **statistics** with the chart button, and **automatic updates**. Remember to **turn the console off** before each transfer.")),
    ]

    private var isLast: Bool { step == pages.count - 1 }
    private var isToolStep: Bool { step == 4 }

    var body: some View {
        let page = pages[step]

        VStack(spacing: 0) {
            HStack {
                Spacer()
                if !isLast {
                    Button(L("Passer", "Skip")) { finish() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 20)

            VStack(spacing: 16) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 54, weight: .regular))
                    .foregroundStyle(page.color)
                    .frame(width: 110, height: 110)
                    .glassEffect(Glass.regular.tint(page.color.opacity(0.2)), in: .circle)
                    .id(step)
                    .transition(.scale.combined(with: .opacity))

                Text(page.title)
                    .font(.title.weight(.bold))
                Text(LocalizedStringKey(page.text))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)

                if isToolStep {
                    toolStatus
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: index == step ? 18 : 7, height: 7)
                        .contentShape(Rectangle().inset(by: -4))
                        .onTapGesture { go(index - step) }
                }
            }
            .padding(.bottom, 18)

            HStack {
                Button {
                    go(-1)
                } label: {
                    Label(L("Précédent", "Back"), systemImage: "chevron.left")
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(step == 0 ? 0 : 1)
                .disabled(step == 0)
                Spacer()
                Button {
                    if isLast { finish() } else { go(1) }
                } label: {
                    HStack(spacing: 8) {
                        Text(isLast ? L("Commencer", "Get Started") : L("Suivant", "Next"))
                        Text(isLast ? "⌘↩" : "↩")
                            .font(.caption.monospaced())
                            .opacity(0.7)
                    }
                }
                .buttonStyle(.glassProminent)
                // Dernière page : ⌘ Entrée (ou clic) ; avant : Entrée.
                .keyboardShortcut(isLast ? KeyboardShortcut(.return, modifiers: .command) : .defaultAction)
            }
            .background(
                // Flèche droite : page suivante (en plus de Entrée).
                Button("") { if !isLast { go(1) } }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .opacity(0)
                    .allowsHitTesting(false)
            )
            Text(L("Astuce : utilisez les flèches ← → du clavier", "Tip: use the ← → arrow keys"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
        .padding(28)
        .frame(width: 580, height: 540)
        .fileImporter(isPresented: $showToolPicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.useDeployer(at: url)
            }
        }
    }

    private var toolStatus: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.deployerURL == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(model.deployerURL == nil ? Color.red : Color.green)
                Text(model.deployerURL == nil ? L("sc64deployer introuvable", "sc64deployer not found") : L("sc64deployer trouvé", "sc64deployer found"))
                    .fontWeight(.semibold)
            }
            if let url = model.deployerURL {
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: 440)
            }
            HStack(spacing: 10) {
                Button(L("Recherche automatique", "Search Automatically")) { model.resetDeployer() }
                    .buttonStyle(.glass)
                Button(L("Localiser sc64deployer…", "Locate sc64deployer…")) { showToolPicker = true }
                    .buttonStyle(.glass)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func go(_ delta: Int) {
        withAnimation(.spring(duration: 0.35)) {
            step = min(max(step + delta, 0), pages.count - 1)
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        model.showOnboarding = false
    }
}
