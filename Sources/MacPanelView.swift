import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Préfixes des glisser-déposer internes entre les deux panneaux.
enum DragPayload {
    static let mac = "summerdrop-mac:"
    static let card = "summerdrop-sd:"

    static func lines(_ text: String, prefix: String) -> [String]? {
        guard text.hasPrefix(prefix) else { return nil }
        return text.dropFirst(prefix.count)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

/// Panneau de gauche : un dossier du Mac (par défaut Jeux › Nintendo 64).
struct MacPanelView: View {
    let model: AppModel
    @State private var showFolderPicker = false
    @State private var isTargeted = false

    private var isActive: Bool { model.activePane == .mac }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer")
                    .foregroundStyle(.blue)
                Text("Mac")
                    .font(.headline)
                Spacer(minLength: 8)
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            model.macGoUp()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.glass)
                        .help("Dossier parent")

                        Button {
                            showFolderPicker = true
                        } label: {
                            Image(systemName: "folder.badge.gearshape")
                        }
                        .buttonStyle(.glass)
                        .help("Choisir un autre dossier du Mac")

                        Button {
                            if let folder = model.suggestedDownloadFolder {
                                NSWorkspace.shared.activateFileViewerSelecting([folder])
                            }
                        } label: {
                            Image(systemName: "macwindow")
                        }
                        .buttonStyle(.glass)
                        .help("Afficher dans le Finder")

                        Button {
                            model.refreshMac()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                        .help("Actualiser")
                    }
                }
            }

            HStack {
                Label(model.downloadFolderDisplayName, systemImage: "folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(model.suggestedDownloadFolder?.path ?? "")
                Spacer()
                if model.macEntries.contains(where: { !$0.entry.isDirectory }) {
                    Button {
                        model.activePane = .mac
                        model.toggleSelectAllMac()
                    } label: {
                        HStack(spacing: 6) {
                            Text(model.allMacFilesSelected ? "Tout désélectionner" : "Tout sélectionner")
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

            list
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            sendBar
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    isTargeted ? Color.blue : Color.white.opacity(isActive ? 0.35 : 0),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: isTargeted ? [8, 6] : [])
                )
        )
        .animation(.spring(duration: 0.3), value: isTargeted)
        .animation(.easeOut(duration: 0.2), value: isActive)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { model.activePane = .mac })
        // Lignes de la carte glissées ici : récupération dans ce dossier.
        .onDrop(of: [UTType.utf8PlainText, UTType.plainText], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let folder = urls.first {
                model.setDownloadFolder(folder)
            }
        }
        .fileDialogDefaultDirectory(model.suggestedDownloadFolder)
        .fileDialogConfirmationLabel("Choisir ce dossier")
        .onAppear { model.refreshMac() }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String,
                  let names = DragPayload.lines(text, prefix: DragPayload.card) else { return }
            Task { @MainActor in
                // Première ligne : dossier d'origine sur la carte.
                guard let folder = names.first else { return }
                let wanted = Set(names.dropFirst())
                let files = model.entries.filter { wanted.contains($0.name) && !$0.isDirectory }
                guard !files.isEmpty, let destination = model.suggestedDownloadFolder else { return }
                model.activePane = .mac
                model.download(files, to: destination, from: folder)
            }
        }
        return true
    }

    @ViewBuilder
    private var list: some View {
        if model.suggestedDownloadFolder == nil {
            placeholder("questionmark.folder", "Aucun dossier", "Choisissez un dossier du Mac.")
        } else if model.macEntries.isEmpty {
            placeholder("tray", "Aucune ROM ici", "Glissez des ROM de la carte ici pour les récupérer.")
        } else if model.visibleMacEntries.isEmpty {
            placeholder("magnifyingglass", "Aucun résultat", "Rien ne correspond à « \(model.searchText) ».")
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.visibleMacEntries) { item in
                        SDEntryRow(entry: item.entry, isSelected: model.macSelection.contains(item.url))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.openMac(item) }
                            .onTapGesture(count: 1) {
                                model.activePane = .mac
                                model.toggleMacSelection(item)
                            }
                            .onDrag { dragProvider(for: item) }
                            .contextMenu {
                                if item.entry.isDirectory {
                                    Button("Ouvrir") { model.openMac(item) }
                                } else {
                                    Button("Envoyer sur la cartouche") {
                                        let selected = model.selectedMacFiles
                                        model.enqueue(selected.contains(item.url) ? selected : [item.url])
                                    }
                                    .disabled(!model.isConnected)
                                }
                                Button("Afficher dans le Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                }
                            }
                    }
                }
                .padding(.vertical, 6)
            }
            .softEdges()
        }
    }

    /// Glisser une ROM du Mac : vers la carte (toute la sélection) ou vers le Finder.
    private func dragProvider(for item: MacEntry) -> NSItemProvider {
        let selected = model.selectedMacFiles
        let urls = selected.contains(item.url) ? selected : [item.url]
        let provider = NSItemProvider(object: item.url as NSURL)
        let payload = DragPayload.mac + urls.map(\.path).joined(separator: "\n")
        provider.registerObject(payload as NSString, visibility: .ownProcess)
        return provider
    }

    private var sendBar: some View {
        let count = model.selectedMacFiles.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sdcard")
                    .foregroundStyle(.orange)
                Text("Envoyer sur la cartouche")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(count == 0
                     ? "Cochez des ROM ou glissez-les à droite"
                     : "\(count) ROM sélectionnée\(count > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Image(systemName: "sdcard.fill")
                    .foregroundStyle(.orange)
                Text(model.currentPathDisplay)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button {
                    model.sendSelectedMacFiles()
                } label: {
                    Label(count == 0 ? "Envoyer" : "Envoyer (\(count))", systemImage: "arrow.up.to.line")
                }
                .buttonStyle(.glassProminent)
                .disabled(count == 0 || !model.isConnected)
                .help(model.isConnected ? "Copier les ROM cochées sur la carte" : "Branchez d'abord la SummerCart64")
            }
        }
        .padding(14)
        .glassEffect(Glass.regular.tint(Color.orange.opacity(count > 0 ? 0.18 : 0.06)), in: .rect(cornerRadius: 18))
        .animation(.spring(duration: 0.35), value: count)
    }

    private func placeholder(_ systemImage: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
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
