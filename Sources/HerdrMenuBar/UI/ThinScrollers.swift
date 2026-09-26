import SwiftUI

// SwiftUI has no API for scroller width, and "Show scroll bars: Always" gives
// the wide legacy scroller, so this styles the enclosing NSScrollView directly.
struct ThinScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = enclosingScrollView(of: view) else { return }
            applyThinOverlayScroller(to: scrollView)
        }
    }

    private func enclosingScrollView(of view: NSView) -> NSScrollView? {
        var parent = view.superview
        while let current = parent, !(current is NSScrollView) {
            parent = current.superview
        }
        return parent as? NSScrollView
    }

    // `.scrollIndicators(.never)` stops SwiftUI reserving a scroller gutter but
    // also hides the scroller, so an overlay one is put back by hand.
    private func applyThinOverlayScroller(to scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        if !(scrollView.verticalScroller is ThinScroller) {
            let scroller = ThinScroller()
            scroller.scrollerStyle = .overlay
            scrollView.verticalScroller = scroller
        }
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller?.isHidden = false
        scrollView.verticalScroller?.alphaValue = 1
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

// Scroller width is a class method, so narrowing it needs a subclass.
private final class ThinScroller: NSScroller {
    override class func scrollerWidth(for controlSize: NSControl.ControlSize,
                                      scrollerStyle: NSScroller.Style) -> CGFloat {
        8
    }
}
