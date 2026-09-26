import SwiftUI

// push and pop must stay balanced, and the panel can close with the pointer
// still inside (a jump does), so the pop is mirrored on disappear.
private struct PointerCursor: ViewModifier {
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != inside else { return }
                inside = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                guard inside else { return }
                inside = false
                NSCursor.pop()
            }
    }
}

extension View {
    func pointerCursor() -> some View { modifier(PointerCursor()) }
}
