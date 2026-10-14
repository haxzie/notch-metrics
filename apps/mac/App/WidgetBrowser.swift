import AppKit
import MetricsAPI
import MetricsCore
import NotchUI
import SwiftUI

/// Browse every widget and click one to add it — inside the notch.
///
/// This was a window of its own, flush with the bottom of the screen, that a
/// tile was dragged out of and up into the notch. Two panels at opposite edges
/// of the display for one action, and the drag crossed everything the user had
/// open on the way. The notch is where the widget is going, so the choosing
/// happens there too.
///
/// Only the sidebar, the search field and the list live here: they need the
/// server's catalogue and the user's connections, which NotchUI knows nothing
/// about. The pane around this, and the way in and out, belong to
/// `NotchContentView` — the same split the configure form uses.
struct WidgetBrowserPane: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = WidgetCatalogueModel()
    @State private var query = ""
    @State private var selection: BrowseSelection = .all
    /// Why the last click did not add anything. Only the full-notch case
    /// happens in practice, and it needs saying — the click otherwise looks
    /// like it missed.
    @State private var problem: String?
    /// Which card the pointer is over.
    ///
    /// Held here rather than in each card. SwiftUI does not reliably send a
    /// card its hover-exit when the list scrolls out from under a still
    /// pointer, so two cards would both believe they were hovered and both
    /// draw the add badge. One id can only name one of them.
    @State private var hoveredID: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // Reloaded when the account picture changes, so a card added just
        // after signing in lands on a real connection.
        .task(id: env.catalogueRevision) { await model.load(env: env) }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 1) {
                sidebarRow(
                    icon: { AnyView(WidgetsMark(size: 13)) },
                    title: "All Widgets", count: nil, value: .all)

                ForEach(model.groups) { group in
                    Text(group.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ForEach(group.connectors) { connector in
                        sidebarRow(
                            icon: {
                                AnyView(
                                    ConnectorIcon(app: AppCatalog.resolve(connector.id), size: 16))
                            },
                            title: connector.name,
                            // How many widgets this connector offers, not how
                            // many are already in the notch — a row nobody has
                            // opened yet should not read as empty.
                            count: connector.metrics.count,
                            value: .connector(connector.id))
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 176)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sidebarRow(
        icon: () -> AnyView, title: String, count: Int?, value: BrowseSelection
    ) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
        } label: {
            HStack(spacing: 8) {
                icon().frame(width: 17)
                Text(title)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(NotchTheme.tertiaryText)
                }
            }
            .foregroundStyle(isSelected ? NotchTheme.primaryText : NotchTheme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            // Over the list rather than over the sidebar: it filters what is
            // on show, which is the way round people kept expecting.
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.tertiaryText)
                TextField("Search widgets…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.primaryText)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(NotchTheme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            if let problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(NotchTheme.editHighlight.opacity(0.18))
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            centred {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Loading widgets…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NotchTheme.secondaryText)
                }
            }
        case .failed(let message):
            centred {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
        case .loaded:
            let sections = model.sections(matching: query, selection: selection)
            if sections.isEmpty {
                centred {
                    Text(
                        query.isEmpty
                            ? "Nothing to add here yet."
                            : "Nothing matches “\(query)”."
                    )
                    .font(.system(size: 11.5))
                    .foregroundStyle(NotchTheme.secondaryText)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 7) {
                                    ConnectorIcon(
                                        app: AppCatalog.resolve(section.connector.id), size: 16)
                                    Text(section.connector.name)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(NotchTheme.secondaryText)
                                }
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 134), spacing: 10)],
                                    alignment: .leading, spacing: 10
                                ) {
                                    ForEach(section.metrics) { metric in
                                        BrowseCard(
                                            connector: section.connector, metric: metric,
                                            hoveredID: $hoveredID,
                                            onPick: { add(section.connector, metric) })
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func centred<V: View>(@ViewBuilder _ body: () -> V) -> some View {
        VStack { Spacer(); body(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Adding

    /// Puts the widget on the grid and opens its configuration.
    ///
    /// On the grid *first*, before anything is configured: the pane previews
    /// the real tile and the grid behind it updates live, neither of which can
    /// be done with a widget that does not exist yet. Cancel in the pane takes
    /// it back out again — see `configuringIsNew`.
    private func add(_ connector: ConnectorEntry, _ metric: MetricDescriptor) {
        let widget = NotchWidget(
            id: "w_\(UUID().uuidString.prefix(8))",
            kind: .providerMetric,
            appId: connector.id,
            // Whatever is already connected, so a new widget lands on real
            // numbers when there is only one account — the common case.
            integrationId: connector.connections.first?.id,
            metric: metric.id,
            title: metric.shortLabel,
            size: .wide,
            granularity: TimeRange.month.defaultGranularity,
            range: .month,
            chart: metric.supportsSeries ? .sparkline : .none,
            format: WidgetFormat(compact: true))

        guard env.layoutModel.add(widget) else {
            problem = "No room in the notch. Press Done, then drag the handle at the bottom "
                + "down to add a row."
            return
        }
        problem = nil

        Task { await env.refresh() }
        env.beginConfiguring(widget.id, isNew: true)
    }
}

enum BrowseSelection: Hashable {
    case all
    case connector(String)
}

/// One widget in the list.
///
/// The card *is* a notch tile — the same `WidgetTile` the grid draws, with a
/// sample series behind it. A bespoke preview would be a second rendering of
/// the same thing, free to drift from what actually lands in the notch.
private struct BrowseCard: View {
    let connector: ConnectorEntry
    let metric: MetricDescriptor
    /// Which card the pane thinks the pointer is over. See `hoveredID`.
    @Binding var hoveredID: String?
    let onPick: () -> Void

    private var id: String { "\(connector.id)/\(metric.id)" }
    private var isHovered: Bool { hoveredID == id }

    private var app: MetricApp { AppCatalog.resolve(connector.id) }

    /// The same test the configure pane uses to decide whether to offer a
    /// Range control. The preview should carry the window for exactly the
    /// metrics whose tile will.
    private var usesTimeWindow: Bool { metric.supportsSeries || metric.supportsCompare }

    var body: some View {
        Button(action: onPick) {
            // No background and no border of its own. `WidgetTile` already
            // draws a rounded fill, a hairline and a clip — wrapping it in a
            // second set put a card inside a card.
            WidgetTile(
                widget: draft, app: app, state: .value(WidgetSample.series(for: metric)),
                showsRange: usesTimeWindow)
                // Tall enough for the tallest thing a 2x1 draws — a chart
                // under a figure, or two list rows. `WidgetTile` fills the
                // height it is given but will not shrink below what its
                // contents need: too short and the ones with charts render
                // past their own rounded fill and over the card below, which
                // is what made a grid of equal frames look ragged.
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isHovered ? NotchTheme.editHighlight : .clear, lineWidth: 1.5))
                // The one thing the tile does not say on its own is that
                // clicking it does something. It appears on hover only, so a
                // list of thirty widgets is not a list of thirty buttons.
                .overlay(alignment: .topTrailing) {
                    if isHovered {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(NotchTheme.editHighlight))
                            .padding(5)
                            .transition(.opacity)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hoveredID = id
            } else if hoveredID == id {
                // Only if this card is still the one claiming the pointer:
                // a late exit from a card the pointer has already left would
                // otherwise clear the badge on the card it moved to.
                hoveredID = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(metric.methodology)
        .accessibilityLabel("Add \(metric.label)")
    }

    private var draft: NotchWidget {
        NotchWidget(
            id: "browse-\(id)",
            kind: .providerMetric,
            appId: connector.id,
            metric: metric.id,
            title: metric.shortLabel,
            // The size it will be when added, not a square: a preview that
            // is a different shape from the tile you get is a preview of
            // something else.
            size: .wide,
            granularity: TimeRange.month.defaultGranularity,
            range: .month,
            chart: metric.supportsSeries ? .sparkline : .none,
            format: WidgetFormat(compact: true))
    }
}

/// Plausible numbers for a card that has not been pointed at an account yet.
///
/// Deterministic from the metric id, so the same widget looks the same every
/// time the browser opens — a card that reshuffles its chart on every scroll
/// reads as live data, which is exactly what this is not.
enum WidgetSample {
    static func series(for metric: MetricDescriptor) -> MetricSeries {
        var seed = UInt64(abs(metric.id.hashValue) % 100_000 + 1)
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((seed >> 33) % 1000) / 1000
        }

        let base: Double = metric.unit == .currency ? 12_340_000 : 56
        let points = (0..<24).map { index in
            MetricPoint(
                t: "2026-01-\(String(format: "%02d", index % 28 + 1))T00:00:00Z",
                v: base * (0.55 + next() * 0.75))
        }
        let rows = sampleRows(for: metric.id)
        return MetricSeries(
            integrationId: nil,
            metric: metric.id,
            unit: metric.unit,
            currency: metric.unit == .currency ? "USD" : nil,
            value: base,
            previousValue: base * 0.8,
            delta: MetricDelta(absolute: base * 0.2, percent: 25.6),
            points: metric.supportsSeries ? points : [],
            granularity: TimeRange.month.defaultGranularity,
            range: .month,
            items: rows)
    }

    /// A list previews as rows, because a figure says nothing about what the
    /// widget will look like once it is on the grid.
    ///
    /// Keyed by metric id, which is a hardcoded list in the one place that can
    /// afford one: this is a *preview*, and a list metric missing from here
    /// shows a plausible number instead of nothing. Every other part of the
    /// browser reads the catalogue, so a new connector still needs no release
    /// — only its preview does.
    private static func sampleRows(for metric: String) -> [MetricListItem]? {
        switch metric {
        case "recent_payments":
            return [
                MetricListItem(
                    id: "1", t: "2026-01-28T11:40:00Z", label: "Ada Lovelace", detail: "Pro",
                    amount: 9_900, currency: "USD", status: "succeeded"),
                MetricListItem(
                    id: "2", t: "2026-01-28T09:12:00Z", label: "grace@example.com",
                    detail: "Starter", amount: 1_900, currency: "USD", status: "succeeded"),
                MetricListItem(
                    id: "3", t: "2026-01-27T22:05:00Z", label: "Linus T.", detail: "Team",
                    amount: 29_900, currency: "USD", status: "succeeded"),
            ]
        case "ci_runs":
            // One of each outcome, so the card shows what the icons mean
            // before anybody has connected anything.
            return [
                MetricListItem(
                    id: "1", t: "2026-01-28T11:40:00Z", label: "CI",
                    detail: "Fix the notch's resize handle", status: "success", state: .succeeded),
                MetricListItem(
                    id: "2", t: "2026-01-28T11:38:00Z", label: "Deploy the API",
                    detail: "Fix the notch's resize handle", status: "failure", state: .failed),
                MetricListItem(
                    id: "3", t: "2026-01-28T10:31:00Z", label: "Version and publish",
                    detail: "Cut 0.2.1", status: "in_progress", state: .running),
            ]
        default:
            return nil
        }
    }
}

// MARK: - The catalogue, grouped for this pane

extension WidgetCatalogueModel {
    var groups: [ConnectorCategoryGroup] { categoryGroups }

    struct Section: Identifiable {
        let connector: ConnectorEntry
        let metrics: [MetricDescriptor]
        var id: String { connector.id }
    }

    func sections(matching query: String, selection: BrowseSelection) -> [Section] {
        let all = categoryGroups.flatMap(\.connectors)
        let scoped: [ConnectorEntry]
        switch selection {
        case .all: scoped = all
        case .connector(let id): scoped = all.filter { $0.id == id }
        }

        // The same matcher the Settings pane uses, so "churn" finds the same
        // widgets in both places.
        let results = WidgetSearch.run(query, over: scoped)
        return results.compactMap { result in
            let metrics = query.isEmpty ? result.app.metrics : result.metrics
            guard !metrics.isEmpty else { return nil }
            return Section(connector: result.app, metrics: metrics)
        }
    }
}
