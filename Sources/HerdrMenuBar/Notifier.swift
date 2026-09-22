import AppKit
import UserNotifications

/// Desktop notifications carrying a "Jump to pane" action.
///
/// Requires a real signed bundle; when authorization is unavailable the app
/// falls back to Herdr's own approach of an AppleScript notification, which
/// cannot carry an action button but still gets the message across.
@MainActor
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var isAuthorized = false

    private static let jumpAction = "HERDR_JUMP"
    private static let category = "HERDR_AGENT"

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let jump = UNNotificationAction(
            identifier: Self.jumpAction,
            title: "Jump to pane",
            options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [jump],
                                   intentIdentifiers: [], options: [])
        ])

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("herdr-menubar: notification auth failed: \(error.localizedDescription)")
            }
            Log.debug("notification authorization granted=\(granted)")
            Task { @MainActor [weak self] in self?.isAuthorized = granted }
        }
    }

    func notify(title: String, body: String, paneID: String, sound: Bool) {
        guard isAuthorized else {
            // UNUserNotificationCenter refuses ad-hoc signed apps, which is the
            // normal case for a locally built binary. Fall back to the same
            // tools Herdr itself uses.
            if notifyViaTerminalNotifier(title: title, body: body,
                                         paneID: paneID, sound: sound) { return }
            Log.debug("falling back to AppleScript notification")
            fallbackNotify(title: title, body: body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.category
        content.userInfo = ["pane_id": paneID]
        if sound { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: "herdr-\(paneID)-\(UUID().uuidString)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Posts through `terminal-notifier` when installed. Unlike the AppleScript
    /// route this keeps a working click action: it focuses the pane inside Herdr
    /// and raises the hosting terminal.
    private func notifyViaTerminalNotifier(
        title: String, body: String, paneID: String, sound: Bool
    ) -> Bool {
        guard let tool = Jumper.locate("terminal-notifier") else { return false }

        var arguments = ["-title", title, "-message", body.isEmpty ? " " : body]
        if let herdr = Jumper.locate("herdr") {
            var command = "\(herdr) agent focus \(paneID)"
            if let bundleID = Jumper.hostTerminalBundleID() {
                command += "; /usr/bin/open -b \(bundleID)"
            }
            arguments += ["-execute", command]
        }
        if sound { arguments += ["-sound", "default"] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        do {
            try process.run()
            Log.debug("posted via terminal-notifier")
            return true
        } catch {
            Log.debug("terminal-notifier failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Last resort: the same AppleScript call Herdr uses when nothing else is
    /// available. Shows a banner but cannot carry a click action.
    private func fallbackNotify(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "on run argv",
            "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
            "-e", "end run",
            title, body,
        ]
        try? process.run()
    }

    // Deliver even while the app is frontmost; it has no windows of its own.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let paneID = response.notification.request.content.userInfo["pane_id"] as? String
        Task { @MainActor in
            if let paneID { Jumper.jump(to: paneID) }
            completionHandler()
        }
    }
}
