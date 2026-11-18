import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppearanceMode.current.apply()
        }
    }

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

        Settings {
            SettingsView(model: model, updater: updater)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                AppMenuCommands()
            }
            CommandGroup(replacing: .help) {
                Button("Revoir le tutoriel") { model.showOnboarding = true }
                Divider()
                Link("Summer Drop sur GitHub", destination: URL(string: "https://github.com/Titelive/summer-drop")!)
            }
        }

        Window("À propos de Summer Drop", id: "about") {
            AboutView(updater: updater)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
