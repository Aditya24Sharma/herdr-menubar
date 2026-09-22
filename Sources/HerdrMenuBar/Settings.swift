import Foundation
import ServiceManagement
import SwiftUI

/// User-facing toggles, persisted in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    @AppStorage("notifyOnBlocked") var notifyOnBlocked = true
    @AppStorage("notifyOnDone") var notifyOnDone = false
    @AppStorage("playSound") var playSound = false

    /// Reflects the real login-item state rather than a stored copy, so it stays
    /// correct if the user changes it in System Settings.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("herdr-menubar: login item change failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}
