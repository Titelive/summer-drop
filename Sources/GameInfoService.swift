import Foundation

/// Fiche d'un jeu : infos tirées du nom No-Intro de la ROM, de Wikipédia/Wikidata
/// et des vignettes libretro (jaquette, écran-titre, capture). Aucune clé d'API.
struct GameInfo: Codable, Sendable, Equatable {
    var romName: String
    var title: String
    var regions: [String] = []
    var languages: [String] = []
    var revision: String?
    var flags: [String] = []

    var wikiTitle: String?
    var summary: String?
    var year: String?
    var developers: [String] = []
    var publishers: [String] = []
    var genres: [String] = []
    var wikipediaURL: URL?

    /// Titres alternatifs (Wikidata) : aident à retrouver les images.
    var alternateTitles: [String] = []
    /// Vrai si l'image a été trouvée grâce à l'IA d'Apple.
    var imagesFoundByAI = false

    var boxartURL: URL?
    var titleScreenURL: URL?
    var snapURL: URL?
}

actor GameInfoStore {
    static let shared = GameInfoStore()

    private var memory: [String: GameInfo] = [:]
    private var inFlight: [String: Task<GameInfo, Never>] = [:]

    private static let userAgent = "SummerDrop/1.3 (https://github.com/Titelive/summer-drop)"

    private var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("SummerDrop/GameInfo2/\(AppLanguage.current.rawValue)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Renvoie la fiche (mémoire, puis disque, puis Internet).
    func info(forFileName fileName: String) async -> GameInfo {
        let romName = (fileName as NSString).deletingPathExtension
        let key = AppLanguage.current.rawValue + "|" + romName
        if let cached = memory[key] { return cached }

        let file = cacheDirectory.appendingPathComponent(Self.safeFileName(romName) + ".json")
        if let data = try? Data(contentsOf: file),
           let cached = try? JSONDecoder().decode(GameInfo.self, from: data) {
            memory[key] = cached
            return cached
        }

        if let running = inFlight[key] { return await running.value }
        let task = Task { await Self.build(romName: romName) }
        inFlight[key] = task
        let info = await task.value
        inFlight[key] = nil
        memory[key] = info
        // On ne met en cache disque que les fiches enrichies (sinon on réessaiera plus tard).
        if info.wikiTitle != nil, let data = try? JSONEncoder().encode(info) {
            try? data.write(to: file)
        }
        return info
    }

    private var boxartMemo: [String: URL?] = [:]

    /// Box art only (for the icon view): quicker than a full card, no Wikipedia call
    /// unless the card is already cached.
    func boxartURL(forFileName fileName: String) async -> URL? {
        let romName = (fileName as NSString).deletingPathExtension
        if let memo = boxartMemo[romName] { return memo }
        let key = AppLanguage.current.rawValue + "|" + romName
        if let cached = memory[key] { return cached.boxartURL }
        let file = cacheDirectory.appendingPathComponent(Self.safeFileName(romName) + ".json")
        if let data = try? Data(contentsOf: file),
           let cached = try? JSONDecoder().decode(GameInfo.self, from: data) {
            memory[key] = cached
            return cached.boxartURL
        }
        guard let names = await ThumbnailIndex.shared.load() else { return nil }
        let match = await ThumbnailIndex.shared.bestMatch(
            romName: romName, alternateTitles: [], regions: Self.parseRegionKeys(romName)
        )
        var url: URL?
        if let match, names.boxarts.contains(match.name) {
            let real = await ThumbnailIndex.shared.resolve(kind: "Named_Boxarts", name: match.name)
            url = Self.thumbnailURL(kind: "Named_Boxarts", romName: real)
        }
        boxartMemo[romName] = .some(url)
        return url
    }

    func clearCache() {
        boxartMemo = [:]
        memory = [:]
        try? FileManager.default.removeItem(at: cacheDirectory.deletingLastPathComponent())
    }

    // MARK: - Construction

    static func build(romName: String) async -> GameInfo {
        var info = parse(romName: romName)
        await enrichFromWikipedia(&info)

        // Images : seulement celles qui existent vraiment (plus de cases vides).
        if let names = await ThumbnailIndex.shared.load() {
            let regionKeys = parseRegionKeys(romName)
            let result = await ThumbnailIndex.shared.bestMatch(
                romName: romName,
                alternateTitles: info.alternateTitles + [info.wikiTitle].compactMap { $0 }.map(ThumbnailIndex.baseTitle),
                regions: regionKeys
            )
            if let (match, viaAI) = result {
                info.imagesFoundByAI = viaAI
                let index = ThumbnailIndex.shared
                if names.boxarts.contains(match) {
                    info.boxartURL = thumbnailURL(kind: "Named_Boxarts", romName: await index.resolve(kind: "Named_Boxarts", name: match))
                }
                if names.titles.contains(match) {
                    info.titleScreenURL = thumbnailURL(kind: "Named_Titles", romName: await index.resolve(kind: "Named_Titles", name: match))
                }
                if names.snaps.contains(match) {
                    info.snapURL = thumbnailURL(kind: "Named_Snaps", romName: await index.resolve(kind: "Named_Snaps", name: match))
                }
            }
        } else {
            // Index indisponible : on tente le nom exact.
            info.boxartURL = thumbnailURL(kind: "Named_Boxarts", romName: romName)
            info.titleScreenURL = thumbnailURL(kind: "Named_Titles", romName: romName)
            info.snapURL = thumbnailURL(kind: "Named_Snaps", romName: romName)
        }
        return info
    }

    /// « Banjo-Tooie (Europe) (En,Fr,De,Es) (Rev 1) » → titre, régions, langues, révision.
    static func parse(romName: String) -> GameInfo {
        var title = romName
        if let cut = romName.firstIndex(where: { $0 == "(" || $0 == "[" }) {
            title = String(romName[..<cut]).trimmingCharacters(in: .whitespaces)
        }
        var info = GameInfo(romName: romName, title: title.isEmpty ? romName : title)

        let regionNames: [String: String] = [
            "Europe": "Europe", "USA": L("USA"), "Japan": L("Japan"), "France": "France",
            "Germany": L("Germany"), "Spain": L("Spain"), "Italy": L("Italy"), "Australia": L("Australia"),
            "World": L("World"), "Brazil": L("Brazil"), "Korea": L("Korea"), "Canada": "Canada",
            "Netherlands": L("Netherlands"), "Sweden": L("Sweden"), "UK": L("UK"), "China": L("China"),
        ]
        let languageNames: [String: String] = [
            "En": L("English"), "Fr": L("French"), "De": L("German"), "Es": L("Spanish"), "It": L("Italian"),
            "Nl": L("Dutch"), "Ja": L("Japanese"), "Sv": L("Swedish"), "Pt": L("Portuguese"), "Da": L("Danish"),
            "Fi": L("Finnish"), "No": L("Norwegian"), "Zh": L("Chinese"), "Ko": L("Korean"),
        ]

        var groups: [String] = []
        var current: String?
        for character in romName {
            if character == "(" { current = "" }
            else if character == ")" { if let value = current { groups.append(value) }; current = nil }
            else if current != nil { current?.append(character) }
        }

        for group in groups {
            let parts = group.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if !parts.isEmpty, parts.allSatisfy({ regionNames[$0] != nil }) {
                info.regions += parts.compactMap { regionNames[$0] }
            } else if !parts.isEmpty, parts.allSatisfy({ $0.count == 2 && languageNames[$0] != nil }) {
                info.languages += parts.compactMap { languageNames[$0] }
            } else if group.hasPrefix("Rev ") {
                info.revision = L("Revision {0}", String(group.dropFirst(4)))
            } else {
                info.flags.append(group)
            }
        }
        return info
    }

    /// Régions en anglais (telles qu'écrites dans les noms No-Intro).
    static func parseRegionKeys(_ romName: String) -> [String] {
        let known = ["Europe", "USA", "Japan", "France", "Germany", "Spain", "Italy", "Australia", "World"]
        return known.filter { romName.contains($0) }
    }

    /// Les vignettes libretro remplacent &*/:`<>?\|" par « _ ».
    static func thumbnailURL(kind: String, romName: String) -> URL? {
        let forbidden = Set("&*/:`<>?\\|\"")
        let safe = String(romName.map { forbidden.contains($0) ? "_" : $0 })
        guard let encoded = (safe + ".png").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://raw.githubusercontent.com/libretro-thumbnails/Nintendo_-_Nintendo_64/master/\(kind)/\(encoded)")
    }

    // MARK: - Wikipédia / Wikidata

    private static func json(_ url: URL) async -> [String: Any]? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func url(_ base: String, _ query: [String: String]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }

    static func enrichFromWikipedia(_ info: inout GameInfo) async {
        // 1. Recherche de l'article (anglais : couverture la plus large) et de son élément Wikidata.
        guard let searchURL = url("https://en.wikipedia.org/w/api.php", [
            "action": "query", "format": "json", "generator": "search",
            "gsrsearch": "\(info.title) Nintendo 64 video game", "gsrlimit": "8",
            "prop": "pageprops", "ppprop": "wikibase_item",
        ]), let search = await json(searchURL),
              let pages = (search["query"] as? [String: Any])?["pages"] as? [String: Any] else { return }

        let ranked = pages.values
            .compactMap { $0 as? [String: Any] }
            .sorted { ($0["index"] as? Int ?? 99) < ($1["index"] as? Int ?? 99) }
        // On préfère l'article dont le titre correspond au jeu (« Banjo-Tooie » plutôt que « Banjo-Kazooie »,
        // « Super Mario 64 » plutôt que « Super Mario 64 DS »).
        func normalized(_ text: String) -> String {
            var value = text
            if let cut = value.range(of: " (") { value = String(value[..<cut.lowerBound]) }
            return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        let wanted = normalized(info.title)
        let exact = ranked.first { normalized($0["title"] as? String ?? "") == wanted }
        let prefix = ranked.first { normalized($0["title"] as? String ?? "").hasPrefix(wanted) }
        guard let page = exact ?? prefix ?? ranked.first,
              let enTitle = page["title"] as? String else { return }
        let qid = (page["pageprops"] as? [String: Any])?["wikibase_item"] as? String
        info.wikiTitle = enTitle

        // 2. Données structurées Wikidata.
        var localTitle: String?
        if let qid, let entityURL = URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(qid).json"),
           let root = await json(entityURL),
           let entity = (root["entities"] as? [String: Any])?[qid] as? [String: Any] {
            let claims = entity["claims"] as? [String: Any] ?? [:]
            localTitle = ((entity["sitelinks"] as? [String: Any])?["\(AppLanguage.current.wikiCode)wiki"] as? [String: Any])?["title"] as? String

            // Titres alternatifs (libellés et alias), utiles pour les noms japonais ou européens.
            var alternates: [String] = []
            for (_, value) in entity["labels"] as? [String: Any] ?? [:] {
                if let label = (value as? [String: Any])?["value"] as? String { alternates.append(label) }
            }
            for (_, list) in entity["aliases"] as? [String: Any] ?? [:] {
                for alias in list as? [[String: Any]] ?? [] {
                    if let value = alias["value"] as? String { alternates.append(value) }
                }
            }
            info.alternateTitles = Array(Set(alternates.filter { $0.unicodeScalars.allSatisfy { $0.value < 0x3000 } })).sorted()

            func itemIDs(_ property: String) -> [String] {
                (claims[property] as? [[String: Any]] ?? []).compactMap { claim in
                    (((claim["mainsnak"] as? [String: Any])?["datavalue"] as? [String: Any])?["value"] as? [String: Any])?["id"] as? String
                }
            }

            // Année de sortie : la plus ancienne.
            let times = (claims["P577"] as? [[String: Any]] ?? []).compactMap { claim in
                (((claim["mainsnak"] as? [String: Any])?["datavalue"] as? [String: Any])?["value"] as? [String: Any])?["time"] as? String
            }
            if let earliest = times.sorted().first {
                info.year = String(earliest.dropFirst().prefix(4))
            }

            let developers = itemIDs("P178"), publishers = itemIDs("P123"), genres = itemIDs("P136")
            let labels = await labelsFor(Array(Set(developers + publishers + genres)))

            info.developers = developers.compactMap { labels[$0] }
            info.publishers = Array(publishers.compactMap { labels[$0] }.prefix(3))
            info.genres = Array(genres.compactMap { labels[$0] }.prefix(3))

        }

        // 3. Résumé, en français si l'article existe.
        let useLocal = AppLanguage.current != .english && localTitle != nil
        let summaryLanguage = useLocal ? AppLanguage.current.wikiCode : "en"
        let summaryTitle = useLocal ? (localTitle ?? enTitle) : enTitle
        if let encoded = summaryTitle.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: "/", with: "%2F"),
           let summaryURL = URL(string: "https://\(summaryLanguage).wikipedia.org/api/rest_v1/page/summary/\(encoded)"),
           let summary = await json(summaryURL) {
            info.summary = summary["extract"] as? String
            if let page = ((summary["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String {
                info.wikipediaURL = URL(string: page)
            }
        }
    }

    private static func labelsFor(_ ids: [String]) async -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        var result: [String: String] = [:]
        // wbgetentities accepte 50 identifiants par appel.
        for chunk in stride(from: 0, to: ids.count, by: 50).map({ Array(ids[$0..<min($0 + 50, ids.count)]) }) {
            guard let labelsURL = url("https://www.wikidata.org/w/api.php", [
                "action": "wbgetentities", "format": "json", "props": "labels",
                "languages": "\(AppLanguage.current.wikidataCode)|en", "ids": chunk.joined(separator: "|"),
            ]), let root = await json(labelsURL),
                  let entities = root["entities"] as? [String: Any] else { continue }
            for (id, value) in entities {
                let labels = (value as? [String: Any])?["labels"] as? [String: Any] ?? [:]
                let local = (labels[AppLanguage.current.wikidataCode] as? [String: Any])?["value"] as? String
                let en = (labels["en"] as? [String: Any])?["value"] as? String
                if let label = local ?? en { result[id] = label }
            }
        }
        return result
    }

    private static func safeFileName(_ name: String) -> String {
        let forbidden = Set("/:\\")
        return String(name.map { forbidden.contains($0) ? "_" : $0 })
    }
}
