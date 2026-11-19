import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// An emoji for each game, shown in the lists instead of a generic controller.
/// Known titles come from a built-in list; the others are asked once to Apple's
/// on-device model, and the answer is kept on the Mac.
@MainActor
@Observable
final class GameEmojiStore {
    static let shared = GameEmojiStore()
    private static let cacheKey = "gameEmojis"

    /// Title (lowercased) → emoji, answers from the on-device model.
    private var cache: [String: String]
    @ObservationIgnored private var pending: [String] = []
    @ObservationIgnored private var queued: Set<String> = []
    @ObservationIgnored private var working = false

    private init() {
        cache = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: String] ?? [:]
    }

    /// The emoji for a ROM file name, or nil while unknown (the controller is shown then).
    func emoji(for fileName: String) -> String? {
        let title = GameInfoStore.parse(romName: (fileName as NSString).deletingPathExtension).title
        let key = title.lowercased()
        if let known = Self.builtIn(for: key) { return known }
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }
        request(title: title, key: key)
        return nil
    }

    func clear() {
        cache = [:]
        queued = []
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
    }

    // MARK: On-device model, one question at a time

    private func request(title: String, key: String) {
        guard Self.aiAvailable, !queued.contains(key) else { return }
        queued.insert(key)
        pending.append(title)
        guard !working else { return }
        working = true
        Task { await drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let title = pending.removeFirst()
            let answer = await Self.askAI(title: title) ?? ""
            cache[title.lowercased()] = answer
            UserDefaults.standard.set(cache, forKey: Self.cacheKey)
        }
        working = false
    }

    private static var aiAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    nonisolated private static func askAI(title: String) async -> String? {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: """
        You pick one emoji that best represents a Nintendo 64 game: its hero, its theme or its genre \
        (for example Banjo-Kazooie 🐻, Wave Race 64 🌊, Doom 64 👹, Mario Kart 64 🏎️). \
        Answer with a single emoji and nothing else. Never answer 🎮.
        """)
        guard let response = try? await session.respond(to: "Game: \(title)") else { return nil }
        return firstEmoji(in: response.content)
        #else
        return nil
        #endif
    }

    /// The first emoji character of a text, if any.
    nonisolated static func firstEmoji(in text: String) -> String? {
        for character in text {
            guard let scalar = character.unicodeScalars.first else { continue }
            let props = scalar.properties
            if props.isEmojiPresentation || (props.isEmoji && scalar.value > 0x238C && character.unicodeScalars.count > 1) {
                return character == "🎮" ? nil : String(character)
            }
        }
        return nil
    }

    // MARK: Built-in list (most specific first)

    nonisolated private static func builtIn(for title: String) -> String? {
        let text = title.replacingOccurrences(of: "é", with: "e")
        for (keyword, emoji) in known where text.contains(keyword) {
            return emoji
        }
        return nil
    }

    nonisolated private static let known: [(String, String)] = [
        ("dr. mario", "💊"), ("dr mario", "💊"),
        ("mario kart", "🏎️"), ("mario party", "🎲"), ("mario tennis", "🎾"), ("mario golf", "⛳"),
        ("paper mario", "📜"), ("mario", "🍄"),
        ("yoshi", "🦖"), ("diddy kong", "🐒"), ("donkey kong", "🦍"),
        ("banjo", "🐻"), ("conker", "🐿️"),
        ("majora", "🎭"), ("ocarina", "🎶"), ("zelda", "🗡️"),
        ("pokemon snap", "📸"), ("pokemon puzzle", "🧩"), ("pokemon", "⚡"), ("pikachu", "⚡"), ("pocket monsters", "⚡"),
        ("kirby", "⭐"), ("star fox", "🦊"), ("lylat", "🦊"), ("f-zero", "🏁"), ("wave race", "🌊"),
        ("1080", "🏂"), ("snowboard", "🏂"), ("smash bros", "🥊"), ("pilotwings", "🪂"),
        ("animal forest", "🍃"), ("doubutsu", "🍃"), ("animal crossing", "🍃"),
        ("goldeneye", "🕵️"), ("007", "🕵️"), ("goldfinger", "🕵️"), ("perfect dark", "🔫"),
        ("turok", "🦖"), ("dinosaur planet", "🦕"),
        ("doom", "👹"), ("quake", "💀"), ("hexen", "🧙"), ("duke nukem", "💥"),
        ("rogue squadron", "✈️"), ("episode i - racer", "🏁"), ("star wars", "🚀"),
        ("starcraft", "👾"), ("resident evil", "🧟"), ("castlevania", "🧛"),
        ("body harvest", "🛸"), ("blast corps", "🚜"), ("jet force gemini", "🐜"),
        ("glover", "🧤"), ("gex", "🦎"), ("chameleon twist", "🦎"),
        ("tetrisphere", "🧩"), ("tetris", "🧩"), ("wetrix", "💧"), ("bust-a-move", "🫧"),
        ("wipeout", "🛸"), ("toy story", "🧸"), ("indiana jones", "🤠"), ("xena", "⚔️"),
        ("harvest moon", "🌾"), ("ogre battle", "🛡️"), ("mischief makers", "🤖"), ("rayman", "🖐️"),
        ("bomberman", "💣"), ("mystical ninja", "🥷"), ("goemon", "🥷"),
        ("space station silicon valley", "🐑"), ("rocket", "🚀"),
        ("beetle adventure", "🚗"), ("cruis'n", "🚗"), ("carmageddon", "🚗"), ("rush", "🏎️"),
        ("ridge racer", "🏎️"), ("top gear", "🏎️"), ("f1 ", "🏎️"), ("formula", "🏎️"), ("nascar", "🏎️"),
        ("extreme-g", "🏍️"), ("excitebike", "🏍️"), ("hydro thunder", "🚤"),
        ("fifa", "⚽"), ("soccer", "⚽"), ("football", "⚽"), ("nba", "🏀"), ("basketball", "🏀"),
        ("nfl", "🏈"), ("madden", "🏈"), ("nhl", "🏒"), ("hockey", "🏒"), ("tony hawk", "🛹"),
        ("golf", "⛳"), ("tennis", "🎾"), ("wwf", "🤼"), ("wcw", "🤼"), ("wrestl", "🤼"), ("boxing", "🥊"),
        ("mortal kombat", "🐉"), ("killer instinct", "🥋"), ("fighters destiny", "🥋"),
        ("superman", "🦸"), ("batman", "🦇"), ("spider-man", "🕷️"), ("south park", "🧒"),
        ("earthworm jim", "🪱"), ("worms", "🪱"), ("army men", "🪖"), ("command & conquer", "🪖"),
        ("rainbow six", "🎯"), ("shadow man", "💀"), ("shadowman", "💀"), ("armorines", "🐛"),
        ("mega man", "🤖"), ("rockman", "🤖"), ("pac-man", "👻"), ("chess", "♟️"),
        ("sin and punishment", "🔫"), ("rampage", "🏙️"), ("harrier", "✈️"), ("aero", "✈️"),
    ]
}
