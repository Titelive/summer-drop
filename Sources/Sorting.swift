import Foundation
import SwiftUI

// MARK: - Sort and group options

enum SortKey: String, CaseIterable, Identifiable, Codable {
    case name, size, date, rating, region

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return L("Name")
        case .size: return L("Size")
        case .date: return L("Date")
        case .rating: return L("My rating")
        case .region: return L("Region")
        }
    }

    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .size: return "internaldrive"
        case .date: return "calendar"
        case .rating: return "star"
        case .region: return "globe"
        }
    }
}

enum GroupKey: String, CaseIterable, Identifiable, Codable {
    case none, letter, region, rating, format

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return L("No groups")
        case .letter: return L("First letter")
        case .region: return L("Region")
        case .rating: return L("My rating")
        case .format: return L("Format")
        }
    }
}

struct SortOptions: Codable, Equatable {
    var key: SortKey = .name
    var ascending = true
    var group: GroupKey = .none

    var isDefault: Bool { self == SortOptions() }

    static func load(_ storageKey: String) -> SortOptions {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let options = try? JSONDecoder().decode(SortOptions.self, from: data) else { return SortOptions() }
        return options
    }

    func save(_ storageKey: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

/// A titled run of rows (title is nil when the list is not grouped).
struct ListSection<Item>: Identifiable {
    let id: String
    let title: String?
    let items: [Item]
}

@MainActor
enum ListArranger {
    /// Sorts (folders first), then groups the items.
    static func arrange<Item>(_ items: [Item], options: SortOptions, entry: (Item) -> SDEntry) -> [ListSection<Item>] {
        let ratings = RatingStore.shared
        func rating(_ e: SDEntry) -> Int { e.isDirectory ? 0 : ratings.rating(for: e.name) }
        func region(_ e: SDEntry) -> String {
            GameInfoStore.parse(romName: (e.name as NSString).deletingPathExtension).regions.first ?? ""
        }
        func byName(_ a: SDEntry, _ b: SDEntry) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        let sorted = items.sorted { lhsItem, rhsItem in
            let lhs = entry(lhsItem), rhs = entry(rhsItem)
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            let result: ComparisonResult
            switch options.key {
            case .name: result = lhs.name.localizedStandardCompare(rhs.name)
            case .size: result = compare(lhs.approxBytes, rhs.approxBytes)
            case .date: result = lhs.date.compare(rhs.date)
            case .rating: result = compare(rating(lhs), rating(rhs))
            case .region:
                let a = region(lhs), b = region(rhs)
                // Unknown region always last.
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                result = a.localizedStandardCompare(b)
            }
            if result == .orderedSame { return byName(lhs, rhs) }
            return options.ascending ? result == .orderedAscending : result == .orderedDescending
        }

        guard options.group != .none else {
            return [ListSection(id: "all", title: nil, items: sorted)]
        }

        let folders = sorted.filter { entry($0).isDirectory }
        let files = sorted.filter { !entry($0).isDirectory }

        func groupTitle(_ e: SDEntry) -> (order: String, title: String) {
            switch options.group {
            case .none:
                return ("", "")
            case .letter:
                let title = GameInfoStore.parse(romName: (e.name as NSString).deletingPathExtension).title
                guard let first = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first else { return ("~", "#") }
                return first.isLetter ? (String(first).uppercased(), String(first).uppercased()) : ("0", "#")
            case .region:
                let value = region(e)
                return value.isEmpty ? ("~", L("Unknown region")) : (value, value)
            case .rating:
                let value = rating(e)
                return (String(9 - value), value == 0 ? L("Not rated") : String(repeating: "★", count: value))
            case .format:
                let ext = (e.name as NSString).pathExtension.lowercased()
                return ext.isEmpty ? ("~", L("Other files")) : (ext, "." + ext)
            }
        }

        var order: [String] = []
        var buckets: [String: (title: String, items: [Item])] = [:]
        for item in files {
            let (key, title) = groupTitle(entry(item))
            if buckets[key] == nil { order.append(key); buckets[key] = (title, []) }
            buckets[key]?.items.append(item)
        }
        var sections: [ListSection<Item>] = []
        if !folders.isEmpty {
            sections.append(ListSection(id: "folders", title: L("Folders"), items: folders))
        }
        // Letters, regions and formats read A→Z (or Z→A when descending); ratings go from 5 stars down.
        let keys = order.sorted { a, b in
            if a == "~" || b == "~" { return b == "~" && a != "~" }
            if options.group == .rating { return a < b }
            return options.ascending ? a.localizedStandardCompare(b) == .orderedAscending
                                     : a.localizedStandardCompare(b) == .orderedDescending
        }
        for key in keys {
            if let bucket = buckets[key] {
                sections.append(ListSection(id: key, title: bucket.title, items: bucket.items))
            }
        }
        return sections
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}

// MARK: - Views

/// The ↑↓ button in each pane's header.
struct SortMenu: View {
    @Binding var options: SortOptions

    var body: some View {
        Menu {
            Picker(L("Sort by"), selection: $options.key) {
                ForEach(SortKey.allCases) { key in
                    Label(key.label, systemImage: key.systemImage).tag(key)
                }
            }
            .pickerStyle(.inline)

            Picker(L("Order"), selection: $options.ascending) {
                Text(L("Ascending")).tag(true)
                Text(L("Descending")).tag(false)
            }
            .pickerStyle(.inline)

            Picker(L("Group by"), selection: $options.group) {
                ForEach(GroupKey.allCases) { key in
                    Text(key.label).tag(key)
                }
            }
            .pickerStyle(.inline)

            if !options.isDefault {
                Divider()
                Button(L("Reset Sorting")) { options = SortOptions() }
            }
        } label: {
            Image(systemName: options.isDefault ? "arrow.up.arrow.down" : "arrow.up.arrow.down.circle.fill")
                .frame(width: 16, height: 16)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .fixedSize()
        .help(L("Sort and group"))
    }
}

/// Small header above each group of rows.
struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}
