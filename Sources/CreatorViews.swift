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

/// Pastille « Créé par [avatar] Titelive » qui mène vers les prestations.
struct CreatorPill: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(Creator.servicesURL)
        } label: {
            HStack(spacing: 8) {
                Text("Créé par")
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
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(Glass.regular.interactive(), in: .capsule)
        .help("Découvrir les prestations de \(Creator.name)")
    }
}

/// Bouton « Offrir un café » vers Buy Me a Coffee.
struct CoffeeButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(Creator.coffeeURL)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cup.and.saucer.fill")
                Text("Offrir un café")
                    .fontWeight(.medium)
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(Glass.regular.tint(Color.yellow.opacity(0.35)).interactive(), in: .capsule)
        .help("Soutenir \(Creator.name) sur Buy Me a Coffee")
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
