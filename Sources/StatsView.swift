import Foundation
import SwiftUI

/// Statistiques locales (rien ne quitte le Mac).
struct TransferStats: Codable, Equatable {
    var uploads = 0
    var downloads = 0
    var failures = 0
    var bytesUp: Int64 = 0
    var bytesDown: Int64 = 0
    var secondsUp: Double = 0
    var secondsDown: Double = 0
    var lastTransfer: Date?
    var since = Date()

    static let storageKey = "transferStats"

    static func load() -> TransferStats {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stats = try? JSONDecoder().decode(TransferStats.self, from: data) else {
            return TransferStats()
        }
        return stats
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    var averageUpSpeed: Double? { secondsUp > 0.5 ? Double(bytesUp) / secondsUp : nil }
    var averageDownSpeed: Double? { secondsDown > 0.5 ? Double(bytesDown) / secondsDown : nil }
}

struct StatsView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L("Statistiques", "Statistics"), systemImage: "chart.bar.xaxis")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(L("depuis le \(model.stats.since.formatted(date: .abbreviated, time: .omitted))", "since \(model.stats.since.formatted(date: .abbreviated, time: .omitted))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatTile(title: L("ROM envoyées", "ROMs sent"), value: "\(model.stats.uploads)", systemImage: "arrow.up.circle.fill", color: .orange)
                    StatTile(title: L("Fichiers récupérés", "Files retrieved"), value: "\(model.stats.downloads)", systemImage: "arrow.down.circle.fill", color: .blue)
                }
                GridRow {
                    StatTile(title: L("Données envoyées", "Data sent"), value: Self.bytes(model.stats.bytesUp), systemImage: "externaldrive.fill.badge.plus", color: .pink)
                    StatTile(title: L("Données récupérées", "Data retrieved"), value: Self.bytes(model.stats.bytesDown), systemImage: "internaldrive.fill", color: .purple)
                }
                GridRow {
                    StatTile(title: L("Vitesse moy. d'envoi", "Avg. upload speed"), value: Self.speed(model.stats.averageUpSpeed), systemImage: "speedometer", color: .yellow)
                    StatTile(title: L("Vitesse moy. de récupération", "Avg. retrieval speed"), value: Self.speed(model.stats.averageDownSpeed), systemImage: "gauge.with.dots.needle.67percent", color: .teal)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Dossier affiché : \(model.currentPathDisplay)", "Current folder: \(model.currentPathDisplay)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.isConnected && model.listError == nil {
                    HStack(spacing: 20) {
                        small(L("ROM", "ROMs"), "\(model.entries.filter { $0.isROM }.count)")
                        small(L("Dossiers", "Folders"), "\(model.entries.filter { $0.isDirectory }.count)")
                        small(L("Autres fichiers", "Other files"), "\(model.entries.filter { !$0.isDirectory && !$0.isROM }.count)")
                        small(L("Taille (approx.)", "Size (approx.)"), Self.bytes(model.entries.reduce(0) { $0 + $1.approxBytes }))
                    }
                } else {
                    Text(L("Branchez la cartouche pour voir son contenu.", "Plug in the cartridge to see its contents."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if model.stats.failures > 0 {
                    Text(L("\(model.stats.failures) transfert(s) en échec", "\(model.stats.failures) failed transfer(s)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let last = model.stats.lastTransfer {
                    Text(L("Dernier transfert : \(last.formatted(date: .abbreviated, time: .shortened))", "Last transfer: \(last.formatted(date: .abbreviated, time: .shortened))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func small(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func speed(_ value: Double?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) + "/s"
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
