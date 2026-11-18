import SwiftUI
import UniformTypeIdentifiers

// MARK: - Fenêtre principale

struct ContentView: View {
    let model: AppModel
    let updater: Updater

    var body: some View {
        ZStack {
            SummerBackground()

            VStack(spacing: 16) {
                HeaderBar(model: model, updater: updater)

                if model.connection == .missingTool {
                    MissingToolView(model: model)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            DropZone(model: model)
                            UploadQueueView(model: model)
                        }
                        .frame(minWidth: 340, idealWidth: 400, maxWidth: 460)

                        SDCardView(model: model)
                    }
                }

                HStack {
                    Spacer()
                    CreatorBar()
                }
            }
            .padding(20)

            if let message = model.banner {
                BannerView(message: message) { model.banner = nil }
            }
        }
        .sheet(isPresented: Binding(
            get: { model.showOnboarding },
            set: { model.showOnboarding = $0 }
        )) {
            OnboardingView(model: model)
        }
    }
}

// MARK: - Fond

struct SummerBackground: View {
    @Environment(\.colorScheme) private var colorScheme

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
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [Color.yellow.opacity(colorScheme == .dark ? 0.12 : 0.45), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 520
            )
        )
        .ignoresSafeArea()
    }
}

// MARK: - En-tête et état de la cartouche

struct HeaderBar: View {
    let model: AppModel
    let updater: Updater
    @State private var showStats = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Summer Drop")
                            .font(.title2.weight(.bold))
                        Text("Envoi de ROM vers la SummerCart64")
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
                .help("Statistiques")
                .popover(isPresented: $showStats, arrowEdge: .bottom) {
                    StatsView(model: model)
                }

                ConnectionPill(state: model.connection)
            }
        }
    }
}

struct ConnectionPill: View {
    let state: ConnectionState

    private var label: String {
        switch state {
        case .searching: return "Recherche de la cartouche…"
        case .connected(let device): return "SummerCart64 connectée · \(device.serial)"
        case .disconnected: return "Cartouche non connectée"
        case .missingTool: return "sc64deployer introuvable"
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
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.8), radius: 4)
            Text(label)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(Glass.regular.tint(color.opacity(0.25)), in: .capsule)
        .help(helpText)
        .animation(.easeInOut, value: state)
    }

    private var helpText: String {
        if case .connected(let device) = state { return "Port : \(device.port)" }
        return "La détection se refait toutes les 3 secondes."
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
                Text("Téléchargement de la version \(version)…")
                    .font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
        case .ready(let version):
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text("Version \(version) prête")
                    .font(.callout.weight(.medium))
                Button("Redémarrer") { updater.installAndRelaunch() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .disabled(isUploading)
                    .help(isUploading ? "Attendez la fin des envois." : "Installe la mise à jour et relance l'app.")
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .glassEffect(Glass.regular.tint(Color.yellow.opacity(0.25)), in: .capsule)
        case .upToDate:
            dismissable(text: "Summer Drop \(updater.currentVersion) est à jour", systemImage: "checkmark.seal.fill", color: .green)
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
    @State private var isTargeted = false
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down.on.square")
                .font(.system(size: 46, weight: .light))
                .symbolEffect(.bounce, value: isTargeted)
            Text(isTargeted ? "Lâchez pour envoyer" : "Déposez vos ROM ici")
                .font(.title3.weight(.semibold))
            Text("Destination : \(model.currentPath)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                showImporter = true
            } label: {
                Label("Choisir des fichiers…", systemImage: "folder")
            }
            .buttonStyle(.glassProminent)
            .disabled(!model.isConnected)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(20)
        .glassEffect(
            isTargeted ? Glass.regular.tint(Color.yellow.opacity(0.35)).interactive() : Glass.regular.interactive(),
            in: .rect(cornerRadius: 28)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(.white.opacity(isTargeted ? 0.9 : 0.35))
                .padding(8)
        )
        .opacity(model.isConnected ? 1 : 0.6)
        .animation(.spring(duration: 0.3), value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            guard model.isConnected else {
                model.banner = "Branchez d'abord la SummerCart64."
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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
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
                Text("Transferts")
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
                    .help("Afficher les fichiers téléchargés dans le Finder")
                }
                if !model.queue.isEmpty && !model.isUploading {
                    Button("Effacer") { model.clearFinished() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }

            if model.queue.isEmpty {
                Text("Aucun transfert pour l'instant.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if model.isUploading {
                    ProgressView(value: model.overallProgress) {
                        Text("Progression totale")
                            .font(.caption)
                    } currentValueLabel: {
                        Text("\(Int(model.overallProgress * 100)) %")
                            .font(.caption.monospacedDigit())
                    }
                    .tint(.yellow)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.queue) { item in
                            UploadRow(item: item, fileProgress: model.currentFileProgress)
                        }
                    }
                }
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
                    Text("\(item.kind == .upload ? "Envoi" : "Téléchargement") en attente · \(sizeText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .uploading:
                    ProgressView(value: fileProgress)
                        .tint(.yellow)
                case .done:
                    Text(item.kind == .upload
                         ? "Envoyé vers \(item.destination)"
                         : "Téléchargé dans \((item.destination as NSString).deletingLastPathComponent)")
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
    @State private var pendingDownload: [SDEntry] = []

    private func askDownload(_ files: [SDEntry]) {
        guard !files.isEmpty else { return }
        pendingDownload = files
        showFolderPicker = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sdcard.fill")
                    .foregroundStyle(.orange)
                Text("Carte SD « SC64 »")
                    .font(.headline)
                Spacer()
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        if !model.selectedFiles.isEmpty {
                            Button {
                                askDownload(model.selectedFiles)
                            } label: {
                                Label("Télécharger (\(model.selectedFiles.count))", systemImage: "arrow.down.to.line")
                            }
                            .buttonStyle(.glassProminent)
                            .help("Copier les fichiers sélectionnés sur le Mac")
                        }

                        Button {
                            model.goUp()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.glass)
                        .disabled(model.currentPath == "/" || model.isLoadingList || model.isUploading)
                        .help("Dossier parent")

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
                        .help("Actualiser")
                    }
                }
            }

            HStack {
                Text(model.currentPath)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isConnected && model.listError == nil && !model.entries.isEmpty {
                    Text("Clic : sélectionner · double-clic : ouvrir un dossier")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let folder = urls.first {
                model.download(pendingDownload, to: folder)
            }
            pendingDownload = []
        }
        .fileDialogDefaultDirectory(model.suggestedDownloadFolder)
        .fileDialogConfirmationLabel("Télécharger ici")
    }

    @ViewBuilder
    private var content: some View {
        if !model.isConnected {
            placeholder(
                systemImage: "cable.connector",
                title: "Branchez la SummerCart64",
                detail: "Reliez la cartouche au Mac en USB-C, console éteinte."
            )
        } else if model.isLoadingList && model.entries.isEmpty {
            ProgressView("Lecture de la carte…")
        } else if let error = model.listError {
            placeholder(systemImage: "exclamationmark.triangle", title: "Lecture impossible", detail: error)
        } else if model.entries.isEmpty {
            placeholder(systemImage: "tray", title: "Dossier vide", detail: "Déposez des ROM à gauche pour les envoyer ici.")
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.entries) { entry in
                        SDEntryRow(entry: entry, isSelected: model.selection.contains(entry.name))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.open(entry) }
                            .onTapGesture(count: 1) { model.toggleSelection(entry) }
                            .contextMenu {
                                if entry.isDirectory {
                                    Button("Ouvrir") { model.open(entry) }
                                } else {
                                    Button("Télécharger sur le Mac…") {
                                        let selected = model.selectedFiles
                                        askDownload(selected.contains(entry) ? selected : [entry])
                                    }
                                }
                            }
                    }
                }
            }
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 22)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
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
        .help(entry.isDirectory ? "Double-cliquez pour ouvrir" : "Cliquez pour sélectionner, clic droit pour télécharger")
    }

    private var iconName: String {
        if entry.isDirectory { return "folder.fill" }
        if entry.isROM { return "gamecontroller.fill" }
        return "doc"
    }

    private var iconColor: Color {
        if entry.isDirectory { return .blue }
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
            Text("sc64deployer introuvable")
                .font(.title2.weight(.semibold))
            Text("Placez sc64deployer à côté de l'app, ou indiquez où il se trouve.")
                .foregroundStyle(.secondary)
            Button("Localiser sc64deployer…") { showPicker = true }
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
