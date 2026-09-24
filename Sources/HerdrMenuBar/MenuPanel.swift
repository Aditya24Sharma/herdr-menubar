import AppKit

/// Closing the dropdown from code.
///
/// `MenuBarExtra` exposes no binding for whether its panel is open, so there is
/// no supported way to close it from inside. The panel is an `NSPanel` that is
/// key while open, and closing it — rather than ordering it out — lets SwiftUI
/// see the dismissal, so the next click on the icon reopens it instead of
/// silently toggling a stale flag.
///
/// This app never shows a window of its own, so whatever is key or visible here
/// is the panel.
@MainActor
enum MenuPanel {
    static func close() {
        if let key = NSApp.keyWindow {
            key.close()
            return
        }
        for window in NSApp.windows where window.isVisible {
            window.close()
        }
    }
}
