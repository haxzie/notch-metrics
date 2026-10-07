import AppKit
import MetricsAPI
import MetricsCore
import NotchUI
import SwiftUI

/// Browse every widget, drag one into the notch.
///
/// A window of its own rather than a Settings pane. The whole interaction is
/// dragging a tile onto the notch, and a sheet or a modal cannot be dragged
/// out of — Settings would have to be dismissed first, by which point the
/// thing being dragged to is the thing that was covering it.
///
/// Glass on purpose: it sits over whatever the user is working in, and an
/// opaque window reads as an app taking over the screen rather than a palette
/// hovering above it.
struct WidgetGalleryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = WidgetCatalogueModel()
    @State private var query = ""
    @State private var selection: GallerySelection = .all

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.5)
            detail
        }
        .task { await model.load(env: env) }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clears the traffic lights, which float over the content because
            // the window has no title bar of its own.
            Text("Add Widgets")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.top, 52)
                .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1, pinnedViews: []) {
                    sidebarRow(
                        icon: { AnyView(WidgetsMark(size: 15)) },
                        title: "All Widgets", count: nil, value: .all)

                    ForEach(model.groups) { group in
                        Text(group.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.top, 16)
                            .padding(.bottom, 5)

                        ForEach(group.connectors) { connector in
                            sidebarRow(
                                icon: {
                                    AnyView(
                                        ConnectorIcon(
                                            app: AppCatalog.resolve(connector.id), size: 19))
                                },
                                title: connector.name,
                                // What is already in the notch, not what is on
                                // offer — the number answers "how much of this
                                // have I got?", which is the question somebody
                                // reopening this window is asking.
                                count: model.widgetCount(for: connector.id, env: env),
                                value: .connector(connector.id))
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sidebarRow(
        icon: () -> AnyView, title: String, count: Int?, value: GallerySelection
    ) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
        } label: {
            HStack(spacing: 10) {
                icon().frame(width: 20)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("Search widgets…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                Spacer(minLength: 16)
                Text("Drag widgets to notch")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            Divider().opacity(0.5)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            centred {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading widgets…").foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            centred {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 9) {
                                    ConnectorIcon(
                                        app: AppCatalog.resolve(section.connector.id), size: 22)
                                    Text(section.connector.name)
                                        .font(.system(size: 14, weight: .medium))
                                }
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 180), spacing: 14)],
                                    alignment: .leading, spacing: 14
                                ) {
                                    ForEach(section.metrics) { metric in
                                        GalleryCard(
                                            connector: section.connector, metric: metric)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func centred<V: View>(@ViewBuilder _ body: () -> V) -> some View {
        VStack { Spacer(); body(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum GallerySelection: Hashable {
    case all
    case connector(String)
}

/// One draggable widget.
///
/// The card *is* a notch tile — the same `WidgetTile` the grid draws, with a
/// sample series behind it. A bespoke preview would be a second rendering of
/// the same thing, free to drift from what actually lands in the notch.
private struct GalleryCard: View {
    let connector: ConnectorEntry
    let metric: MetricDescriptor

    private var app: MetricApp { AppCatalog.resolve(connector.id) }

    var body: some View {
        WidgetTile(widget: draft, app: app, state: .value(GallerySample.series(for: metric)))
            .frame(height: 150)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.22)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .help(metric.methodology)
            // The payload the notch's drop destination decodes. A plain string
            // rather than a custom Transferable: it crosses a window boundary
            // and has to survive AppKit's pasteboard either way.
            .draggable(GalleryPayload.encode(connector: connector.id, metric: metric.id)) {
                WidgetTile(
                    widget: draft, app: app,
                    state: .value(GallerySample.series(for: metric))
                )
                .frame(width: 180, height: 110)
            }
    }

    private var draft: NotchWidget {
        NotchWidget(
            id: "gallery-\(connector.id)-\(metric.id)",
            kind: .providerMetric,
            appId: connector.id,
            metric: metric.id,
            title: metric.shortLabel,
            size: .square,
            granularity: metric.granularities.first ?? .day,
            range: .month,
            chart: metric.supportsSeries ? .sparkline : .none,
            format: WidgetFormat(compact: true))
    }
}

/// The drag payload, as one string.
enum GalleryPayload {
    static func encode(connector: String, metric: String) -> String {
        "notch-widget:\(connector)/\(metric)"
    }

    static func decode(_ raw: String) -> (connector: String, metric: String)? {
        guard raw.hasPrefix("notch-widget:") else { return nil }
        let body = raw.dropFirst("notch-widget:".count)
        guard let slash = body.firstIndex(of: "/") else { return nil }
        let connector = String(body[body.startIndex..<slash])
        let metric = String(body[body.index(after: slash)...])
        guard !connector.isEmpty, !metric.isEmpty else { return nil }
        return (connector, metric)
    }
}

/// Plausible numbers for a card that has not been pointed at an account yet.
///
/// Deterministic from the metric id, so the same widget looks the same every
/// time the window opens — a card that reshuffles its chart on every scroll
/// reads as live data, which is exactly what this is not.
enum GallerySample {
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
        return MetricSeries(
            integrationId: nil,
            metric: metric.id,
            unit: metric.unit,
            currency: metric.unit == .currency ? "USD" : nil,
            value: base,
            previousValue: base * 0.8,
            delta: MetricDelta(absolute: base * 0.2, percent: 25.6),
            points: metric.supportsSeries ? points : [],
            granularity: metric.granularities.first ?? .day,
            range: .month)
    }
}

// MARK: - The catalogue, grouped for this window

extension WidgetCatalogueModel {
    var groups: [ConnectorCategoryGroup] { categoryGroups }

    struct Section: Identifiable {
        let connector: ConnectorEntry
        let metrics: [MetricDescriptor]
        var id: String { connector.id }
    }

    func sections(matching query: String, selection: GallerySelection) -> [Section] {
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
