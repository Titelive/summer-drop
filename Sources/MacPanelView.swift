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
                        .help(L("Parent folder"))

                        Button {
                            showFolderPicker = true
                        } label: {
                            Image(systemName: "folder.badge.gearshape")
                        }
                        .buttonStyle(.glass)
                        .help(L("Choose another Mac folder"))

                        SortMenu(options: Binding(get: { model.macSort }, set: { model.macSort = $0 }))

                        Button {
                            if let folder = model.suggestedDownloadFolder {
                                NSWorkspace.shared.activateFileViewerSelecting([folder])
                            }
                        } label: {
                            Image(systemName: "macwindow")
                        }
                        .buttonStyle(.glass)
                        .help(L("Show in Finder"))

                        Button {
                            model.refreshMac()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                        .help(L("Refresh"))
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
                            Text(model.allMacFilesSelected ? L("Deselect All") : L("Select All"))
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
        .fileDialogConfirmationLabel(L("Choose This Folder"))
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
            placeholder("questionmark.folder", L("No folder"), L("Choose a Mac folder."))
        } else if model.macEntries.isEmpty {
            placeholder("tray", L("No ROMs here"), L("Drag ROMs from the card here to retrieve them."))
        } else if model.visibleMacEntries.isEmpty {
            placeholder("magnifyingglass", L("No results"), L("Nothing matches “{0}”.", "\(model.searchText)"))
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.macSections) { section in
                        if let title = section.title {
                            SectionHeader(title: title, count: section.items.count)
                        }
                        ForEach(section.items) { item in
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
                                    Button(L("Open")) { model.openMac(item) }
                                } else {
                                    Button(L("Send to the cartridge")) {
                                        let selected = model.selectedMacFiles
                                        model.enqueue(selected.contains(item.url) ? selected : [item.url])
                                    }
                                    .disabled(!model.isConnected)
                                }
                                Button(L("Show in Finder")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .animation(.spring(duration: 0.4), value: model.macSort)
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
                Text(L("Send to the cartridge"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(count == 0
                     ? L("Check ROMs or drag them to the right")
                     : L("{0} ROM{1} selected", "\(count)", "\(count > 1 ? "s" : "")"))
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
                    Label(count == 0 ? L("Send") : L("Send ({0})", "\(count)"), systemImage: "arrow.up.to.line")
                }
                .buttonStyle(.glassProminent)
                .disabled(count == 0 || !model.isConnected)
                .help(model.isConnected ? L("Copy the checked ROMs to the card") : L("Plug in the SummerCart64 first"))
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
