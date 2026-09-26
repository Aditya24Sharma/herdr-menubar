import AppKit

// MenuBarExtra exposes no open/closed binding, so this backs up an inert `dismiss`.
// Match by class AND visibility: the other window is the status item, and closing it removes the icon.
@MainActor
enum MenuPanel {
    private static let panelClassMarker = "MenuBarExtra"

    static func close() {
        guard let panel = NSApp.windows.first(where: isMenuBarExtraPanel),
              panel.isVisible
        else { return }

        Log.debug("closing the panel as a fallback")
        panel.close()
    }

    private static func isMenuBarExtraPanel(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains(panelClassMarker)
    }
}
