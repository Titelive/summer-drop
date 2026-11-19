import Foundation

/// Résultat brut d'un appel à sc64deployer.
struct CommandResult: Sendable {
    let status: Int32
    let output: String
    var succeeded: Bool { status == 0 }
}

/// Une entrée de la carte SD de la SummerCart64.
struct SDEntry: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let isDirectory: Bool
    let sizeText: String
    let date: String
    /// Taille approximative en octets (sc64deployer n'affiche qu'une taille arrondie).
    var approxBytes: Int64 = 0

    var isROM: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["z64", "n64", "v64", "ndd"].contains(ext)
    }
}

/// Une cartouche détectée par `sc64deployer list`.
struct DeviceInfo: Sendable, Equatable {
    let serial: String
    let port: String
}

/// Enveloppe autour de l'outil en ligne de commande sc64deployer.
enum Deployer {
    static let customPathKey = "deployerPath"

    /// Cherche sc64deployer : chemin choisi par l'utilisateur, à côté de l'app,
    /// dans Contents/Resources, dans le dossier iCloud habituel, puis Homebrew.
    static func locate() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let custom = UserDefaults.standard.string(forKey: customPathKey), !custom.isEmpty {
            candidates.append(URL(fileURLWithPath: custom))
        }
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("sc64deployer"))
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("sc64deployer"))
        }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        candidates.append(home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Documents/Jeux/Analogue 3D/sc64deployer"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/sc64deployer"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/sc64deployer"))
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    /// Lance sc64deployer hors du thread principal et renvoie sa sortie (stdout + stderr).
    /// L'entrée standard est vide : si l'outil demande « Continue anyways? [y/N] »
    /// (console allumée), la réponse est « non » et l'accès est annulé proprement.
    static func run(_ executable: URL, _ arguments: [String]) async -> CommandResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<CommandResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = executable.deletingLastPathComponent()
                var environment = ProcessInfo.processInfo.environment
                environment["NO_COLOR"] = "1"
                environment["CLICOLOR"] = "0"
                process.environment = environment

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: CommandResult(status: -1, output: error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = stripANSI(String(decoding: data, as: UTF8.self))
                continuation.resume(returning: CommandResult(status: process.terminationStatus, output: text))
            }
        }
    }

    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }

    // MARK: - Analyse des sorties

    /// Lignes du type «  1: [SC64xxxx] at port [/dev/cu.usbserial-xxx] (using "ftdi" backend) ».
    static func parseDevices(_ output: String) -> [DeviceInfo] {
        var devices: [DeviceInfo] = []
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":"), Int(line[..<colon]) != nil else { continue }
            let parts = bracketed(line)
            guard parts.count >= 2 else { continue }
            devices.append(DeviceInfo(serial: parts[0], port: parts[1]))
        }
        return devices
    }

    private static func bracketed(_ text: String) -> [String] {
        var result: [String] = []
        var current: String?
        for character in text {
            if character == "[" {
                current = ""
            } else if character == "]" {
                if let value = current { result.append(value) }
                current = nil
            } else if current != nil {
                current?.append(character)
            }
        }
        return result
    }

    /// Lignes du type « f 8.0M 2024-05-01 12:00:00 | Mario.z64 » ou « d ---- 2024-05-01 12:00:00 | /menu ».
    static func parseEntries(_ output: String) -> [SDEntry] {
        var entries: [SDEntry] = []
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard let separator = line.range(of: " | ") else { continue }
            let meta = line[..<separator.lowerBound].split(separator: " ", omittingEmptySubsequences: true)
            guard meta.count >= 2, meta[0] == "d" || meta[0] == "f" else { continue }
            let isDirectory = meta[0] == "d"
            var name = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            if isDirectory, name.hasPrefix("/") { name.removeFirst() }
            if name.isEmpty { continue }
            let date = meta.count >= 4 ? "\(meta[2]) \(meta[3])" : ""
            let size = isDirectory ? "" : frenchSize(String(meta[1]))
            let bytes = isDirectory ? 0 : approximateBytes(String(meta[1]))
            entries.append(SDEntry(name: name, isDirectory: isDirectory, sizeText: size, date: date, approxBytes: bytes))
        }
        return entries
    }

    private static func approximateBytes(_ text: String) -> Int64 {
        guard let unit = text.last, let value = Double(text.dropLast()) else { return 0 }
        let multiplier: Double
        switch unit {
        case "K": multiplier = 1024
        case "M": multiplier = 1024 * 1024
        case "G": multiplier = 1024 * 1024 * 1024
        case "T": multiplier = 1024 * 1024 * 1024 * 1024
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }

    private static func frenchSize(_ text: String) -> String {
        guard let unit = text.last else { return text }
        let number = text.dropLast()
        switch unit {
        case "B": return L("{0} B", "\(number)")
        case "K": return L("{0} KB", "\(number)")
        case "M": return L("{0} MB", "\(number)")
        case "G": return L("{0} GB", "\(number)")
        case "T": return L("{0} TB", "\(number)")
        default: return text
        }
    }

    /// L'outil a refusé d'accéder à la carte parce que la console est allumée.
    static func consoleWasOn(_ output: String) -> Bool {
        output.contains("SD card access aborted") || output.contains("console is powered on")
    }

    /// Traduit les erreurs les plus courantes en français.
    static func friendlyError(_ output: String) -> String {
        if consoleWasOn(output) {
            return L("The console is on. Turn off the Analogue 3D before accessing the SD card.")
        }
        if output.contains("No SC64 devices found") {
            return L("SummerCart64 not found. Plug it in over USB-C.")
        }
        if output.contains("Couldn't init the SD card") {
            return L("The cartridge's SD card is missing or unreadable.")
        }
        if output.contains("Could not find the path") || output.contains("Could not find the file") {
            return L("Path not found on the SD card.")
        }
        let lines = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.last ?? L("Unknown sc64deployer error.")
    }
}
