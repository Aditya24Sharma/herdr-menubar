import SwiftUI

struct QuitButton: View {
    @State private var hovering = false

    private static let title = "Quit Herdr Menu Bar"

    var body: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Circle()
                .fill(Color(nsColor: .systemRed))
                .frame(width: 12, height: 12)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.black.opacity(hovering ? 0.55 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Self.title)
        // Otherwise VoiceOver reads the xmark glyph as "Close".
        .accessibilityLabel(Self.title)
        .pointerCursor()
    }
}
