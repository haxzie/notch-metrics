import SwiftUI

/// How tall the configure form wants to be.
///
/// Crosses a module boundary: the form is built in the app target, which has
/// the catalogue and the connections, but the notch is what has to be tall
/// enough to show it. A preference is the one direction SwiftUI passes data
/// up a tree it does not own.
public struct ConfigurePanelHeightKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0

    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
