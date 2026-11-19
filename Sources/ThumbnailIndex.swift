import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Index des vignettes libretro (noms de fichiers existants), pour retrouver une image
/// même quand le nom de la ROM ne correspond pas exactement (traductions, dumps GoodN64…).
actor ThumbnailIndex {
    static let shared = ThumbnailIndex()

    struct Names: Codable {
        var boxarts: Set<String> = []
        var titles: Set<String> = []
        var snaps: Set<String> = []
        /// "Kind/name" of images that are git symlinks to another image (e.g. a Rev 1 pointing to the original).
        var links: Set<String> = []
        var fetched = Date.distantPast
    }

    private var names: Names?
    private var resolvedLinks: [String: String] = [:]

    /// The real image name: follows libretro's symlinks, which raw.githubusercontent.com
    /// serves as a tiny text file holding the target's name instead of the picture.
    func resolve(kind: String, name: String) async -> String {
        let key = kind + "/" + name
        guard let names = await load(), names.links.contains(key) else { return name }
        if let known = resolvedLinks[key] { return known }
        guard let url = GameInfoStore.thumbnailURL(kind: kind, romName: name),
              let (data, _) = try? await URLSession.shared.data(from: url),
              data.count < 1024,
              let text = String(data: data, encoding: .utf8) else { return name }
        let file = (text.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).lastPathComponent
        let target = (file as NSString).deletingPathExtension
        guard !target.isEmpty else { return name }
        resolvedLinks[key] = target
        return target
    }
    private var loading: Task<Names?, Never>?

    private var cacheFile: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("SummerDrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("libretro-index.json")
    }

    func load() async -> Names? {
        if let names { return names }
        if let data = try? Data(contentsOf: cacheFile),
           let cached = try? JSONDecoder().decode(Names.self, from: data),
           Date().timeIntervalSince(cached.fetched) < 7 * 24 * 3600 {
            names = cached
            return cached
        }
        if let loading { return await loading.value }
        let task = Task { await Self.fetch() }
        loading = task
        let result = await task.value
        loading = nil
        if let result {
            names = result
            if let data = try? JSONEncoder().encode(result) { try? data.write(to: cacheFile) }
        }
        return result
    }

    private static func fetch() async -> Names? {
        guard let url = URL(string: "https://api.github.com/repos/libretro-thumbnails/Nintendo_-_Nintendo_64/git/trees/master?recursive=1") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SummerDrop (https://github.com/Titelive/summer-drop)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tree = root["tree"] as? [[String: Any]] else { return nil }
        var names = Names(fetched: Date())
        for item in tree {
            guard let path = item["path"] as? String, path.hasSuffix(".png") else { continue }
            let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let name = String(parts[1].dropLast(4))
            if item["mode"] as? String == "120000" { names.links.insert(parts[0] + "/" + name) }
            switch parts[0] {
            case "Named_Boxarts": names.boxarts.insert(name)
            case "Named_Titles": names.titles.insert(name)
            case "Named_Snaps": names.snaps.insert(name)
            default: break
            }
        }
        return names.boxarts.isEmpty ? nil : names
    }

    // MARK: - Correspondance

    /// Forme comparable : minuscules, sans accents, « ō » → « ou » (romanisation No-Intro).
    static func normalize(_ text: String) -> String {
        var value = text.lowercased()
            .replacingOccurrences(of: "ō", with: "ou")
            .replacingOccurrences(of: "ū", with: "uu")
            .replacingOccurrences(of: "&", with: " and ")
        value = value.folding(options: [.diacriticInsensitive], locale: nil)
        let cleaned = value.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    static func baseTitle(_ name: String) -> String {
        guard let cut = name.firstIndex(where: { $0 == "(" || $0 == "[" }) else { return name }
        return String(name[..<cut]).trimmingCharacters(in: .whitespaces)
    }

    private static func tokens(_ text: String) -> Set<String> {
        Set(normalize(text).split(separator: " ").map(String.init).filter { $0.count > 1 })
    }

    /// Trouve le nom libretro le plus proche : titre exact (ou titre alternatif),
    /// région préférée, puis ressemblance des mots, puis IA d'Apple sur l'appareil.
    func bestMatch(romName: String, alternateTitles: [String], regions: [String]) async -> (name: String, viaAI: Bool)? {
        guard let names = await load() else { return nil }
        let all = names.boxarts.union(names.titles).union(names.snaps)
        if all.contains(romName) { return (romName, false) }

        let wanted = Set(([Self.baseTitle(romName)] + alternateTitles).map(Self.normalize).filter { !$0.isEmpty })
        let sameTitle = all.filter { wanted.contains(Self.normalize(Self.baseTitle($0))) }
        if let pick = Self.preferRegion(Array(sameTitle), regions: regions) { return (pick, false) }

        // Ressemblance des mots (Jaccard).
        let romTokens = Self.tokens(Self.baseTitle(romName))
        var best: (name: String, score: Double)?
        var shortlist: [(String, Double)] = []
        for name in all {
            let other = Self.tokens(Self.baseTitle(name))
            guard !other.isEmpty, !romTokens.isEmpty else { continue }
            let score = Double(romTokens.intersection(other).count) / Double(romTokens.union(other).count)
            if score > 0 { shortlist.append((name, score)) }
            if score > (best?.score ?? 0) { best = (name, score) }
        }
        if let best, best.score >= 0.6 {
            let sameBase = all.filter { Self.baseTitle($0) == Self.baseTitle(best.name) }
            return (Self.preferRegion(Array(sameBase), regions: regions) ?? best.name, false)
        }

        // Dernier recours : l'IA d'Apple, sur l'appareil, choisit parmi de vrais noms.
        let candidates = shortlist.sorted { $0.1 > $1.1 }.prefix(25).map(\.0)
        let alternates = all.filter { name in
            alternateTitles.contains { Self.tokens(Self.baseTitle(name)).isSuperset(of: Self.tokens($0)) && !Self.tokens($0).isEmpty }
        }
        guard let answer = await Self.askAI(romName: romName, candidates: Array(Set(candidates + alternates)).sorted(), all: all) else { return nil }
        return (answer, true)
    }

    private static func preferRegion(_ names: [String], regions: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let order = ["Europe", "France", "USA", "World", "Japan"]
        func rank(_ name: String) -> Int {
            for region in regions where name.contains(region) { return 0 }
            for (index, region) in order.enumerated() where name.contains("(\(region)") || name.contains(", \(region)") {
                return index + 1
            }
            return 99
        }
        return names.sorted { rank($0) < rank($1) || (rank($0) == rank($1) && $0.count < $1.count) }.first
    }

    static var aiAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    private static func askAI(romName: String, candidates: [String], all: Set<String>) async -> String? {
        #if canImport(FoundationModels)
        guard aiAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
        You match Nintendo 64 ROM file names to official No-Intro titles. \
        Games can have Japanese, European or American names (for example Animal Forest is "Doubutsu no Mori"). \
        Answer with the exact No-Intro title only, without region or extension, or NONE if you do not know.
        """)
        let list = candidates.isEmpty ? "" : "\nPossible names:\n" + candidates.joined(separator: "\n")
        guard let response = try? await session.respond(to: "ROM file: \(romName)\(list)") else { return nil }
        let answer = response.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`."))
        guard !answer.isEmpty, answer.uppercased() != "NONE" else { return nil }
        // On ne garde la réponse que si elle désigne un vrai fichier libretro.
        if all.contains(answer) { return answer }
        let target = normalize(baseTitle(answer))
        let matches = all.filter { normalize(baseTitle($0)) == target }
        return preferRegion(Array(matches), regions: [])
        #else
        return nil
        #endif
    }
}
