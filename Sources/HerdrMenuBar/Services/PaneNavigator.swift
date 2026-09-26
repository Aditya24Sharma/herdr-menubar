enum PaneNavigator {
    static func jump(to paneID: String) {
        do {
            try HerdrClient().focus(paneID: paneID)
        } catch {
            Log.error("pane.focus failed: \(error.localizedDescription)")
        }
        TerminalActivator.activateHostTerminal()
    }
}
