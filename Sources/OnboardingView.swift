import AppKit
import SwiftUI

/// Tutoriel affiché au premier lancement (et rejouable depuis Aide ou les Réglages).
struct OnboardingView: View {
    let model: AppModel
    @State private var step = 0
    @State private var showToolPicker = false
    @AppStorage(AppLanguage.storageKey) private var languageSetting = AppLanguage.systemValue

    static let doneKey = "onboardingDone"

    private struct Page {
        let systemImage: String
        let color: Color
        let title: String
        let text: String
    }

    private var pages: [Page] { [
        Page(systemImage: "sun.max.fill", color: .yellow,
             title: L("Welcome to Summer Drop"),
             text: L("Summer Drop **sends** your **Nintendo 64 ROMs** to the SD card of your **SummerCart64**, and **retrieves** them, straight from the Mac over **USB-C**. No more pulling out the **microSD card** or opening **Terminal**.")),
        Page(systemImage: "cable.connector", color: .green,
             title: L("Plug in the cartridge"),
             text: L("Connect the **SummerCart64** to the Mac with a **USB-C** cable, **console off**. The pill at the top right turns **green** as soon as the cartridge is detected.")),
        Page(systemImage: "rectangle.split.2x1", color: .orange,
             title: L("Mac on the left, card on the right"),
             text: L("On the **left**, a folder on your **Mac** (by default **Jeux › Nintendo 64**). On the **right**, the cartridge's **SD card**. To **send**, **drag** ROMs from left to right, or from the **Finder**, or check them and click **“Send”**. Whole folders work too.")),
        Page(systemImage: "arrow.down.to.line", color: .blue,
             title: L("Retrieve them to the Mac"),
             text: L("**Drag** ROMs from the **card** to the **Mac** pane, or check them and click **“Retrieve”**. Shortcuts: **⌘A** select all, **⌘C** copy (**⌘X** move), then click the other pane and **⌘V** paste. No file on the Mac is **ever overwritten**.")),
        Page(systemImage: "wrench.and.screwdriver.fill", color: .purple,
             title: L("The sc64deployer tool"),
             text: L("Summer Drop relies on **sc64deployer**, the SummerCart64's **official tool**. It normally **comes with the app**. Check below that it is **found**.")),
        Page(systemImage: "sparkles", color: .pink,
             title: L("Let's go!"),
             text: L("**Settings** with **⌘,** (language, light or dark theme, download folder…), **search** with **⌘K**, **game cards** when hovering a name, **sort and group** with the **↑↓** button, **statistics** with the chart button, and **automatic updates**. Remember to **turn the console off** before each transfer.")),
    ] }

    private var isLast: Bool { step == pages.count - 1 }
    private var isToolStep: Bool { step == 4 }

    var body: some View {
        let page = pages[step]

        VStack(spacing: 0) {
            HStack {
                Spacer()
                if !isLast {
                    Button(L("Skip")) { finish() }
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

                if step == 0 {
                    LanguageChoiceGrid()
                        .padding(.top, 4)
                }
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
                    Label(L("Back"), systemImage: "chevron.left")
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
                        Text(isLast ? L("Get Started") : L("Next"))
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
            Text(L("Tip: use the ← → arrow keys"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
        .padding(28)
        .frame(width: 600, height: 600)
        // Every text follows the language picked on the first page, right away.
        .id(languageSetting)
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
                Text(model.deployerURL == nil ? L("sc64deployer not found") : L("sc64deployer found"))
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
                Button(L("Search Automatically")) { model.resetDeployer() }
                    .buttonStyle(.glass)
                Button(L("Locate sc64deployer…")) { showToolPicker = true }
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
