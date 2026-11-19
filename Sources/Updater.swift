import AppKit
import Foundation
import Observation

/// Mises à jour automatiques via les « Releases » GitHub du dépôt indiqué
/// dans Info.plist (clé SummerDropGitHubRepo). L'app télécharge l'image disque
/// de la dernière version, prépare la nouvelle app, puis la remplace au
/// redémarrage (ou à la fermeture de l'app).
@MainActor
@Observable
final class Updater {
    enum Phase: Equatable {
        case idle
        case checking
        case downloading(String)
        case ready(String)
        case upToDate
        case failed(String)
    }

    static let shared = Updater()
    nonisolated static let autoCheckKey = "autoUpdateChecks"

    nonisolated static var automaticChecksEnabled: Bool {
        UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true
    }

    var phase: Phase = .idle

    let currentVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private let repo: String? =
        Bundle.main.object(forInfoDictionaryKey: "SummerDropGitHubRepo") as? String

    private var stagedAppURL: URL?
    private var installOnQuit = false
    private var loopTask: Task<Void, Never>?

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    private struct UpdateError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// Vérifie au lancement, puis toutes les 6 heures.
    func startAutomaticChecks() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            while !Task.isCancelled {
                if Updater.automaticChecksEnabled {
                    await self?.checkForUpdates(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func checkForUpdates(userInitiated: Bool) async {
        switch phase {
        case .checking, .downloading, .ready:
            return
        default:
            break
        }
        guard let repo, !repo.isEmpty else {
            if userInitiated { phase = .failed("Aucun dépôt GitHub n'est configuré.") }
            return
        }

        phase = .checking
        do {
            guard let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
                throw UpdateError("Adresse du dépôt invalide.")
            }
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("SummerDrop/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError("Aucune version publiée sur GitHub.")
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = Self.cleanVersion(release.tag_name)

            guard Self.isNewer(latest, than: currentVersion) else {
                phase = userInitiated ? .upToDate : .idle
                return
            }
            guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
                throw UpdateError("La version \(latest) n'a pas d'image disque.")
            }
            let target = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw UpdateError("Le dossier de l'app est protégé en écriture : mise à jour impossible.")
            }

            phase = .downloading(latest)
            let (downloaded, _) = try await URLSession.shared.download(from: asset.browser_download_url)
            let staged = try await Task.detached(priority: .utility) {
                try Updater.prepareApp(fromDMG: downloaded)
            }.value

            stagedAppURL = staged
            installOnQuit = true
            phase = .ready(latest)
            Notifier.shared.post(title: "Mise à jour prête", body: "Summer Drop \(latest) est prête : redémarrez l'app pour l'installer.")
        } catch {
            phase = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    /// Remplace l'app et la relance.
    func installAndRelaunch() {
        install(relaunch: true)
        NSApp.terminate(nil)
    }

    /// Appelé à la fermeture : installe la mise à jour prête sans relancer.
    func installIfPendingOnQuit() {
        if installOnQuit { install(relaunch: false) }
    }

    func dismiss() {
        switch phase {
        case .upToDate, .failed: phase = .idle
        default: break
        }
    }

    private func install(relaunch: Bool) {
        guard let staged = stagedAppURL else { return }
        installOnQuit = false
        stagedAppURL = nil

        let target = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let relaunchLine = relaunch ? "/usr/bin/open \"$2\"" : ""
        // Attend la fermeture de l'app, remplace le paquet, puis relance.
        let script = """
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$2" && /usr/bin/ditto "$1" "$2" && /usr/bin/xattr -cr "$2"
        \(relaunchLine)
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", staged.path, target.path]
        try? process.run()
    }

    // MARK: - Outils (hors du thread principal)

    nonisolated static func prepareApp(fromDMG dmg: URL) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("SummerDropUpdate-\(UUID().uuidString)")
        let mountPoint = work.appendingPathComponent("volume")
        try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let image = work.appendingPathComponent("update.dmg")
        try fm.moveItem(at: dmg, to: image)

        try run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        let items = try fm.contentsOfDirectory(atPath: mountPoint.path)
        guard let appName = items.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError("L'image disque ne contient pas d'app.")
        }
        let staged = work.appendingPathComponent(appName)
        try run("/usr/bin/ditto", [mountPoint.appendingPathComponent(appName).path, staged.path])
        _ = try? run("/usr/bin/xattr", ["-cr", staged.path])

        // Vérification minimale : c'est bien la même app.
        let newID = Bundle(url: staged)?.bundleIdentifier
        guard newID != nil, newID == Bundle.main.bundleIdentifier else {
            throw UpdateError("L'app téléchargée ne correspond pas à Summer Drop.")
        }
        return staged
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw UpdateError("Échec de \((path as NSString).lastPathComponent).")
        }
    }

    nonisolated static func cleanVersion(_ tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        return value
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
