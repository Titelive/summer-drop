import Foundation
import Observation

enum ConnectionState: Equatable {
    case searching
    case connected(DeviceInfo)
    case disconnected
    case missingTool
}

struct UploadItem: Identifiable, Equatable {
    enum State: Equatable {
        case waiting
        case uploading
        case done
        case failed(String)
    }

    let id = UUID()
    let url: URL
    let size: Int64
    let destination: String
    var state: State = .waiting

    var name: String { url.lastPathComponent }
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
    var isUploading = false
    var currentFileProgress: Double = 0

    var banner: String?

    private var commandRunning = false
    private var pollTask: Task<Void, Never>?
    private var bytesPerSecond: Double

    private static let speedKey = "measuredBytesPerSecond"

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.speedKey)
        bytesPerSecond = saved > 0 ? saved : 1_500_000
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
        Task { await refreshList() }
    }

    func goUp() {
        guard currentPath != "/", !isLoadingList else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent.isEmpty ? "/" : parent
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
            queue.append(UploadItem(url: url, size: size, destination: destination))
            added += 1
        }
        if added == 0 {
            banner = "Déposez des fichiers (les dossiers ne sont pas pris en charge)."
            return
        }
        if !isUploading {
            isUploading = true
            Task { await processQueue() }
        }
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
            let expected = max(Double(item.size) / bytesPerSecond, 0.5)
            let ticker = Task { [weak self] in
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(start)
                    self?.currentFileProgress = min(elapsed / expected, 0.97)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }

            let result = await Deployer.run(tool, ["sd", "upload", item.url.path, item.destination])
            ticker.cancel()
            let elapsed = Date().timeIntervalSince(start)

            guard let current = queue.firstIndex(where: { $0.id == item.id }) else { continue }

            if result.succeeded && !Deployer.consoleWasOn(result.output) {
                currentFileProgress = 1
                queue[current].state = .done
                if item.size > 2_000_000, elapsed > 0.5 {
                    let measured = Double(item.size) / elapsed
                    bytesPerSecond = bytesPerSecond * 0.3 + measured * 0.7
                    UserDefaults.standard.set(bytesPerSecond, forKey: Self.speedKey)
                }
            } else {
                let message = Deployer.friendlyError(result.output)
                queue[current].state = .failed(message)
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
