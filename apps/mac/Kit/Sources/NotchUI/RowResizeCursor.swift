import SwiftUI

extension View {
    /// The up-down resize cursor over this view, owned by SwiftUI.
    ///
    /// `pointerStyle` makes the cursor part of what the hosting view resolves
    /// on its own cursor-update pass, which is what an `NSCursor.set()` in a
    /// hover callback is racing — and losing on the first hover, which is the
    /// one that matters.
    ///
    /// A no-op on macOS 14, which has no such API and keeps the old race.
    /// Deliberately not an `NSTrackingArea` overlay instead: an `NSView` laid
    /// over the handle takes the mouse-down with it, and a handle that cannot
    /// be dragged is a worse bug than a cursor that sometimes does not change.
    @ViewBuilder
    func rowResizeCursor() -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(.rowResize)
        } else {
            self
        }
    }
}

extension View {
    /// Keeps `offset` in step with how far this scroll view is scrolled.
    ///
    /// macOS 15 only, and the caller has to carry its own guess on 14: there is
    /// no way to observe a SwiftUI scroll view's offset before it, and the
    /// `GeometryReader`-in-a-preference trick does not work — preferences are
    /// re-sent when the view tree updates, which a scroll does not do.
    @ViewBuilder
    func trackScrollOffset(_ offset: Binding<CGFloat>) -> some View {
        if #available(macOS 15.0, *) {
            onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, now in
                offset.wrappedValue = now
            }
        } else {
            self
        }
    }
}

extension View {
    /// The pointing hand over a tile that goes somewhere.
    ///
    /// `pointerStyle` rather than `NSCursor` in a hover callback, for the
    /// reason above: the hosting view's cursor pass runs after the callback
    /// and wins, which is why the resize handle only changed the cursor on the
    /// second hover.
    @ViewBuilder
    func linkCursor(_ active: Bool) -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(active ? .link : nil)
        } else {
            self
        }
    }
}
