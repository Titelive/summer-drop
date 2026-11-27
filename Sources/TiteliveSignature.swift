import SwiftUI
import AppKit

// MARK: - Signature Titelive (coin bas gauche de la fenêtre principale)
//
// Une ligne avec l'icône et le nom de l'app, puis la pastille « Créé par Titelive »
// (lien vers titelive.me) et le bouton jaune « Offrir un café » (Buy Me a Coffee).
// Le bouton café n'apparaît jamais dans l'édition Setapp : passer showsCoffee: false.

enum SignatureLinks {
    static let site = URL(string: "https://titelive.me")!
    static let coffee = URL(string: "https://buymeacoffee.com/titelive")!
}

struct TiteliveSignature: View {
    let appName: String
    /// false dans l'édition Setapp : aucun lien de don ou d'achat.
    let showsCoffee: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text(appName)
                    .font(.caption.weight(.medium))
                    // .secondary est trop pâle sur le verre : primaire atténué (> 4,5:1 en clair et en sombre)
                    .foregroundStyle(.primary.opacity(0.78))
                    .lineLimit(1)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { pills }
                VStack(alignment: .leading, spacing: 6) { pills }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var pills: some View {
        SignatureCreditPill()
        if showsCoffee { SignatureCoffeeButton() }
    }
}

/// Pied FIXE sous une liste (à poser avec .safeAreaInset(edge: .bottom) sur la List) :
/// petit séparateur au-dessus et fond opaque, la liste défile au-dessus et s'arrête avant le pied,
/// rien n'est jamais recouvert. Marge gauche alignée sur les rubriques de la barre latérale.
struct TiteliveSignatureFooter: View {
    let appName: String
    let showsCoffee: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.horizontal, 10)
            TiteliveSignature(appName: appName, showsCoffee: showsCoffee)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .signatureFooterBackground()
    }
}

extension View {
    /// Fond opaque du pied de signature (couleur système de la fenêtre, claire ou sombre).
    func signatureFooterBackground() -> some View {
        background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Pastille « Créé par [avatar] Titelive », lien vers titelive.me.
struct SignatureCreditPill: View {
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        Button { openURL(SignatureLinks.site) } label: {
            HStack(spacing: 5) {
                Text(L("Made by")).foregroundStyle(.primary.opacity(0.78))
                SignatureAvatar(size: 16)
                Text("Titelive").fontWeight(.semibold).foregroundStyle(.primary)
            }
            .font(.caption)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(height: 24)
            .signatureGlass(hovering: hovering)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("titelive.me")
        .accessibilityLabel(L("Made by") + " Titelive")
    }
}

/// Bouton jaune Buy Me a Coffee, en taille réduite (texte #121212, bord noir, capsule).
struct SignatureCoffeeButton: View {
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        Button { openURL(SignatureLinks.coffee) } label: {
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(hovering ? -12 : 0))
                Text(L("Buy me a coffee"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color(red: 1, green: hovering ? 0.914 : 0.867, blue: hovering ? 0.30 : 0)))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.85), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("buymeacoffee.com/titelive")
        .accessibilityLabel(L("Buy me a coffee"))
    }
}

/// Avatar de Titelive (avatar.png dans les ressources de l'app), sinon un « T ».
struct SignatureAvatar: View {
    var size: CGFloat = 16

    private static let image: NSImage? = {
        for name in ["avatar", "Avatar"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png") { return NSImage(contentsOf: url) }
        }
        return nil
    }()

    var body: some View {
        Group {
            if let img = Self.image {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Text("T")
                    .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255))
            }
        }
        .frame(width: size, height: size)
        .background(Color(red: 0.85, green: 0.98, blue: 0.55), in: .circle)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

private extension View {
    /// Verre Liquid Glass sur macOS 26, matériau fin sinon.
    @ViewBuilder func signatureGlass(hovering: Bool) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(hovering ? 0.25 : 0.12)))
        }
    }
}
