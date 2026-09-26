import AppKit
import UserNotifications

@MainActor
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private static let jumpActionID = "HERDR_JUMP"
    private static let categoryID = "HERDR_AGENT"
    nonisolated private static let paneIDKey = "pane_id"

    private var isAuthorized = false

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([Self.agentCategory()])
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.error("notification auth failed: \(error.localizedDescription)")
            }
            Log.debug("notification authorization granted=\(granted)")
            Task { @MainActor [weak self] in self?.isAuthorized = granted }
        }
    }

    // UNUserNotificationCenter refuses ad-hoc signed apps (the normal local build),
    // so fall back to the same tools Herdr itself uses.
    func notify(title: String, body: String, paneID: String, sound: Bool) {
        if isAuthorized {
            postUserNotification(title: title, body: body, paneID: paneID, sound: sound)
        } else if !postViaTerminalNotifier(title: title, body: body, paneID: paneID, sound: sound) {
            Log.debug("falling back to AppleScript notification")
            postViaAppleScript(title: title, body: body)
        }
    }

    private static func agentCategory() -> UNNotificationCategory {
        let jump = UNNotificationAction(
            identifier: jumpActionID,
            title: "Jump to pane",
            options: [.foreground])
        return UNNotificationCategory(identifier: categoryID, actions: [jump],
                                      intentIdentifiers: [], options: [])
    }

    private func postUserNotification(title: String, body: String, paneID: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [Self.paneIDKey: paneID]
        if sound { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: "herdr-\(paneID)-\(UUID().uuidString)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func postViaTerminalNotifier(
        title: String, body: String, paneID: String, sound: Bool
    ) -> Bool {
        guard let tool = Executables.locate("terminal-notifier") else { return false }

        var arguments = ["-title", title, "-message", body.isEmpty ? " " : body]
        if let command = Self.jumpShellCommand(paneID: paneID) {
            arguments += ["-execute", command]
        }
        if sound { arguments += ["-sound", "default"] }

        do {
            try Self.launch(tool, arguments: arguments)
            Log.debug("posted via terminal-notifier")
            return true
        } catch {
            Log.debug("terminal-notifier failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func jumpShellCommand(paneID: String) -> String? {
        guard let herdr = Executables.locate("herdr") else { return nil }
        var command = "\(herdr) agent focus \(paneID)"
        if let bundleID = TerminalActivator.hostTerminalBundleID() {
            command += "; /usr/bin/open -b \(bundleID)"
        }
        return command
    }

    // Cannot carry a click action, but still gets the message across.
    private func postViaAppleScript(title: String, body: String) {
        try? Self.launch("/usr/bin/osascript", arguments: [
            "-e", "on run argv",
            "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
            "-e", "end run",
            title, body,
        ])
    }

    private static func launch(_ executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try process.run()
    }

    // Present even while the app is frontmost; it has no windows of its own.
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
        let paneID = response.notification.request.content.userInfo[Self.paneIDKey] as? String
        Task { @MainActor in
            if let paneID { PaneNavigator.jump(to: paneID) }
            completionHandler()
        }
    }
}
