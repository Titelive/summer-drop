import AppKit
import Foundation
import Observation

enum ConnectionState: Equatable {
    case searching
    case connected(DeviceInfo)
    case disconnected
    case missingTool
}

/// Un élément du dossier affiché côté Mac.
struct MacEntry: Identifiable, Equatable {
    let url: URL
    let entry: SDEntry
    var id: URL { url }
}

enum Pane: Equatable {
    case mac
    case card
}

/// Presse-papiers interne de l'app (⌘C / ⌘V entre les deux panneaux).
enum AppClipboard: Equatable {
    case empty
    case macFiles([URL])
    case cardFiles([SDEntry], folder: String)
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
    /// ⌘X : supprimer l'original une fois la copie réussie (corbeille côté Mac, effacement côté carte).
    var moveSource = false
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
    var searchText = ""
    /// Vrai quand on écrit dans la recherche : ⌘A/⌘C/⌘V gardent alors leur rôle habituel.
    var isEditingText = false

    // Panneau Mac
    var macEntries: [MacEntry] = []
    var macSelection: Set<URL> = []
    var activePane: Pane = .card
    var clipboard: AppClipboard = .empty
    var clipboardIsCut = false
    /// Demande de confirmation avant un déplacement (⌘X puis ⌘V).
    var pendingMove = false

    /// Tri et regroupement de chaque panneau (gardés entre les lancements).
    var cardSort = SortOptions.load("sort.card") { didSet { cardSort.save("sort.card") } }
    var macSort = SortOptions.load("sort.mac") { didSet { macSort.save("sort.mac") } }

    /// Entrées de la carte, triées et groupées.
    var cardSections: [ListSection<SDEntry>] {
        ListArranger.arrange(visibleEntries, options: cardSort) { $0 }
    }

    /// Entrées du Mac, triées et groupées.
    var macSections: [ListSection<MacEntry>] {
        ListArranger.arrange(visibleMacEntries, options: macSort) { $0.entry }
    }

    /// Entrées affichées, filtrées par la recherche.
    var visibleEntries: [SDEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedStandardContains(query) }
    }
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

        let wasDisconnected = connection == .disconnected
        if result.succeeded, let first = devices.first {
            connection = .connected(first)
            if wasDisconnected {
                Notifier.shared.post(title: L("SummerCart64 connected"), body: L("Cartridge {0} is ready.", "\(first.serial)"), sound: false)
            }
            if !wasConnected {
                currentPath = "/"
                await refreshList()
            }
        } else {
            connection = .disconnected
            if wasConnected {
                Notifier.shared.post(title: L("SummerCart64 unplugged"), body: L("The cartridge is no longer detected."), sound: false)
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
            banner = L("This file is not executable. Run “chmod +x” on it in Terminal.")
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
        searchText = ""
        Task { await refreshList() }
    }

    func goUp() {
        guard currentPath != "/", !isLoadingList else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent.isEmpty ? "/" : parent
        selection = []
        searchText = ""
        Task { await refreshList() }
    }

    static func join(_ folder: String, _ name: String) -> String {
        folder == "/" ? "/" + name : folder + "/" + name
    }

    // MARK: - Envoi

    func enqueue(_ urls: [URL], move: Bool = false) {
        let fm = FileManager.default
        var added = 0
        for url in Self.expandFolders(urls, fileManager: fm) {
            let attributes = try? fm.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let destination = Self.join(currentPath, url.lastPathComponent)
            queue.append(UploadItem(kind: .upload, source: url.path, destination: destination, size: size, moveSource: move))
            added += 1
        }
        if added == 0 {
            banner = L("No ROM found (.z64, .n64, .v64, .ndd).")
            return
        }
        startQueueIfNeeded()
    }

    static let romExtensions: Set<String> = ["z64", "n64", "v64", "ndd"]

    /// Fichiers : gardés tels quels. Dossiers : on y prend toutes les ROM, sous-dossiers compris,
    /// et elles arrivent ensemble dans le dossier de destination de la carte.
    private static func expandFolders(_ urls: [URL], fileManager fm: FileManager) -> [URL] {
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                files.append(url)
                continue
            }
            guard let walker = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            var found: [URL] = []
            for case let file as URL in walker
            where romExtensions.contains(file.pathExtension.lowercased()) {
                found.append(file)
            }
            files += found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        return files
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
        let files = visibleEntries.filter { !$0.isDirectory }
        return !files.isEmpty && files.allSatisfy { selection.contains($0.name) }
    }

    func toggleSelectAll() {
        if allFilesSelected {
            selection = []
        } else {
            selection = Set(visibleEntries.filter { !$0.isDirectory }.map(\.name))
        }
    }

    func setDownloadFolder(_ folder: URL) {
        let changed = UserDefaults.standard.string(forKey: Self.lastDownloadFolderKey) != folder.path
        UserDefaults.standard.set(folder.path, forKey: Self.lastDownloadFolderKey)
        downloadFolderVersion += 1
        if changed {
            macSelection = []
            refreshMac()
        }
    }

    // MARK: - Panneau Mac

    /// Liste le dossier Mac affiché : sous-dossiers et ROM.
    func refreshMac() {
        guard let folder = suggestedDownloadFolder else {
            macEntries = []
            return
        }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isPackageKey]
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let entries: [MacEntry] = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            if !isDirectory && !Self.romExtensions.contains(url.pathExtension.lowercased()) { return nil }
            let size = Int64(values?.fileSize ?? 0)
            let sizeText = isDirectory ? "" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            let date = values?.contentModificationDate.map { formatter.string(from: $0) } ?? ""
            let entry = SDEntry(name: url.lastPathComponent, isDirectory: isDirectory, sizeText: sizeText, date: date, approxBytes: size)
            return MacEntry(url: url, entry: entry)
        }
        macEntries = entries.sorted { lhs, rhs in
            if lhs.entry.isDirectory != rhs.entry.isDirectory { return lhs.entry.isDirectory }
            return lhs.entry.name.localizedStandardCompare(rhs.entry.name) == .orderedAscending
        }
        macSelection = macSelection.filter { url in macEntries.contains { $0.url == url } }
    }

    var visibleMacEntries: [MacEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return macEntries }
        return macEntries.filter { $0.entry.name.localizedStandardContains(query) }
    }

    func openMac(_ item: MacEntry) {
        guard item.entry.isDirectory else { return }
        setDownloadFolder(item.url)
    }

    func macGoUp() {
        guard let folder = suggestedDownloadFolder else { return }
        let parent = folder.deletingLastPathComponent()
        guard parent.path != folder.path else { return }
        setDownloadFolder(parent)
    }

    func toggleMacSelection(_ item: MacEntry) {
        guard !item.entry.isDirectory else { return }
        if macSelection.contains(item.url) { macSelection.remove(item.url) } else { macSelection.insert(item.url) }
    }

    var selectedMacFiles: [URL] {
        macEntries.filter { !$0.entry.isDirectory && macSelection.contains($0.url) }.map(\.url)
    }

    var allMacFilesSelected: Bool {
        let files = macEntries.filter { !$0.entry.isDirectory }
        return !files.isEmpty && files.allSatisfy { macSelection.contains($0.url) }
    }

    func toggleSelectAllMac() {
        if allMacFilesSelected {
            macSelection = []
        } else {
            macSelection = Set(macEntries.filter { !$0.entry.isDirectory }.map(\.url))
        }
    }

    func sendSelectedMacFiles() {
        let files = selectedMacFiles
        guard !files.isEmpty else { return }
        macSelection = []
        enqueue(files)
    }

    // MARK: - Raccourcis du panneau actif (⌘A, ⌘C, ⌘V)

    func selectAllInActivePane() {
        switch activePane {
        case .mac: toggleSelectAllMac()
        case .card: toggleSelectAll()
        }
    }

    /// Supprime l'original après un déplacement réussi.
    private func removeSource(of item: UploadItem, tool: URL) async {
        switch item.kind {
        case .upload:
            // Côté Mac : à la corbeille, donc récupérable.
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: item.source), resultingItemURL: nil)
            } catch {
                banner = L("Copied, but “{0}” could not be moved to the Trash.", "\(item.name)")
            }
        case .download:
            let result = await Deployer.run(tool, ["sd", "rm", item.source])
            if !result.succeeded || Deployer.consoleWasOn(result.output) {
                banner = L("Copied to the Mac, but “{0}” could not be deleted from the card.", "\(item.name)")
            }
        }
    }

    func cutFromActivePane() {
        copyFromActivePane()
        guard clipboard != .empty else { return }
        // The SC64 menu must stay on the card: it can be copied, never moved off.
        if case .cardFiles(let files, _) = clipboard, files.contains(where: \.isSystemFile) {
            clipboardIsCut = false
            banner = L("The SC64 menu can't be moved off the card. Uncheck sc64menu.n64, or copy it with ⌘C.")
            return
        }
        clipboardIsCut = true
        let count: Int
        switch clipboard {
        case .macFiles(let files): count = files.count
        case .cardFiles(let files, _): count = files.count
        case .empty: count = 0
        }
        banner = L("{0} ROM{1} to move: click the other pane, then ⌘V.", "\(count)", "\(count > 1 ? "s" : "")")
    }

    /// Texte de la confirmation de déplacement.
    var pendingMoveDescription: String {
        switch clipboard {
        case .macFiles(let files):
            return L("{0} ROM{1} will be copied to the card, then moved to the Mac's Trash.", "\(files.count)", "\(files.count > 1 ? "s" : "")")
        case .cardFiles(let files, _):
            return L("{0} ROM{1} will be copied to the Mac, then deleted from the SD card. This deletion is permanent.", "\(files.count)", "\(files.count > 1 ? "s" : "")")
        case .empty:
            return ""
        }
    }

    func copyFromActivePane() {
        clipboardIsCut = false
        switch activePane {
        case .mac:
            let files = selectedMacFiles
            guard !files.isEmpty else { banner = L("First check some ROMs in the Mac pane."); return }
            clipboard = .macFiles(files)
            // Aussi dans le presse-papiers du Mac : on peut coller dans le Finder.
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(files.map { $0 as NSURL })
            banner = L("{0} ROM{1} copied: click the card, then ⌘V.", "\(files.count)", "\(files.count > 1 ? "s" : "")")
        case .card:
            let files = selectedFiles
            guard !files.isEmpty else { banner = L("First check some ROMs on the card."); return }
            clipboard = .cardFiles(files, folder: currentPath)
            banner = L("{0} ROM{1} copied: click the Mac pane, then ⌘V.", "\(files.count)", "\(files.count > 1 ? "s" : "")")
        }
    }

    func pasteIntoActivePane() {
        if clipboardIsCut && clipboard != .empty {
            // Le déplacement attend une confirmation explicite.
            let fromMacToCard: Bool
            if case .macFiles = clipboard { fromMacToCard = true } else { fromMacToCard = false }
            guard (fromMacToCard && activePane == .card) || (!fromMacToCard && activePane == .mac) else {
                banner = L("Click the other pane first, then ⌘V.")
                return
            }
            pendingMove = true
            return
        }
        paste(move: false)
    }

    func confirmMove() {
        pendingMove = false
        paste(move: true)
        clipboard = .empty
        clipboardIsCut = false
    }

    private func paste(move: Bool) {
        switch activePane {
        case .card:
            var urls: [URL] = []
            if case .macFiles(let files) = clipboard { urls = files }
            if urls.isEmpty {
                // Fichiers copiés dans le Finder.
                urls = NSPasteboard.general.readObjects(
                    forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]
                ) as? [URL] ?? []
            }
            guard !urls.isEmpty else { banner = L("Nothing to paste: copy ROMs from the Mac first (⌘C)."); return }
            guard isConnected else { banner = L("Plug in the SummerCart64 first."); return }
            enqueue(urls, move: move)
        case .mac:
            guard case .cardFiles(let files, let folder) = clipboard else {
                banner = L("Nothing to paste: copy ROMs from the card first (⌘C).")
                return
            }
            guard let destination = suggestedDownloadFolder else { return }
            download(files, to: destination, from: folder, move: move)
        }
    }

    /// Nom lisible : « iCloud Drive › Documents › Jeux › Nintendo 64 ».
    var downloadFolderDisplayName: String {
        _ = downloadFolderVersion
        guard let path = suggestedDownloadFolder?.path else { return L("No folder") }
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

    func download(_ files: [SDEntry], to folder: URL, from sdFolder: String? = nil, move: Bool = false) {
        let fm = FileManager.default
        setDownloadFolder(folder)
        let origin = sdFolder ?? currentPath
        var reserved = Set<String>()
        for entry in files where !entry.isDirectory {
            let source = Self.join(origin, entry.name)
            let target = Self.uniqueURL(for: entry.name, in: folder, reserved: reserved, fileManager: fm)
            reserved.insert(target.path)
            queue.append(UploadItem(kind: .download, source: source, destination: target.path, size: entry.approxBytes, moveSource: move))
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

    private func notifyBatch(sent: Int, received: Int, failed: Int) {
        guard sent + received + failed > 0 else { return }
        var parts: [String] = []
        if sent > 0 { parts.append(L("{0} ROM{1} sent to the card", "\(sent)", "\(sent > 1 ? "s" : "")")) }
        if received > 0 { parts.append(L("{0} file{1} retrieved to the Mac", "\(received)", "\(received > 1 ? "s" : "")")) }
        if failed > 0 { parts.append(L("{0} failure{1}", "\(failed)", "\(failed > 1 ? "s" : "")")) }
        Notifier.shared.post(
            title: failed > 0 ? L("Transfers finished with errors") : L("Transfers finished"),
            body: parts.joined(separator: ", ") + "."
        )
    }

    /// « Carte SD › racine », « Carte SD › saves »…
    static func sdDisplayPath(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        return ([L("SD card")] + (parts.isEmpty ? [L("root")] : parts)).joined(separator: " › ")
    }

    var currentPathDisplay: String { Self.sdDisplayPath(currentPath) }

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
        var sent = 0, received = 0, failed = 0

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
                if item.kind == .upload { sent += 1 } else { received += 1 }
                if item.moveSource {
                    await removeSource(of: item, tool: tool)
                }
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
                failed += 1
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
        notifyBatch(sent: sent, received: received, failed: failed)
        refreshMac()
        await refreshList()
    }
}
