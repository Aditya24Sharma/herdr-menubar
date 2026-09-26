import SwiftUI

struct SettingsPanel: View {
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Notify when an agent needs me", isOn: $settings.notifyOnBlocked)
            Toggle("Notify when an agent finishes", isOn: $settings.notifyOnDone)
            Toggle("Play a sound", isOn: $settings.playSound)
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.launchAtLogin = $0 }))
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}
