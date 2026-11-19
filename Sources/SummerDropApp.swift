import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppearanceMode.current.apply()
            Notifier.shared.setup()
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
                .frame(minWidth: 1000, minHeight: 640)
                .task {
                    model.start()
                    updater.startAutomaticChecks()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(model: model, updater: updater)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                AppMenuCommands()
            }
            CommandGroup(replacing: .help) {
                Button(L("Revoir le tutoriel", "Show the Tutorial Again")) { model.showOnboarding = true }
                Divider()
                Link(L("Summer Drop sur GitHub", "Summer Drop on GitHub"), destination: URL(string: "https://github.com/Titelive/summer-drop")!)
            }
        }

        Window(L("À propos de Summer Drop", "About Summer Drop"), id: "about") {
            AboutView(updater: updater)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
