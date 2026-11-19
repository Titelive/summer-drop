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

    private var spacing: CGFloat { size * 0.25 }
    private var cell: CGFloat { size * 1.15 }
    private var shown: Int { hovered > 0 ? hovered : rating }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { index in
                let filled = index <= shown
                // Each star keeps the same size and place: only the yellow fill fades and grows in.
                ZStack {
                    Image(systemName: "star")
                        .foregroundStyle(Color.secondary.opacity(0.55))
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color.yellow.opacity(hovered > 0 && index > rating ? 0.6 : 1))
                        .scaleEffect(filled ? 1 : 0.4)
                        .opacity(filled ? 1 : 0)
                }
                .font(.system(size: size))
                .frame(width: cell, height: cell)
                .contentShape(Rectangle())
                .onTapGesture { onSet?(index) }
            }
        }
        // One hover zone for the whole row of stars: no flicker in the gaps between them.
        .onContinuousHover { phase in
            guard onSet != nil else { return }
            switch phase {
            case .active(let point):
                hovered = min(max(Int(point.x / (cell + spacing)) + 1, 1), 5)
            case .ended:
                hovered = 0
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.spring(duration: 0.3, bounce: 0.35), value: rating)
        .accessibilityElement()
        .accessibilityLabel(L("{0} star{1} out of 5", "\(rating)", "\(rating > 1 ? "s" : "")"))
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
                RemoteImage(url: info?.boxartURL, placeholder: "gamecontroller", loading: info == nil)
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
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
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
                        Text(L("My rating"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 2)
                }
            }

            // Captures : seulement celles qui existent (zone de hauteur fixe pour ne pas
            // redimensionner la bulle pendant le chargement).
            HStack(spacing: 10) {
                if info == nil {
                    RemoteImage(url: nil, placeholder: "photo", loading: true)
                    RemoteImage(url: nil, placeholder: "photo", loading: true)
                } else if info?.titleScreenURL == nil && info?.snapURL == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                        Text(L("No screenshots found for this game"))
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if let url = info?.titleScreenURL {
                        RemoteImage(url: url, placeholder: "photo")
                    }
                    if let url = info?.snapURL {
                        RemoteImage(url: url, placeholder: "photo")
                    }
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            technicalGrid

            Group {
                if let summary = info?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.callout)
                        .lineLimit(5)
                        .foregroundStyle(.primary.opacity(0.85))
                } else if info == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("Looking up information…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(L("No summary found."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if let url = info?.wikipediaURL {
                    Link(L("Read on Wikipedia"), destination: url)
                        .font(.caption)
                }
                Spacer()
                if info?.imagesFoundByAI == true {
                    Label(L("Images found by Apple's AI"), systemImage: "apple.intelligence")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help(L("The on-device AI recognized the game; check that these are the right images."))
                }
                Text(L("Sources: Wikipedia, Wikidata, libretro"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        // Taille fixe : une bulle qui change de taille pendant son affichage fait planter AppKit.
        .frame(width: 460, height: 560, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.75))
        .task(id: entry.name) {
            let loaded = await GameInfoStore.shared.info(forFileName: entry.name)
            info = loaded
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
        case "z64": format = L("z64 · big-endian (native)")
        case "v64": format = L("v64 · byte-swapped")
        case "n64": format = "n64 · little-endian"
        default: format = ext
        }
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            if !parsed.regions.isEmpty {
                row(L("Region"), parsed.regions.joined(separator: ", "))
            }
            if !parsed.languages.isEmpty {
                row(L("Languages"), parsed.languages.joined(separator: ", "))
            }
            row(L("Size"), entry.sizeText.isEmpty ? "—" : entry.sizeText)
            row("Format", format)
            if let revision = parsed.revision {
                row("Version", revision)
            }
            if !parsed.flags.isEmpty {
                row(L("Tags"), parsed.flags.joined(separator: ", "))
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
    var loading = false

    var body: some View {
        ZStack {
            Rectangle().fill(.primary.opacity(0.06))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Image(systemName: placeholder)
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    default:
                        ProgressView().controlSize(.small)
                    }
                }
            } else if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: placeholder)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
        }
        .clipped()
    }
}
