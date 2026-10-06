import MetricsCore
import SwiftUI

/// A connector's mark: its symbol on a tile of its own brand colour.
///
/// Not the vendor's logo. Shipping third-party marks means an asset pipeline,
/// a licence question for each one, and a release every time somebody
/// rebrands — and the app's whole point is that a connector can ship without
/// a Mac release. The brand *colour* carries most of the recognition anyway,
/// and it arrives from the server with the manifest.
public struct ConnectorIcon: View {
    public let app: MetricApp
    public var size: CGFloat
    /// Dimmed for connectors that cannot be connected yet.
    public var isEnabled: Bool

    public init(app: MetricApp, size: CGFloat = 28, isEnabled: Bool = true) {
        self.app = app
        self.size = size
        self.isEnabled = isEnabled
    }

    private var tint: Color { NotchTheme.accent(for: app) }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(tint.opacity(isEnabled ? 0.16 : 0.08))
            .overlay(
                Image(systemName: app.symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(tint)
                    .opacity(isEnabled ? 1 : 0.45)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(tint.opacity(isEnabled ? 0.22 : 0.1), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
