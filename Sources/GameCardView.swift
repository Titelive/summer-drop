import AppKit
import Observation
import SwiftUI

// MARK: - Notes personnelles (étoiles)

/// Vos notes de 1 à 5 étoiles, gardées sur le Mac.
@MainActor
@Observable
final class RatingStore {
    static let shared = RatingStore()
    private static let key = "gameRatings"

    private(set) var ratings: [String: Int]

    init() {
        ratings = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
    }

    /// La note est liée au jeu (titre sans région), pour la retrouver sur toutes ses versions.
    static func key(for fileName: String) -> String {
        GameInfoStore.parse(romName: (fileName as NSString).deletingPathExtension).title.lowercased()
    }

    func rating(for fileName: String) -> Int {
        ratings[Self.key(for: fileName)] ?? 0
    }

    func setRating(_ value: Int, for fileName: String) {
        let key = Self.key(for: fileName)
        // Recliquer sur la même étoile efface la note.
        if ratings[key] == value || value == 0 {
            ratings[key] = nil
        } else {
            ratings[key] = min(max(value, 1), 5)
        }
        UserDefaults.standard.set(ratings, forKey: Self.key)
    }
}

struct StarRatingView: View {
    let rating: Int
    var size: CGFloat = 16
    var onSet: ((Int) -> Void)?
    @State private var hovered = 0

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(1...5, id: \.self) { index in
                let filled = index <= (hovered > 0 ? hovered : rating)
                Image(systemName: filled ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(filled ? Color.yellow : Color.secondary.opacity(0.6))
                    .scaleEffect(hovered == index ? 1.2 : 1)
                    .contentTransition(.symbolEffect(.replace))
                    .onHover { inside in
                        guard onSet != nil else { return }
                        hovered = inside ? index : (hovered == index ? 0 : hovered)
                    }
                    .onTapGesture { onSet?(index) }
            }
        }
        .animation(.spring(duration: 0.25), value: hovered)
        .animation(.spring(duration: 0.25), value: rating)
        .accessibilityElement()
        .accessibilityLabel("\(rating) étoile\(rating > 1 ? "s" : "") sur 5")
    }
}

// MARK: - Fiche de jeu

struct GameCardView: View {
    let entry: SDEntry
    @State private var info: GameInfo?
    private let ratings = RatingStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                RemoteImage(url: info?.boxartURL, placeholder: "shippingbox")
                    .frame(width: 120, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    Text(info?.title ?? GameInfoStore.parse(romName: (entry.name as NSString).deletingPathExtension).title)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let line = subtitle {
                        Text(line)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let info, !info.genres.isEmpty {
                        Text(info.genres.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        StarRatingView(rating: ratings.rating(for: entry.name), size: 15) { value in
                            ratings.setRating(value, for: entry.name)
                        }
                        Text("Ma note")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 2)
                }
            }

            HStack(spacing: 10) {
                RemoteImage(url: info?.titleScreenURL, placeholder: "photo")
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                RemoteImage(url: info?.snapURL, placeholder: "gamecontroller")
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            technicalGrid

            if let summary = info?.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.primary.opacity(0.85))
            } else if info == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Recherche des informations…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if let url = info?.wikipediaURL {
                    Link("Lire sur Wikipédia", destination: url)
                        .font(.caption)
                }
                Spacer()
                Text("Sources : Wikipédia, Wikidata, libretro")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(width: 440)
        .task(id: entry.name) {
            let loaded = await GameInfoStore.shared.info(forFileName: entry.name)
            withAnimation(.easeOut(duration: 0.25)) { info = loaded }
        }
    }

    private var subtitle: String? {
        guard let info else { return nil }
        let parts = [info.year, info.developers.first, info.publishers.first.flatMap { $0 == info.developers.first ? nil : $0 }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var technicalGrid: some View {
        let parsed = info ?? GameInfoStore.parse(romName: (entry.name as NSString).deletingPathExtension)
        let ext = (entry.name as NSString).pathExtension.lowercased()
        let format: String
        switch ext {
        case "z64": format = "z64 · big-endian (natif)"
        case "v64": format = "v64 · octets inversés"
        case "n64": format = "n64 · little-endian"
        default: format = ext
        }
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            row("Région", parsed.regions.isEmpty ? "—" : parsed.regions.joined(separator: ", "))
            row("Langues", parsed.languages.isEmpty ? "—" : parsed.languages.joined(separator: ", "))
            row("Taille", entry.sizeText.isEmpty ? "—" : entry.sizeText)
            row("Format", format)
            if let revision = parsed.revision {
                row("Version", revision)
            }
            if !parsed.flags.isEmpty {
                row("Mentions", parsed.flags.joined(separator: ", "))
            }
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// Image distante avec repli élégant si elle n'existe pas.
struct RemoteImage: View {
    let url: URL?
    let placeholder: String

    var body: some View {
        ZStack {
            Rectangle().fill(.primary.opacity(0.06))
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: placeholder)
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    default:
                        ProgressView().controlSize(.small)
                    }
                }
            } else {
                Image(systemName: placeholder)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
        }
        .clipped()
    }
}
