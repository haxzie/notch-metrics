import AppKit
import Foundation

/// Where the notch is, in screen coordinates.
public struct NotchGeometry: Equatable, Sendable {
    public let screenNumber: CGDirectDisplayID
    public let hasNotch: Bool
    /// In AppKit global coordinates (origin bottom-left).
    public let notchRect: CGRect
    public let screenFrame: CGRect
    public let menuBarHeight: CGFloat

    public init(
        screenNumber: CGDirectDisplayID, hasNotch: Bool,
        notchRect: CGRect, screenFrame: CGRect, menuBarHeight: CGFloat
    ) {
        self.screenNumber = screenNumber
        self.hasNotch = hasNotch
        self.notchRect = notchRect
        self.screenFrame = screenFrame
        self.menuBarHeight = menuBarHeight
    }
}

public enum NotchGeometryResolver {
    /// Width used for the floating pill on a display with no notch.
    public static let fallbackWidth: CGFloat = 200

    public static func geometry(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let displayID = screen.displayID

        // `visibleFrame` excludes the menu bar — except when it is set to
        // auto-hide, where the difference is zero and the status bar's own
        // thickness is the only honest answer.
        let measured = frame.maxY - screen.visibleFrame.maxY
        let menuBarHeight = measured > 0 ? measured : NSStatusBar.system.thickness

        // macOS 12+. A non-zero top safe-area inset is what a notch *is*; the
        // two auxiliary rects are the usable slivers either side of it.
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else {
            return NotchGeometry(
                screenNumber: displayID,
                hasNotch: false,
                notchRect: CGRect(
                    x: frame.midX - fallbackWidth / 2,
                    y: frame.maxY - menuBarHeight,
                    width: fallbackWidth,
                    height: menuBarHeight
                ),
                screenFrame: frame,
                menuBarHeight: menuBarHeight
            )
        }

        let width = max(0, frame.width - left.width - right.width)
        return NotchGeometry(
            screenNumber: displayID,
            hasNotch: true,
            notchRect: CGRect(
                x: frame.minX + left.width,
                y: frame.maxY - inset,
                width: width,
                height: inset
            ),
            screenFrame: frame,
            menuBarHeight: menuBarHeight
        )
    }

    /// The display the notch UI should live on, honouring the user's preference
    /// and falling back when the one they chose is unplugged.
    public static func targetScreen(policy: NotchDisplayPolicy, screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        switch policy {
        case .builtIn:
            return screens.first(where: { geometry(for: $0).hasNotch }) ?? screens.first
        case .followsMouse:
            let location = NSEvent.mouseLocation
            return screens.first(where: { $0.frame.contains(location) }) ?? screens.first
        case .specific(let id):
            return screens.first(where: { $0.displayID == id }) ?? screens.first
        }
    }
}

public enum NotchDisplayPolicy: Equatable, Sendable, Codable {
    case builtIn
    /// Costs a permanently installed global mouse monitor, so it is opt-in.
    case followsMouse
    case specific(CGDirectDisplayID)
}

extension NSScreen {
    public var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
