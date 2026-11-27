import AppKit
import Foundation
import Observation
import UserNotifications

/// Kinds of notification, each with its own switch in Settings.
enum NotificationKind: String, CaseIterable, Identifiable, Sendable {
    /// A batch of transfers finished (with or without errors).
    case transfers
    /// The SummerCart64 was plugged in or unplugged.
    case cartridge
    /// A new version was downloaded and is ready to install.
    case update

    var id: String { rawValue }

    var defaultsKey: String { "notify.\(rawValue)" }

    var label: String {
        switch self {
        case .transfers: return L("Transfers finished")
        case .cartridge: return L("Cartridge plugged in or unplugged")
        case .update: return L("Update ready to install")
        }
    }

    var detail: String {
        switch self {
        case .transfers: return L("Once per batch, only when Summer Drop is in the background.")
        case .cartridge: return L("Only when Summer Drop is in the background, at most once a minute.")
        case .update: return L("Once per new version.")
        }
    }

    var systemImage: String {
        switch self {
        case .transfers: return "arrow.up.arrow.down.circle"
        case .cartridge: return "sdcard"
        case .update: return "arrow.down.app"
        }
    }

    /// On unless turned off (or unless the old single switch was turned off).
    var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if let value = defaults.object(forKey: defaultsKey) as? Bool { return value }
        return defaults.object(forKey: Notifier.legacyEnabledKey) as? Bool ?? true
    }

    /// Focus filters what each level may do: `.passive` never lights up the screen nor plays a sound,
    /// `.active` is the standard banner and stays silenced by Focus unless the user allows Summer Drop.
    var interruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .transfers: return .active
        case .cartridge, .update: return .passive
        }
    }

    /// Minimum delay between two notifications of this kind.
    var cooldown: TimeInterval {
        switch self {
        case .cartridge: return 60
        case .transfers, .update: return 0
        }
    }
}

/// Where a click on a notification takes the user. The main window observes it.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Destination: Equatable {
        case transfers
        case cartridge
        case updateSettings
    }

    /// Set by a notification click, consumed by the main window.
    var pending: Destination?
    /// Tab shown when the Settings window opens.
    var settingsTab: SettingsTab = .general
    /// Incremented to make the transfer list flash briefly.
    var highlightTransfers = 0
}

enum SettingsTab: Hashable {
    case general, notifications, cartridge, updates, credits
}

/// macOS notifications: finished transfers, cartridge plugged in or unplugged, update ready.
///
/// Permission is not asked at launch: it is asked the first time the user starts a transfer
/// (the moment a "transfers finished" notification starts to make sense), or when they turn
/// a switch on in Settings.
@MainActor
@Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    /// The single switch of earlier versions, still read as the default of each kind.
    nonisolated static let legacyEnabledKey = "notificationsEnabled"
    private static let lastUpdateVersionKey = "notify.update.lastVersion"

    private enum Category {
        static let transfers = "transfers"
        static let transfersWithDownloads = "transfers.downloads"
        static let cartridge = "cartridge"
        static let update = "update"
    }

    private enum Action {
        static let revealDownloads = "revealDownloads"
        static let installUpdate = "installUpdate"
    }

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private var lastPosted: [NotificationKind: Date] = [:]

    /// Called by the app at launch. Never shows the permission prompt.
    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories()
        Task { await refreshAuthorization() }
        // The user may change the permission in System Settings while the app runs.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await Notifier.shared.refreshAuthorization() }
        }
    }

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
    }

    /// Shows the system prompt if it was never shown and at least one kind is on.
    func requestAuthorizationIfNeeded() {
        guard NotificationKind.allCases.contains(where: \.isEnabled) else { return }
        Task {
            await refreshAuthorization()
            guard authorization == .notDetermined else { return }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        }
    }

    /// System Settings › Notifications › Summer Drop.
    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Posting

    func notifyTransfers(title: String, body: String, failed: Bool, hasDownloads: Bool) {
        post(.transfers, title: title, body: body,
             category: hasDownloads ? Category.transfersWithDownloads : Category.transfers,
             relevance: failed ? 1 : 0.6)
    }

    func notifyCartridge(title: String, body: String) {
        post(.cartridge, title: title, body: body, category: Category.cartridge, sound: false, relevance: 0.3)
    }

    /// Posted once per version, even if the app downloads it again after a restart.
    func notifyUpdate(version: String, title: String, body: String) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.lastUpdateVersionKey) != version else { return }
        if post(.update, title: title, body: body, category: Category.update, relevance: 0.8, allowWhenActive: true) {
            defaults.set(version, forKey: Self.lastUpdateVersionKey)
        }
    }

    /// Returns whether the notification was handed to the system.
    @discardableResult
    private func post(
        _ kind: NotificationKind,
        title: String,
        body: String,
        category: String,
        sound: Bool = true,
        relevance: Double,
        allowWhenActive: Bool = false
    ) -> Bool {
        guard kind.isEnabled, authorization == .authorized || authorization == .provisional else { return false }
        // The window already shows what happened: no banner while the user is looking at it.
        guard allowWhenActive || !NSApp.isActive else { return false }
        if let last = lastPosted[kind], Date().timeIntervalSince(last) < kind.cooldown { return false }
        lastPosted[kind] = Date()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.threadIdentifier = kind.rawValue
        content.interruptionLevel = kind.interruptionLevel
        content.relevanceScore = relevance
        content.userInfo = ["kind": kind.rawValue]
        if sound && kind.interruptionLevel != .passive { content.sound = .default }
        // One identifier per kind: a new notification replaces the previous one instead of piling up.
        let request = UNNotificationRequest(identifier: kind.rawValue, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
        return true
    }

    private func registerCategories() {
        let reveal = UNNotificationAction(identifier: Action.revealDownloads, title: L("Show in Finder"), options: [.foreground])
        let install = UNNotificationAction(identifier: Action.installUpdate, title: L("Restart and Install"), options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Category.transfers, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.transfersWithDownloads, actions: [reveal], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.cartridge, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.update, actions: [install], intentIdentifiers: []),
        ])
    }

    // MARK: - Delegate

    /// Hooks the app gives the notifier for the notification buttons.
    var revealDownloads: (() -> Void)?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Only the update notification is posted while the app is in front: keep it in the list, no banner.
        completionHandler([.list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let kind = (response.notification.request.content.userInfo["kind"] as? String).flatMap(NotificationKind.init(rawValue:))
        let action = response.actionIdentifier
        Task { @MainActor in
            self.handle(kind: kind, action: action)
            completionHandler()
        }
    }

    private func handle(kind: NotificationKind?, action: String) {
        if action == UNNotificationDismissActionIdentifier { return }
        NSApp.activate()
        let router = AppRouter.shared
        switch action {
        case Action.revealDownloads:
            revealDownloads?()
            router.pending = .transfers
        case Action.installUpdate:
            Updater.shared.installAndRelaunch()
        default:
            switch kind {
            case .transfers, nil: router.pending = .transfers
            case .cartridge: router.pending = .cartridge
            case .update: router.pending = .updateSettings
            }
        }
    }
}
