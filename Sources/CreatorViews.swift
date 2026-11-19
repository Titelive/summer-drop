import AppKit
import SwiftUI

enum Creator {
    static let name = "Titelive"
    static let servicesURL = URL(string: "https://titelive.me/prestations/")!
    static let coffeeURL = URL(string: "https://buymeacoffee.com/titelive")!

    static var avatar: NSImage? {
        guard let url = Bundle.main.url(forResource: "Avatar", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// Gabarit commun aux deux pastilles : même hauteur, même verre, même typographie.
private struct PillLabel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .font(.callout)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .contentShape(Capsule())
    }
}

/// Pastille « Créé par [avatar] Titelive » qui mène vers les prestations.
struct CreatorPill: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(Creator.servicesURL)
        } label: {
            PillLabel {
                Text(L("Made by"))
                    .foregroundStyle(.secondary)
                Group {
                    if let avatar = Creator.avatar {
                        Image(nsImage: avatar)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                    }
                }
                .frame(width: 20, height: 20)
                .clipShape(Circle())
                Text(Creator.name)
                    .fontWeight(.semibold)
            }
        }
        .buttonStyle(.plain)
        .glassEffect(Glass.regular.interactive(), in: .capsule)
        .help(L("Discover {0}'s services", "\(Creator.name)"))
    }
}

/// Bouton « Offrir un café » vers Buy Me a Coffee.
struct CoffeeButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(Creator.coffeeURL)
        } label: {
            PillLabel {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(.yellow)
                    .frame(width: 20, height: 20)
                Text(L("Buy me a coffee"))
                    .fontWeight(.semibold)
            }
        }
        .buttonStyle(.plain)
        .glassEffect(Glass.regular.interactive(), in: .capsule)
        .help(L("Support {0} on Buy Me a Coffee", "\(Creator.name)"))
    }
}

/// Les deux côte à côte.
struct CreatorBar: View {
    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                CreatorPill()
                CoffeeButton()
            }
        }
    }
}
