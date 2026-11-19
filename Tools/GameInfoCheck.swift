import Foundation

// Vérification en CI : interroge les vraies sources pour quelques ROM.
@main
struct GameInfoCheck {
    static func main() async {
        let names = CommandLine.arguments.dropFirst()
        for name in names {
            let info = await GameInfoStore.build(romName: name)
            print("── \(name)")
            print("titre: \(info.title) | régions: \(info.regions) | langues: \(info.languages) | rév: \(info.revision ?? "-")")
            print("wiki: \(info.wikiTitle ?? "-") | année: \(info.year ?? "-")")
            print("dév: \(info.developers) | éditeur: \(info.publishers) | genres: \(info.genres)")
            print("résumé: \(info.summary?.prefix(120) ?? "-")")
            for url in [info.boxartURL, info.titleScreenURL, info.snapURL].compactMap({ $0 }) {
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                let status = ((try? await URLSession.shared.data(for: request))?.1 as? HTTPURLResponse)?.statusCode ?? -1
                print("\(status) \(url.lastPathComponent) [\(url.deletingLastPathComponent().lastPathComponent)]")
            }
        }
    }
}
