import AppKit
import Foundation
import Observation

enum ConnectionState: Equatable {
    case searching
    case connected(DeviceInfo)
    case disconnected
    case missingTool
}

struct UploadItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case upload    // Mac -> carte SD
        case download  // carte SD -> Mac
    }

    enum State: Equatable {
        case waiting
        case uploading
        case done
        case failed(String)
    }

    let id = UUID()
    let kind: Kind
    /// Chemin local (envoi) ou chemin sur la carte SD (téléchargement).
    let source: String
    /// Chemin sur la carte SD (envoi) ou chemin local (téléchargement).
    let destination: String
    let size: Int64
    var state: State = .waiting

    var name: String { (source as NSString).lastPathComponent }
}

@MainActor
@Observable
final class AppModel {
    var connection: ConnectionState = .searching
    var deployerURL: URL?

    var entries: [SDEntry] = []
    var currentPath = "/"
    var isLoadingList = false
    var listError: String?

    var queue: [UploadItem] = []
    var selection: Set<String> = []
    /// Incrémenté quand le dossier de téléchargement change, pour rafraîchir l'affichage.
    var downloadFolderVersion = 0
    var isUploading = false
    var currentFileProgress: Double = 0

    var banner: String?
    var stats = TransferStats.load()
    var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingDone")

    private var commandRunning = false
    private var pollTask: Task<Void, Never>?
    private var bytesPerSecond: Double
    private var downloadBytesPerSecond: Double

    private static let speedKey = "measuredBytesPerSecond"
    private static let downloadSpeedKey = "measuredDownloadBytesPerSecond"
    static let lastDownloadFolderKey = "lastDownloadFolder"

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.speedKey)
        bytesPerSecond = saved > 0 ? saved : 1_500_000
        let savedDownload = UserDefaults.standard.double(forKey: Self.downloadSpeedKey)
        downloadBytesPerSecond = savedDownload > 0 ? savedDownload : 2_000_000
        deployerURL = Deployer.locate()
        if deployerURL == nil { connection = .missingTool }
    }

    // MARK: - Connexion

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshConnection()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func refreshConnection() async {
        guard let tool = deployerURL else {
            connection = .missingTool
            return
        }
        guard !commandRunning else { return }
        let result = await Deployer.run(tool, ["list"])
        let devices = Deployer.parseDevices(result.output)
        let wasConnected: Bool
        if case .connected = connection { wasConnected = true } else { wasConnected = false }

        if result.succeeded, let first = devices.first {
            connection = .connected(first)
            if !wasConnected {
                currentPath = "/"
                await refreshList()
            }
        } else {
            connection = .disconnected
            if wasConnected {
                entries = []
                listError = nil
            }
        }
    }

    func useDeployer(at url: URL) {
        UserDefaults.standard.set(url.path, forKey: Deployer.customPathKey)
        deployerURL = Deployer.locate()
        connection = deployerURL == nil ? .missingTool : .searching
        if deployerURL == nil {
            banner = "Ce fichier n'est pas exécutable. Lancez « chmod +x » dessus dans le Terminal."
        }
        Task { await refreshConnection() }
    }

    func resetDeployer() {
        UserDefaults.standard.removeObject(forKey: Deployer.customPathKey)
        deployerURL = Deployer.locate()
        connection = deployerURL == nil ? .missingTool : .searching
        Task { await refreshConnection() }
    }

    func resetStats() {
        stats = TransferStats()
        stats.save()
    }

    var isConnected: Bool {
        if case .connected = connection { return true }
        return false
    }

    // MARK: - Contenu de la carte SD

    func refreshList() async {
        guard let tool = deployerURL, !commandRunning else { return }
        commandRunning = true
        isLoadingList = true
        let result = await Deployer.run(tool, ["sd", "ls", currentPath])
        isLoadingList = false
        commandRunning = false

        selection = selection.filter { name in Deployer.parseEntries(result.output).contains { $0.name == name } }
        if result.succeeded && !Deployer.consoleWasOn(result.output) {
            listError = nil
            entries = Deployer.parseEntries(result.output)
                .filter { !$0.name.hasPrefix(".") }
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        } else {
            entries = []
            listError = Deployer.friendlyError(result.output)
        }
    }

    func open(_ entry: SDEntry) {
        guard entry.isDirectory, !isLoadingList else { return }
        currentPath = Self.join(currentPath, entry.name)
        selection = []
        Task { await refreshList() }
    }

    func goUp() {
        guard currentPath != "/", !isLoadingList else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent.isEmpty ? "/" : parent
        selection = []
        Task { await refreshList() }
    }

    static func join(_ folder: String, _ name: String) -> String {
        folder == "/" ? "/" + name : folder + "/" + name
    }

    // MARK: - Envoi

    func enqueue(_ urls: [URL]) {
        let fm = FileManager.default
        var added = 0
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            let attributes = try? fm.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let destination = Self.join(currentPath, url.lastPathComponent)
            queue.append(UploadItem(kind: .upload, source: url.path, destination: destination, size: size))
            added += 1
        }
        if added == 0 {
            banner = "Déposez des fichiers (les dossiers ne sont pas pris en charge)."
            return
        }
        startQueueIfNeeded()
    }

    private func startQueueIfNeeded() {
        if !isUploading {
            isUploading = true
            Task { await processQueue() }
        }
    }

    // MARK: - Téléchargement (carte SD -> Mac)

    func toggleSelection(_ entry: SDEntry) {
        guard !entry.isDirectory else { return }
        if selection.contains(entry.name) {
            selection.remove(entry.name)
        } else {
            selection.insert(entry.name)
        }
    }

    var allFilesSelected: Bool {
        let files = entries.filter { !$0.isDirectory }
        return !files.isEmpty && files.allSatisfy { selection.contains($0.name) }
    }

    func toggleSelectAll() {
        if allFilesSelected {
            selection = []
        } else {
            selection = Set(entries.filter { !$0.isDirectory }.map(\.name))
        }
    }

    func setDownloadFolder(_ folder: URL) {
        UserDefaults.standard.set(folder.path, forKey: Self.lastDownloadFolderKey)
        downloadFolderVersion += 1
    }

    /// Nom lisible : « iCloud Drive › Documents › Jeux › Nintendo 64 ».
    var downloadFolderDisplayName: String {
        _ = downloadFolderVersion
        guard let path = suggestedDownloadFolder?.path else { return "Aucun dossier" }
        let home = NSHomeDirectory()
        let icloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        var display = path
        if display.hasPrefix(icloud) {
            display = "iCloud Drive" + display.dropFirst(icloud.count)
        } else if display.hasPrefix(home) {
            display = "~" + display.dropFirst(home.count)
        }
        return display.split(separator: "/").joined(separator: " › ")
    }

    var selectedFiles: [SDEntry] {
        entries.filter { !$0.isDirectory && selection.contains($0.name) }
    }

    /// Dossier proposé par défaut : le dernier utilisé, sinon « Jeux/Nintendo 64 » sur iCloud.
    var suggestedDownloadFolder: URL? {
        _ = downloadFolderVersion
        let fm = FileManager.default
        if let last = UserDefaults.standard.string(forKey: Self.lastDownloadFolderKey),
           fm.fileExists(atPath: last) {
            return URL(fileURLWithPath: last)
        }
        let nintendo = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Documents/Jeux/Nintendo 64")
        if fm.fileExists(atPath: nintendo.path) { return nintendo }
        return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    func download(_ files: [SDEntry], to folder: URL) {
        let fm = FileManager.default
        setDownloadFolder(folder)
        var reserved = Set<String>()
        for entry in files where !entry.isDirectory {
            let source = Self.join(currentPath, entry.name)
            let target = Self.uniqueURL(for: entry.name, in: folder, reserved: reserved, fileManager: fm)
            reserved.insert(target.path)
            queue.append(UploadItem(kind: .download, source: source, destination: target.path, size: entry.approxBytes))
        }
        selection = []
        startQueueIfNeeded()
    }

    /// Évite d'écraser un fichier du Mac : « Mario.z64 » devient « Mario (2).z64 ».
    private static func uniqueURL(for name: String, in folder: URL, reserved: Set<String>, fileManager: FileManager) -> URL {
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) || reserved.contains(candidate.path) {
            let numbered = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    func revealDownloads() {
        let urls = queue
            .filter { $0.kind == .download && $0.state == .done }
            .map { URL(fileURLWithPath: $0.destination) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    var hasCompletedDownloads: Bool {
        queue.contains { $0.kind == .download && $0.state == .done }
    }

    func clearFinished() {
        queue.removeAll { item in
            switch item.state {
            case .done, .failed: return true
            default: return false
            }
        }
    }

    /// Progression globale de la file, pondérée par la taille des fichiers.
    var overallProgress: Double {
        let total = queue.reduce(0.0) { $0 + Double(max($1.size, 1)) }
        guard total > 0 else { return 0 }
        let done = queue.reduce(0.0) { sum, item in
            let size = Double(max(item.size, 1))
            switch item.state {
            case .done, .failed: return sum + size
            case .uploading: return sum + size * currentFileProgress
            case .waiting: return sum
            }
        }
        return min(done / total, 1)
    }

    private func processQueue() async {
        guard let tool = deployerURL else {
            isUploading = false
            return
        }
        // Attendre la fin d'une éventuelle lecture de la carte.
        while commandRunning {
            try? await Task.sleep(for: .milliseconds(200))
        }
        commandRunning = true

        while let index = queue.firstIndex(where: { $0.state == .waiting }) {
            let item = queue[index]
            queue[index].state = .uploading
            currentFileProgress = 0

            // sc64deployer n'affiche pas de pourcentage : on estime la progression
            // à partir de la taille du fichier et du débit mesuré lors des envois précédents.
            let start = Date()
            let speed = item.kind == .upload ? bytesPerSecond : downloadBytesPerSecond
            let expected = max(Double(item.size) / speed, 0.5)
            let ticker = Task { [weak self] in
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(start)
                    self?.currentFileProgress = min(elapsed / expected, 0.97)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }

            let arguments: [String]
            switch item.kind {
            case .upload: arguments = ["sd", "upload", item.source, item.destination]
            case .download: arguments = ["sd", "download", item.source, item.destination]
            }
            let result = await Deployer.run(tool, arguments)
            ticker.cancel()
            let elapsed = Date().timeIntervalSince(start)

            guard let current = queue.firstIndex(where: { $0.id == item.id }) else { continue }

            if result.succeeded && !Deployer.consoleWasOn(result.output) {
                currentFileProgress = 1
                queue[current].state = .done
                switch item.kind {
                case .upload:
                    stats.uploads += 1
                    stats.bytesUp += item.size
                    stats.secondsUp += elapsed
                case .download:
                    let attributes = try? FileManager.default.attributesOfItem(atPath: item.destination)
                    let realSize = (attributes?[.size] as? NSNumber)?.int64Value
                    stats.downloads += 1
                    stats.bytesDown += realSize ?? item.size
                    stats.secondsDown += elapsed
                }
                stats.lastTransfer = Date()
                stats.save()
                if item.size > 2_000_000, elapsed > 0.5 {
                    let measured = Double(item.size) / elapsed
                    switch item.kind {
                    case .upload:
                        bytesPerSecond = bytesPerSecond * 0.3 + measured * 0.7
                        UserDefaults.standard.set(bytesPerSecond, forKey: Self.speedKey)
                    case .download:
                        downloadBytesPerSecond = downloadBytesPerSecond * 0.3 + measured * 0.7
                        UserDefaults.standard.set(downloadBytesPerSecond, forKey: Self.downloadSpeedKey)
                    }
                }
            } else {
                let message = Deployer.friendlyError(result.output)
                queue[current].state = .failed(message)
                stats.failures += 1
                stats.save()
                if item.kind == .download {
                    // Ne pas laisser de fichier incomplet sur le Mac.
                    try? FileManager.default.removeItem(atPath: item.destination)
                }
                if Deployer.consoleWasOn(result.output) {
                    // Inutile d'insister : on arrête la file.
                    for i in queue.indices where queue[i].state == .waiting {
                        queue[i].state = .failed(message)
                    }
                    banner = message
                }
            }
        }

        currentFileProgress = 0
        commandRunning = false
        isUploading = false
        await refreshList()
    }
}
