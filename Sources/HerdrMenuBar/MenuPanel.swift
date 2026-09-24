import AppKit

/// Closing the dropdown from code.
///
/// `MenuBarExtra` exposes no binding for whether its panel is open, so this is
/// a backstop for `@Environment(\.dismiss)` on systems where that is inert.
///
/// It matches the panel by class and checks that it is visible. Both matter:
/// the app's other window is the status item itself, and closing that removes
/// the icon from the menu bar for the rest of the process's life.
@MainActor
enum MenuPanel {
    static func close() {
        guard let panel = NSApp.windows.first(where: {
            String(describing: type(of: $0)).contains("MenuBarExtra")
        }), panel.isVisible else { return }

        Log.debug("closing the panel as a fallback")
        panel.close()
    }
}
