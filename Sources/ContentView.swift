import SwiftUI
import UniformTypeIdentifiers

// MARK: - Fenêtre principale

struct ContentView: View {
    let model: AppModel
    let updater: Updater
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppLanguage.storageKey) private var languageSetting = AppLanguage.systemValue

    var body: some View {
        ZStack {
            SummerBackground()

            VStack(spacing: 16) {
                HeaderBar(model: model, updater: updater)

                if model.connection == .missingTool {
                    MissingToolView(model: model)
                } else {
                    // Deux panneaux : le Mac à gauche, la carte à droite. On glisse de l'un à l'autre.
                    HStack(alignment: .top, spacing: 16) {
                        MacPanelView(model: model)
                        SDCardView(model: model)
                    }
                    UploadQueueView(model: model)
                        .frame(height: model.queue.isEmpty ? 96 : 170)
                        .animation(.spring(duration: 0.4), value: model.queue.isEmpty)
                }

                HStack {
                    Spacer()
                    CreatorBar()
                }
            }
            .padding(20)
            // Rebuilt when the language changes, so every label is translated at once.
            .id(languageSetting)

            if let message = model.banner {
                BannerView(message: message) { model.banner = nil }
            }
        }
        .background(shortcuts)
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.25), value: model.banner)
        .animation(reduceMotion ? nil : .spring(duration: 0.5), value: model.connection)
        .confirmationDialog(
            L("Move these ROMs?"),
            isPresented: Binding(get: { model.pendingMove }, set: { model.pendingMove = $0 }),
            titleVisibility: .visible
        ) {
            Button(L("Move"), role: .destructive) { model.confirmMove() }
            Button(L("Cancel"), role: .cancel) { model.pendingMove = false }
        } message: {
            Text(model.pendingMoveDescription)
        }
        .sheet(isPresented: Binding(
            get: { model.showOnboarding },
            set: { model.showOnboarding = $0 }
        )) {
            OnboardingView(model: model)
        }
    }
}

extension ContentView {
    /// ⌘A, ⌘C, ⌘V agissent sur le panneau actif (sauf pendant la saisie d'une recherche).
    @ViewBuilder
    var shortcuts: some View {
        let editing = model.isEditingText
        ZStack {
            Button("") { model.selectAllInActivePane() }
                .keyboardShortcut(editing ? nil : KeyboardShortcut("a", modifiers: .command))
            Button("") { model.copyFromActivePane() }
                .keyboardShortcut(editing ? nil : KeyboardShortcut("c", modifiers: .command))
            Button("") { model.pasteIntoActivePane() }
                .keyboardShortcut(editing ? nil : KeyboardShortcut("v", modifiers: .command))
            Button("") { model.cutFromActivePane() }
                .keyboardShortcut(editing ? nil : KeyboardShortcut("x", modifiers: .command))
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Bords adoucis des listes

extension View {
    /// Fond progressif en haut et en bas d'une liste qui défile : plus de ligne coupée net.
    func softEdges(_ size: CGFloat = 14) -> some View {
        mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: size)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: size)
            }
        )
    }
}

// MARK: - Fond

struct SummerBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    private var colors: [Color] {
        if colorScheme == .dark {
            // Nuit d'été : crépuscule violet et bleu profond.
            return [
                Color(red: 0.36, green: 0.16, blue: 0.32),
                Color(red: 0.20, green: 0.13, blue: 0.36),
                Color(red: 0.06, green: 0.08, blue: 0.22),
            ]
        }
        return [
            Color(red: 1.00, green: 0.62, blue: 0.30),
            Color(red: 0.96, green: 0.36, blue: 0.52),
            Color(red: 0.45, green: 0.32, blue: 0.85),
        ]
    }

    var body: some View {
        // Le dégradé dérive lentement, comme une lumière d'été qui bouge.
        LinearGradient(
            colors: colors,
            startPoint: drift ? .top : .topLeading,
            endPoint: drift ? .bottomTrailing : .bottom
        )
        .overlay(
            RadialGradient(
                colors: [Color.yellow.opacity(colorScheme == .dark ? 0.12 : 0.45), .clear],
                center: drift ? UnitPoint(x: 0.85, y: 0.05) : .topTrailing,
                startRadius: 10,
                endRadius: drift ? 600 : 500
            )
        )
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

// MARK: - En-tête et état de la cartouche

/// Soleil qui tourne doucement et « respire ».
struct AnimatedSun: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var glow = false

    var body: some View {
        Image(systemName: "sun.max.fill")
            .font(.title2)
            .foregroundStyle(.yellow)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .scaleEffect(glow ? 1.08 : 0.94)
            .shadow(color: .yellow.opacity(glow ? 0.9 : 0.3), radius: glow ? 10 : 3)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                    spin = true
                }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    glow = true
                }
            }
    }
}

struct HeaderBar: View {
    let model: AppModel
    let updater: Updater
    @State private var showStats = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    AnimatedSun()
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Summer Drop")
                            .font(.title2.weight(.bold))
                        Text(L("Send and retrieve ROMs · SummerCart64"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)

                Spacer()

                UpdatePill(updater: updater, isUploading: model.isUploading)

                Button {
                    showStats.toggle()
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title3)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .help(L("Statistics"))
                .popover(isPresented: $showStats, arrowEdge: .bottom) {
                    StatsView(model: model)
                }

                ConnectionPill(state: model.connection)
            }
            .animation(.spring(duration: 0.45), value: updater.phase)
        }
    }
}

/// Point d'état : il pulse pendant la recherche et « respire » une fois connecté.
struct StatusDot: View {
    let color: Color
    let isSearching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(pulse ? 0 : 0.7), lineWidth: 2)
                .scaleEffect(pulse ? 2.2 : 1)
            Circle()
                .fill(color)
                .shadow(color: color.opacity(0.8), radius: pulse ? 6 : 3)
        }
        .frame(width: 10, height: 10)
        .onAppear(perform: start)
        .onChange(of: isSearching) { _, _ in
            pulse = false
            start()
        }
    }

    private func start() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: isSearching ? 0.9 : 2.4).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

struct ConnectionPill: View {
    let state: ConnectionState

    private var label: String {
        switch state {
        case .searching: return L("Looking for the cartridge…")
        case .connected(let device): return L("SummerCart64 connected · {0}", "\(device.serial)")
        case .disconnected: return L("Cartridge not connected")
        case .missingTool: return L("sc64deployer not found")
        }
    }

    private var color: Color {
        switch state {
        case .searching: return .orange
        case .connected: return .green
        case .disconnected: return .red
        case .missingTool: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: color, isSearching: state == .searching)
            Text(label)
                .contentTransition(.opacity)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(Glass.regular.tint(color.opacity(0.25)), in: .capsule)
        .help(helpText)
        .animation(.easeInOut, value: state)
    }

    private var helpText: String {
        if case .connected(let device) = state { return L("Port: {0}", "\(device.port)") }
        return L("Detection runs every 3 seconds.")
    }
}

// MARK: - Mises à jour

struct UpdatePill: View {
    let updater: Updater
    let isUploading: Bool

    var body: some View {
        switch updater.phase {
        case .idle, .checking:
            EmptyView()
        case .downloading(let version):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Downloading version {0}…", "\(version)"))
                    .font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
        case .ready(let version):
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text(L("Version {0} ready", "\(version)"))
                    .font(.callout.weight(.medium))
                Button(L("Restart")) { updater.installAndRelaunch() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .disabled(isUploading)
                    .help(isUploading ? L("Wait for transfers to finish.") : L("Installs the update and relaunches the app."))
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .glassEffect(Glass.regular.tint(Color.yellow.opacity(0.25)), in: .capsule)
        case .upToDate:
            dismissable(text: L("Summer Drop {0} is up to date", "\(updater.currentVersion)"), systemImage: "checkmark.seal.fill", color: .green)
        case .failed(let message):
            dismissable(text: message, systemImage: "exclamationmark.triangle.fill", color: .red)
        }
    }

    private func dismissable(text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(text)
                .font(.callout)
                .lineLimit(1)
            Button {
                updater.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Zone de dépôt

struct DropZone: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dashPhase: CGFloat = 0
    @State private var isTargeted = false
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 12) {
            // En-tête, symétrique de « Récupérer sur le Mac ».
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer.and.arrow.down")
                    .foregroundStyle(.orange)
                Text(L("Send to the cartridge"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "laptopcomputer")
                    Image(systemName: "arrow.right")
                    Image(systemName: "sdcard")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(L("From the Mac to the SummerCart64's SD card"))
            }

            Spacer(minLength: 0)

            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down.on.square")
                .font(.system(size: 44, weight: .light))
                .symbolEffect(.bounce, value: isTargeted)
            Text(isTargeted ? L("Drop to send") : L("Drop your ROMs here"))
                .font(.title3.weight(.semibold))
                .contentTransition(.interpolate)
            Button {
                showImporter = true
            } label: {
                Label(L("Choose ROMs or a folder…"), systemImage: "folder")
            }
            .buttonStyle(.glassProminent)
            .disabled(!model.isConnected)

            Spacer(minLength: 0)

            // Destination lisible sur la carte.
            HStack(spacing: 8) {
                Image(systemName: "sdcard.fill")
                    .foregroundStyle(.orange)
                Text(L("Destination:"))
                    .foregroundStyle(.secondary)
                Text(model.currentPathDisplay)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .help(L("Open a folder in the right-hand list to change the destination."))
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(20)
        .glassEffect(
            isTargeted ? Glass.regular.tint(Color.yellow.opacity(0.35)).interactive() : Glass.regular.interactive(),
            in: .rect(cornerRadius: 28)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6], dashPhase: dashPhase))
                .foregroundStyle(.white.opacity(isTargeted ? 0.9 : 0.35))
                .padding(8)
        )
        .scaleEffect(isTargeted && !reduceMotion ? 1.02 : 1)
        .opacity(model.isConnected ? 1 : 0.6)
        .onAppear {
            guard !reduceMotion else { return }
            // Pointillés qui défilent doucement autour de la zone.
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                dashPhase = -28
            }
        }
        .animation(.spring(duration: 0.3), value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            guard model.isConnected else {
                model.banner = L("Plug in the SummerCart64 first.")
                return false
            }
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.enqueue([url]) }
                }
            }
            return true
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.enqueue(urls)
            }
        }
    }
}

// MARK: - File d'envoi

struct UploadQueueView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Transfers"))
                    .font(.headline)
                Spacer()
                if model.hasCompletedDownloads {
                    Button {
                        model.revealDownloads()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help(L("Show downloaded files in the Finder"))
                }
                if !model.queue.isEmpty && !model.isUploading {
                    Button(L("Clear")) { model.clearFinished() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }

            if model.queue.isEmpty {
                Text(L("No transfers yet."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if model.isUploading {
                    ProgressView(value: model.overallProgress) {
                        Text(L("Overall progress"))
                            .font(.caption)
                    } currentValueLabel: {
                        Text("\(Int(model.overallProgress * 100)) %")
                            .font(.caption.monospacedDigit())
                            .contentTransition(.numericText())
                            .animation(.snappy, value: Int(model.overallProgress * 100))
                    }
                    .tint(.yellow)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        // Le plus récent en haut : il reste toujours visible.
                        ForEach(model.queue.reversed()) { item in
                            UploadRow(item: item, fileProgress: model.currentFileProgress)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .scale(scale: 0.9).combined(with: .opacity)
                                ))
                        }
                    }
                    .animation(.spring(duration: 0.4), value: model.queue)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.automatic)
                .softEdges()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

struct UploadRow: View {
    let item: UploadItem
    let fileProgress: Double

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                switch item.state {
                case .waiting:
                    Text((item.kind == .upload ? L("Upload pending · {0}", "\(sizeText)") : L("Download pending · {0}", "\(sizeText)")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .uploading:
                    ProgressView(value: fileProgress)
                        .tint(.yellow)
                        .animation(.linear(duration: 0.12), value: fileProgress)
                case .done:
                    Text(item.kind == .upload
                         ? L("Sent to {0}", "\(AppModel.sdDisplayPath((item.destination as NSString).deletingLastPathComponent))")
                         : L("Downloaded to {0}", "\((item.destination as NSString).deletingLastPathComponent)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.state {
        case .waiting:
            Image(systemName: item.kind == .upload ? "arrow.up.circle" : "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .uploading:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Contenu de la carte SD

struct SDCardView: View {
    let model: AppModel
    @State private var showFolderPicker = false
    @State private var isTargeted = false
    @FocusState private var searchFocused: Bool

    private var isActive: Bool { model.activePane == .card }

    /// Fichiers du Finder ou ROM glissées depuis le panneau Mac : envoi sur la carte.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard model.isConnected else {
            model.banner = L("Plug in the SummerCart64 first.")
            return false
        }
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    if let text = object as? String, let paths = DragPayload.lines(text, prefix: DragPayload.mac) {
                        Task { @MainActor in
                            model.activePane = .card
                            model.macSelection = []
                            model.enqueue(paths.map { URL(fileURLWithPath: $0) })
                        }
                    } else {
                        loadFileURL(provider)
                    }
                }
            } else {
                loadFileURL(provider)
            }
        }
        return true
    }

    private func loadFileURL(_ provider: NSItemProvider) {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.isFileURL else { return }
            Task { @MainActor in
                model.activePane = .card
                model.enqueue([url])
            }
        }
    }

    /// Glisser une ROM de la carte vers le panneau Mac (toute la sélection si elle en fait partie).
    private func dragProvider(for entry: SDEntry) -> NSItemProvider {
        let selected = model.selectedFiles
        let files = selected.contains(entry) ? selected : [entry]
        let payload = DragPayload.card + ([model.currentPath] + files.map(\.name)).joined(separator: "\n")
        return NSItemProvider(object: payload as NSString)
    }

    /// Récupère directement dans le dossier de destination affiché en bas du panneau.
    private func retrieve(_ files: [SDEntry]) {
        guard !files.isEmpty, let folder = model.suggestedDownloadFolder else { return }
        model.download(files, to: folder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sdcard.fill")
                    .foregroundStyle(.orange)
                Text("SummerCart64")
                    .font(.headline)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                searchField
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            model.goUp()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.glass)
                        .disabled(model.currentPath == "/" || model.isLoadingList || model.isUploading)
                        .help(L("Parent folder"))

                        SortMenu(options: Binding(get: { model.cardSort }, set: { model.cardSort = $0 }))

                        Button {
                            Task { await model.refreshList() }
                        } label: {
                            // La roue de chargement remplace l'icône, à sa place exacte.
                            ZStack {
                                Image(systemName: "arrow.clockwise")
                                    .opacity(model.isLoadingList ? 0 : 1)
                                if model.isLoadingList {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.7)
                                }
                            }
                            .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.glass)
                        .disabled(!model.isConnected || model.isLoadingList || model.isUploading)
                        .help(L("Refresh"))
                    }
                }
            }

            HStack {
                Label(model.currentPathDisplay, systemImage: "folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(model.currentPath)
                Spacer()
                if model.isConnected && model.listError == nil && model.entries.contains(where: { !$0.isDirectory }) {
                    Button {
                        model.activePane = .card
                        model.toggleSelectAll()
                    } label: {
                        HStack(spacing: 6) {
                            Text(model.allFilesSelected ? L("Deselect All") : L("Select All"))
                            if isActive {
                                Text("⌘A")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.isConnected {
                retrieveBar
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    isTargeted ? Color.orange : Color.white.opacity(isActive ? 0.35 : 0),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: isTargeted ? [8, 6] : [])
                )
        )
        .animation(.spring(duration: 0.3), value: isTargeted)
        .animation(.easeOut(duration: 0.2), value: isActive)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { model.activePane = .card })
        .onDrop(of: [UTType.fileURL, UTType.utf8PlainText], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .onChange(of: searchFocused) { _, focused in
            model.isEditingText = focused
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let folder = urls.first {
                model.setDownloadFolder(folder)
            }
        }
        .fileDialogDefaultDirectory(model.suggestedDownloadFolder)
        .fileDialogConfirmationLabel(L("Choose This Folder"))
    }

    /// Champ de recherche (⌘K pour y aller, Échap pour effacer).
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("Search"), text: Binding(
                get: { model.searchText },
                set: { model.searchText = $0 }
            ))
            .textFieldStyle(.plain)
            .focused($searchFocused)
            .onExitCommand {
                model.searchText = ""
                searchFocused = false
            }
            if model.searchText.isEmpty {
                Text("⌘K")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            } else {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 220, height: 30)
        .glassEffect(Glass.regular.interactive(), in: .capsule)
        .disabled(!model.isConnected)
        .background(
            // Raccourci ⌘K : place le curseur dans la recherche.
            Button("") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        )
        .animation(.snappy, value: model.searchText.isEmpty)
    }

    /// Barre « De la carte vers le Mac », symétrique de la zone de dépôt.
    private var retrieveBar: some View {
        let count = model.selectedFiles.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer.and.arrow.down")
                    .foregroundStyle(.blue)
                Text(L("Retrieve to the Mac"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(count == 0
                     ? L("Check ROMs or drag them to the left")
                     : L("{0} file{1} selected", "\(count)", "\(count > 1 ? "s" : "")"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(model.downloadFolderDisplayName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(model.suggestedDownloadFolder?.path ?? "")
                Button(L("Change…")) { showFolderPicker = true }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                Spacer()
                Button {
                    retrieve(model.selectedFiles)
                } label: {
                    Label(count == 0 ? L("Retrieve") : L("Retrieve ({0})", "\(count)"), systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.glassProminent)
                .disabled(count == 0)
                .help(count == 0 ? L("Check some ROMs in the list first") : L("Copy the checked files to this Mac folder"))
            }
        }
        .padding(14)
        .glassEffect(Glass.regular.tint(Color.blue.opacity(count > 0 ? 0.18 : 0.06)), in: .rect(cornerRadius: 18))
        .animation(.spring(duration: 0.35), value: count)
    }

    @ViewBuilder
    private var content: some View {
        if !model.isConnected {
            placeholder(
                systemImage: "cable.connector",
                title: L("Plug in the SummerCart64"),
                detail: L("Connect the cartridge to the Mac over USB-C, with the console off.")
            )
        } else if model.isLoadingList && model.entries.isEmpty {
            ProgressView(L("Reading the card…"))
        } else if let error = model.listError {
            placeholder(systemImage: "exclamationmark.triangle", title: L("Can't read the card"), detail: error)
        } else if !model.entries.isEmpty && model.visibleEntries.isEmpty {
            placeholder(systemImage: "magnifyingglass", title: L("No results"), detail: L("No file in this folder contains “{0}”.", "\(model.searchText)"))
        } else if model.entries.isEmpty {
            placeholder(systemImage: "tray", title: L("Empty folder"), detail: L("Drag ROMs here from the Mac pane or the Finder."))
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.cardSections) { section in
                        if let title = section.title {
                            SectionHeader(title: title, count: section.items.count)
                        }
                        ForEach(section.items) { entry in
                        SDEntryRow(entry: entry, isSelected: model.selection.contains(entry.name))
                            .contentShape(Rectangle())
                            .transition(.opacity.combined(with: .offset(y: 8)))
                            .onTapGesture(count: 2) { model.open(entry) }
                            .onTapGesture(count: 1) {
                                model.activePane = .card
                                model.toggleSelection(entry)
                            }
                            .onDrag { dragProvider(for: entry) }
                            .contextMenu {
                                if entry.isDirectory {
                                    Button(L("Open")) { model.open(entry) }
                                } else {
                                    Button(L("Retrieve to the Mac")) {
                                        let selected = model.selectedFiles
                                        retrieve(selected.contains(entry) ? selected : [entry])
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .animation(.spring(duration: 0.4), value: model.cardSort)
            }
            .softEdges()
        }
    }

    private func placeholder(systemImage: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct SDEntryRow: View {
    let entry: SDEntry
    var isSelected = false
    @AppStorage("gameCardsEnabled") private var cardsEnabled = true
    @State private var showCard = false
    @State private var nameHovered = false
    @State private var cardHovered = false
    @State private var hoverTask: Task<Void, Never>?
    private let ratings = RatingStore.shared

    /// Survol du nom : la fiche apparaît après un court délai et reste ouverte
    /// tant que la souris est sur le nom ou sur la fiche.
    private func updateHover() {
        hoverTask?.cancel()
        let wanted = nameHovered || cardHovered
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(wanted ? 650 : 350))
            guard !Task.isCancelled else { return }
            showCard = (nameHovered || cardHovered) && cardsEnabled
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Case à cocher visible pour les fichiers (les dossiers s'ouvrent au double-clic).
            Group {
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 18)
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 22)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .underline(nameHovered && entry.isROM && cardsEnabled, color: .secondary)
                .onHover { inside in
                    guard entry.isROM else { return }
                    nameHovered = inside
                    updateHover()
                }
            if entry.isSystemFile {
                Text(L("SC64 menu"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.18), in: .capsule)
            }
            Spacer(minLength: 6)
            // Fixed slot for the stars: giving a rating never changes the name's width.
            if entry.isROM {
                StarRatingView(rating: ratings.rating(for: entry.name), size: 9)
                    .opacity(ratings.rating(for: entry.name) > 0 ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: ratings.rating(for: entry.name))
            }
            Text(entry.sizeText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(entry.date)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(isSelected ? 0.6 : 0), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: isSelected)
        // Anchored on the whole row, which never moves: the card stays put while you rate.
        .popover(isPresented: $showCard, arrowEdge: .leading) {
            GameCardView(entry: entry)
                .onHover { inside in
                    cardHovered = inside
                    updateHover()
                }
        }
        .help(entry.isDirectory ? L("Double-click to open")
              : entry.isSystemFile ? L("The SummerCart64 menu, not a game. Keep it at the root of the SD card.")
              : L("Click to check, then “Retrieve” below"))
    }

    private var iconName: String {
        if entry.isDirectory { return "folder.fill" }
        if entry.isSystemFile { return "memorychip.fill" }
        if entry.isROM { return "gamecontroller.fill" }
        return "doc"
    }

    private var iconColor: Color {
        if entry.isDirectory { return .blue }
        if entry.isSystemFile { return .purple }
        if entry.isROM { return .orange }
        return .secondary
    }
}

// MARK: - Outil introuvable

struct MissingToolView: View {
    let model: AppModel
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 44, weight: .light))
            Text(L("sc64deployer not found"))
                .font(.title2.weight(.semibold))
            Text(L("Put sc64deployer next to the app, or show where it is."))
                .foregroundStyle(.secondary)
            Button(L("Locate sc64deployer…")) { showPicker = true }
                .buttonStyle(.glassProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.useDeployer(at: url)
            }
        }
    }
}

// MARK: - Bandeau d'alerte

struct BannerView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 24)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
