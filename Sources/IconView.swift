import AppKit
import SwiftUI

/// List or icons, chosen per pane.
enum ViewMode: String, Codable {
    case list, icons

    static func load(_ key: String) -> ViewMode {
        ViewMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .list
    }
}

/// The list / icons button in each pane's header.
struct ViewModeButton: View {
    @Binding var mode: ViewMode

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.4)) {
                mode = mode == .list ? .icons : .list
            }
        } label: {
            Image(systemName: mode == .list ? "square.grid.2x2" : "list.bullet")
                .foregroundStyle(.primary)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.glass)
        .help(mode == .list ? L("Show as Icons") : L("Show as List"))
    }
}

/// Icon view shared by both panes: same selection, drag and context menu as the list.
struct EntryGrid<Item: Identifiable, MenuContent: View>: View {
    let sections: [ListSection<Item>]
    let entry: (Item) -> SDEntry
    let isSelected: (Item) -> Bool
    let onTap: (Item) -> Void
    let onOpen: (Item) -> Void
    let onDrag: (Item) -> NSItemProvider
    @ViewBuilder let menu: (Item) -> MenuContent

    private let columns = [GridItem(.adaptive(minimum: 118, maximum: 170), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            GameTile(entry: entry(item), isSelected: isSelected(item))
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                                .onTapGesture(count: 2) { onOpen(item) }
                                .onTapGesture(count: 1) { onTap(item) }
                                .onDrag { onDrag(item) }
                                .contextMenu { menu(item) }
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    } header: {
                        if let title = section.title {
                            SectionHeader(title: title, count: section.items.count)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .softEdges()
    }
}

/// One tile: box art when known, otherwise the game's emoji (or a folder).
struct GameTile: View {
    let entry: SDEntry
    let isSelected: Bool
    @AppStorage("gameCardsEnabled") private var cardsEnabled = true
    @State private var boxart: URL?
    @State private var hovered = false
    private let ratings = RatingStore.shared

    private var displayName: String {
        guard entry.isROM else { return entry.name }
        return GameInfoStore.parse(romName: (entry.name as NSString).deletingPathExtension).title
    }

    var body: some View {
        VStack(spacing: 6) {
            art
                .frame(height: 92)
                .frame(maxWidth: .infinity)
            Text(displayName)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 30, alignment: .top)
            // Fixed height so tiles line up, rated or not.
            StarRatingView(rating: entry.isROM ? ratings.rating(for: entry.name) : 0, size: 8)
                .opacity(entry.isROM && ratings.rating(for: entry.name) > 0 ? 1 : 0)
        }
        .padding(8)
        .background(
            isSelected ? Color.accentColor.opacity(0.35) : Color.white.opacity(hovered ? 0.12 : 0.06),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(isSelected ? 0.6 : 0), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.system(size: 16))
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(hovered ? 1.03 : 1)
        .onHover { hovered = $0 }
        .animation(.spring(duration: 0.25), value: hovered)
        .animation(.spring(duration: 0.25), value: isSelected)
        .help(entry.name)
        .task(id: entry.name) {
            guard entry.isROM, cardsEnabled else { return }
            let url = await GameInfoStore.shared.boxartURL(forFileName: entry.name)
            withAnimation(.easeOut(duration: 0.3)) { boxart = url }
        }
    }

    @ViewBuilder
    private var art: some View {
        if entry.isDirectory {
            Image(systemName: "folder.fill")
                .font(.system(size: 50))
                .foregroundStyle(.blue)
        } else if entry.isSystemFile {
            Image(systemName: "memorychip.fill")
                .font(.system(size: 44))
                .foregroundStyle(.purple)
        } else if let boxart {
            AsyncImage(url: boxart) { phase in
                if case .success(let image) = phase {
                    image.resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .transition(.opacity)
                } else {
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    @ViewBuilder
    private var fallback: some View {
        if entry.isROM, let emoji = GameEmojiStore.shared.emoji(for: entry.name) {
            Text(emoji).font(.system(size: 46))
        } else {
            Image(systemName: entry.isROM ? "gamecontroller.fill" : "doc")
                .font(.system(size: 40))
                .foregroundStyle(entry.isROM ? Color.orange : Color.secondary)
        }
    }
}
