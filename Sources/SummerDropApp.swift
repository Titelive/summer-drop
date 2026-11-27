import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Before the first window appears: no flash of the wrong theme.
            AppearanceMode.current.apply()
            // The delegate must be set before launch ends to receive a click that launched the app.
            Notifier.shared.setup()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppearanceTransition.shared.start()
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
    @AppStorage(AppLanguage.storageKey) private var languageSetting = AppLanguage.systemValue

    var body: some Scene {
        Window("Summer Drop", id: "main") {
            ContentView(model: model, updater: updater)
                .frame(minWidth: 1000, minHeight: 640)
                .task {
                    Notifier.shared.revealDownloads = { model.revealDownloads() }
                    model.start()
                    updater.startAutomaticChecks()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        // No opaque title bar: the summer gradient runs up to the top edge, behind the window buttons.
        // The header already shows the app's name.
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView(model: model, updater: updater)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                AppMenuCommands(language: languageSetting)
            }
            CommandGroup(replacing: .help) {
                Button(L("Show the Tutorial Again")) { model.showOnboarding = true }
                Divider()
                Link(L("Summer Drop on GitHub"), destination: URL(string: "https://github.com/Titelive/summer-drop")!)
            }
        }

        Window(L("About Summer Drop"), id: "about") {
            AboutView(updater: updater)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
