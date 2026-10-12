import MetricsCore
import SwiftUI

/// The geometry of the drop, in one place.
///
/// Shared between the view that draws it and the controller that has to make
/// the same rect clickable — `hitTest` returns nil outside `activeHitRect`, so
/// a banner the controller mismeasures is visible and dead.
public enum NotchBannerMetrics {
    /// The mark that falls out of the notch, and the disc behind it.
    ///
    /// The disc is the mark's *background*, not a container it sits inside:
    /// `ConnectorIcon` draws a rounded square with a `size * 0.26` corner
    /// radius, which puts its corners at `0.6 * size` from the centre — so a
    /// circle of `1.2 * size` is the smallest one that contains them.
    ///
    /// Derived rather than typed as a literal, because the two numbers are not
    /// independent: tighten the ratio and the brand mark's corners get clipped,
    /// loosen it and the disc reads as a gap around a small logo.
    public static let icon: CGFloat = 26
    public static let circle: CGFloat = (icon * 1.2).rounded(.up)

    /// How far clear of the notch it falls before opening.
    public static let gap: CGFloat = 12
    public static let cardWidth: CGFloat = 334
    /// Barely taller than the circle: the card grows sideways, not downwards,
    /// so it stays out of the way of whatever is under the menu bar.
    public static let cardHeight: CGFloat = 54

    public static func size(open: Bool) -> CGSize {
        open
            ? CGSize(width: cardWidth, height: cardHeight)
            : CGSize(width: circle, height: circle)
    }

    /// Both states are fully round-ended — half the circle, half the pill's
    /// height — so one shape animates the whole way and the mark's backing
    /// appears to be *stretched* sideways rather than swapped for a rectangle.
    public static func radius(open: Bool) -> CGFloat {
        open ? cardHeight / 2 : circle / 2
    }

    /// Closed, this is whatever is left over around the mark — a hair, by
    /// construction. Open, it is a real left margin. One function doing both is
    /// what keeps the mark from visibly jumping as the pill stretches.
    public static func horizontalPadding(open: Bool) -> CGFloat {
        open ? 13 : (circle - icon) / 2
    }
}

/// One notification, dropped out of the notch as a circle and opened into a
/// card.
///
/// Deliberately not a `UNUserNotificationCenter` banner. An accessory app with
/// no Dock icon asking for notification permission before it has delivered
/// anything is the worst version of this feature, and the notch is already on
/// screen — so the app owns the presentation and needs no entitlement, no
/// Info.plist key and no permission prompt.
struct NotchDropBanner: View {
    let alert: NotchAlert
    /// False while it is still a falling circle.
    let isOpen: Bool
    let onTap: () -> Void

    var body: some View {
        let size = NotchBannerMetrics.size(open: isOpen)
        let radius = NotchBannerMetrics.radius(open: isOpen)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        return Button(action: onTap) {
            HStack(spacing: 10) {
                ConnectorIcon(app: AppCatalog.resolve(alert.provider), size: NotchBannerMetrics.icon)
                    .overlay(alignment: .bottomTrailing) {
                        if alert.severity == .warning {
                            Circle()
                                .fill(NotchTheme.warning)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(.black.opacity(0.55), lineWidth: 1.5))
                                .offset(x: 3, y: 3)
                        }
                    }

                if isOpen {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(alert.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(NotchTheme.primaryText)
                            .lineLimit(1)

                        if let line = secondLine {
                            Text(line)
                                .font(.system(size: 11))
                                .foregroundStyle(NotchTheme.secondaryText)
                                // One line. The card is a glance; the detail is
                                // in the notification centre a click away, and
                                // a wrapped second line would double its height.
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Slid out from behind the icon rather than faded in on the
                    // spot, so the text reads as having been revealed by the
                    // pill stretching open.
                    .transition(.opacity.combined(with: .offset(x: -12)))

                    if alert.link != nil {
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NotchTheme.tertiaryText)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, NotchBannerMetrics.horizontalPadding(open: isOpen))
            .frame(width: size.width, height: size.height)
            .background {
                shape
                    .fill(NotchTheme.surfaceMaterial)
                    .overlay(shape.fill(NotchTheme.surfaceTint))
            }
            .overlay(shape.strokeBorder(NotchTheme.panelStroke, lineWidth: 1))
            .compositingGroup()
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            // Clipped to the same shape it is filled with, or the text spills
            // past the corners for the frame or two where the card is still
            // narrower than its contents.
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(alert.link == nil ? "Open notifications" : "Open in your browser")
    }

    /// The body, or the amount when there is no body, so the card always says
    /// something beyond its title.
    private var secondLine: String? {
        if let body = alert.body, !body.isEmpty { return body }
        guard let amount = alert.amount, let currency = alert.currency else { return nil }
        // Minor units on the wire, divided here — the same conversion
        // `MetricFormatter.display` does for a currency tile.
        return MetricFormatter.currency(Double(amount) / 100, code: currency, compact: false)
    }
}
