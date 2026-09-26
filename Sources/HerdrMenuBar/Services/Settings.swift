import ServiceManagement
import SwiftUI

@MainActor
final class Settings: ObservableObject {
    @AppStorage("notifyOnBlocked") var notifyOnBlocked = true
    @AppStorage("notifyOnDone") var notifyOnDone = false
    @AppStorage("playSound") var playSound = false

    // Reads live SMAppService state so it stays correct when changed in System Settings.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            setLoginItemRegistered(newValue)
            objectWillChange.send()
        }
    }

    private func setLoginItemRegistered(_ registered: Bool) {
        do {
            if registered {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.error("login item change failed: \(error.localizedDescription)")
        }
    }
}
