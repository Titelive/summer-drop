import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            Updater.shared.installIfPendingOnQuit()
        }
    }
}

@main
struct SummerDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var updater = Updater.shared

    var body: some Scene {
        Window("Summer Drop", id: "main") {
            ContentView(model: model, updater: updater)
                .frame(minWidth: 880, minHeight: 580)
                .task {
                    model.start()
                    updater.startAutomaticChecks()
                }
        }
        .defaultSize(width: 1040, height: 680)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Rechercher des mises à jour…") {
                    Task { await Updater.shared.checkForUpdates(userInitiated: true) }
                }
            }
        }
    }
}
