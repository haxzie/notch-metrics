import AppKit
import MetricsCore
import SwiftUI
import UniformTypeIdentifiers

/// The screenshot editor: a live card above, the controls that change it
/// below.
///
/// The preview is the *same* `ShareCard` the exporter renders, scaled down to
/// fit the window rather than redrawn at window size. A preview built from its
/// own layout would be a second implementation of the card, free to disagree
/// with the file — which is the one thing a screenshot tool cannot get wrong.
public struct ShareEditorView: View {
    public let request: ShareRequest

    @State private var frame: ShareFrame
    @State private var background: ShareBackground
    @State private var widgetSize: WidgetSize
    /// The chart on the card, which starts as the widget's own but is not
    /// written back to it. A card is a picture of one moment, and wanting
    /// bars in a tweet is not wanting bars in the notch forever.
    @State private var chart: ChartKind
    /// Set after a save so the button can confirm rather than look inert.
    @State private var savedTo: URL?
    @State private var failure: String?

    public init(request: ShareRequest) {
        self.request = request
        _frame = State(initialValue: .square)
        _background = State(initialValue: .initial)
        // Opens on the size the widget already is, so the first thing shown
        // is the tile the user clicked share on. Anything else reads as the
        // editor having changed their widget.
        _widgetSize = State(
            initialValue: ShareTileMetrics.presets.contains(request.widget.size)
                ? request.widget.size : .square)
        _chart = State(initialValue: request.widget.chart)
    }

    /// Whether there is a series to draw at all.
    ///
    /// A snapshot metric — stargazers, open issues — has one point or none,
    /// and `WidgetTile` draws no chart for it however it is asked. Offering
    /// the menu there would be a control that visibly does nothing.
    private var hasSeries: Bool {
        if case .value(let series) = request.state { return series.points.count > 1 }
        return false
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // One field behind everything, running under the title bar to
            // the very top of the window. The bar used to sit in its own
            // strip below a divider, which cut the window into a picture and
            // a toolbar; the point of a floating bar is that there is one
            // surface and the controls hover over it.
            backdrop.ignoresSafeArea()
            preview
            bar.padding(.bottom, 18)
        }
        // Narrower than the old 780: the bar collapses now, so the window is
        // allowed to be small enough to need it.
        .frame(minWidth: 520, minHeight: 480)
        // Dark throughout: the card is the subject and a light chrome around
        // it bleeds into the preview, making every dark background look
        // lighter than it exports.
        .preferredColorScheme(.dark)
    }

    /// The window's own surface: a dark field, dotted, with a frosted sheet
    /// over it.
    ///
    /// The dots are the notch's own `DottedGrid`, which is what the grid's
    /// edit well is made of — the editor should look like part of the same
    /// app rather than a generic export window.
    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.11), Color(white: 0.045)],
                startPoint: .top, endPoint: .bottom)
            DottedGrid(pitch: 16, opacity: 0.07)
            // Over the dots rather than under them, so the texture is in the
            // glass instead of behind it.
            Rectangle().fill(.ultraThinMaterial).opacity(0.5)
        }
    }

    // MARK: - Preview

    private var preview: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 32
            // The bar floats over the bottom of the same surface, so the card
            // has to stop short of it rather than slide underneath.
            let barClearance: CGFloat = 86
            let available = CGSize(
                width: max(1, proxy.size.width - inset * 2),
                height: max(1, proxy.size.height - inset * 2 - barClearance))
            let card = frame.layoutSize
            // Never above 1: the card is already laid out at half its export
            // size, and blowing it up past that would show the preview
            // sharper than the controls next to it while telling the user
            // nothing new.
            let scale = min(available.width / card.width, available.height / card.height, 1)

            ShareCard(
                request: request, widgetSize: widgetSize, background: background, chart: chart,
                size: card
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(scale)
            .frame(width: card.width * scale, height: card.height * scale)
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            .frame(width: proxy.size.width, height: proxy.size.height - barClearance / 2)
            // Snappy rather than spring: the card changes aspect ratio when
            // the frame changes, and an overshoot on a rectangle whose shape
            // is also animating reads as a wobble.
            .animation(.snappy(duration: 0.24), value: frame)
            .animation(.snappy(duration: 0.24), value: widgetSize)
            .animation(.easeOut(duration: 0.18), value: chart)
            .animation(.easeOut(duration: 0.18), value: background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The bar

    /// One floating pill of controls, over the card rather than under it.
    ///
    /// Icons rather than words on the triggers. Four labelled dropdowns, each
    /// carrying a caption *and* its current value, came to most of the width
    /// of the window — and the two that matter, Copy and Download, were the
    /// ones pushed off the end when it got narrow. The picture on each
    /// trigger is the same one its menu rows carry, so the bar still says
    /// which frame, which background and which span without spelling them.
    private var bar: some View {
        // Two layouts, widest first. `ViewThatFits` picks the first that does
        // — which is what makes this survive a window dragged narrow, rather
        // than clipping whichever control happens to be last.
        ViewThatFits(in: .horizontal) {
            barContent(showsStatus: true, labelsExports: true)
            barContent(showsStatus: false, labelsExports: true)
            barContent(showsStatus: false, labelsExports: false)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(Color.black.opacity(0.35))))
        .overlay(
            Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        .animation(.easeOut(duration: 0.15), value: savedTo)
        .animation(.easeOut(duration: 0.15), value: failure)
    }

    private func barContent(showsStatus: Bool, labelsExports: Bool) -> some View {
        HStack(spacing: 8) {
            // The four choices, grouped: they are one kind of thing, and the
            // two buttons after them are another.
            HStack(spacing: 2) {
                trigger(
                    caption: "Frame", value: frame.name, icon: ShareMenuIcon.aspect(frame)
                ) {
                    ForEach(ShareFrame.presets) { preset in
                        Button {
                            frame = preset
                        } label: {
                            Text("\(preset.name) — \(preset.detail)")
                            Image(nsImage: ShareMenuIcon.aspect(preset))
                        }
                    }
                }

                trigger(
                    caption: "Background", value: background.name,
                    icon: ShareMenuIcon.swatch(background)
                ) {
                    // Sectioned by set. Twenty pictures in one flat list is a
                    // scroll with no shape to it; the sets are how somebody
                    // thinks about picking one.
                    ForEach(ShareBackground.groups) { group in
                        Section(group.label) {
                            ForEach(group.backgrounds) { preset in
                                Button {
                                    background = preset
                                } label: {
                                    Text(preset.name)
                                    Image(nsImage: ShareMenuIcon.swatch(preset))
                                }
                            }
                        }
                    }
                }

                trigger(
                    caption: "Size", value: ShareTileMetrics.label(for: widgetSize),
                    icon: ShareMenuIcon.span(widgetSize)
                ) {
                    ForEach(ShareTileMetrics.presets, id: \.rawValue) { size in
                        Button {
                            widgetSize = size
                        } label: {
                            Text("\(ShareTileMetrics.label(for: size)) — \(size.rawValue)")
                            Image(nsImage: ShareMenuIcon.span(size))
                        }
                    }
                }

                if hasSeries {
                    trigger(
                        caption: "Chart", value: Self.chartLabel(chart),
                        icon: ShareMenuIcon.chart(chart)
                    ) {
                        // Listed, not `allCases`: `ChartKind` crosses the wire
                        // and is deliberately not `CaseIterable`.
                        ForEach([ChartKind.sparkline, .bars, .none], id: \.rawValue) { kind in
                            Button {
                                chart = kind
                            } label: {
                                Text(Self.chartLabel(kind))
                                Image(nsImage: ShareMenuIcon.chart(kind))
                            }
                        }
                    }
                }
            }

            if showsStatus {
                status
                    .padding(.horizontal, 2)
            }

            Button {
                copy()
            } label: {
                if labelsExports {
                    Text("Copy")
                } else {
                    Image(systemName: "doc.on.doc")
                }
            }
            .controlSize(.large)
            .help("Copy the card to the clipboard")
            .fixedSize()

            Button {
                download()
            } label: {
                if labelsExports {
                    Text("Download").fontWeight(.semibold)
                } else {
                    Image(systemName: "arrow.down.to.line").fontWeight(.semibold)
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            // The same blue every other primary action in the app uses —
            // Done in the notch, Add on a new widget. The brand magenta made
            // the one button you press at the end of this flow look like a
            // different app's.
            .tint(NotchTheme.editHighlight)
            .help("Save the card as a PNG")
            .fixedSize()
            .keyboardShortcut("s", modifiers: .command)
        }
    }

    /// One dropdown: the current choice as a picture, and a chevron.
    ///
    /// No text at all. The caption and the value live in the tooltip, which
    /// is where a control this small has to keep them — an icon-only button
    /// with nothing to hover for is a guess.
    private func trigger(
        caption: String, value: String, icon: NSImage,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: icon)
                    .renderingMode(icon.isTemplate ? .template : .original)
                    .foregroundStyle(NotchTheme.secondaryText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(NotchTheme.tertiaryText)
            }
            .frame(height: 22)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.07)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        // `.button` + `.plain`, not `.borderlessButton`. The borderless style
        // throws the label away and draws its own — caption, chevron, no
        // value and no pill — so the bar said "Frame" three times and never
        // which frame.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(caption): \(value)")
    }

    /// "Sparkline" is what the type is called; "Line" is what it looks
    /// like, which is the question this menu answers.
    private static func chartLabel(_ kind: ChartKind) -> String {
        switch kind {
        case .none: return "None"
        case .sparkline: return "Line"
        case .bars: return "Bars"
        }
    }

    /// What the last Download or Copy did, and nothing otherwise.
    ///
    /// One line in the bar rather than a sheet. A save that reports nothing
    /// looks like a button that did nothing, and an alert for "wrote a file
    /// where you asked" is worse than the problem.
    ///
    /// The export's pixel size used to sit here when idle. It was a constant
    /// in a row that is otherwise all controls, and the frame trigger beside
    /// it already says which size is selected.
    @ViewBuilder
    private var status: some View {
        if let failure {
            Text(failure)
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.negative)
                .lineLimit(1)
                .truncationMode(.middle)
        } else if let savedTo {
            Text("Saved to \(savedTo.deletingLastPathComponent().lastPathComponent)")
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.positive)
                .lineLimit(1)
        }
    }


    // MARK: - Export

    private func render() -> Data? {
        ShareExport.png(
            request: request, widgetSize: widgetSize, background: background, chart: chart,
            frame: frame)
    }

    private func download() {
        guard let data = render() else {
            failure = "Could not render that card."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ShareExport.suggestedName(for: request)
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        // `runModal`, not `beginSheetModal`: the editor is a panel owned by an
        // accessory app, and a sheet on a non-activating panel can end up
        // behind the window it belongs to with no way back to it.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            failure = nil
            savedTo = url
        } catch {
            failure = "Could not write the file: \(error.localizedDescription)"
        }
    }

    /// Straight onto the pasteboard, for the common case of pasting into a
    /// post rather than keeping a file.
    private func copy() {
        guard let data = render(), let image = NSImage(data: data) else {
            failure = "Could not render that card."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        failure = nil
        savedTo = nil
    }
}
