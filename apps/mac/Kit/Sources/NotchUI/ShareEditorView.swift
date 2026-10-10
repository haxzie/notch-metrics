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
    /// Set after a save so the button can confirm rather than look inert.
    @State private var savedTo: URL?
    @State private var failure: String?

    public init(request: ShareRequest) {
        self.request = request
        _frame = State(initialValue: .square)
        _background = State(initialValue: ShareBackground.presets[0])
        // Opens on the size the widget already is, so the first thing shown
        // is the tile the user clicked share on. Anything else reads as the
        // editor having changed their widget.
        _widgetSize = State(
            initialValue: ShareTileMetrics.presets.contains(request.widget.size)
                ? request.widget.size : .square)
    }

    public var body: some View {
        VStack(spacing: 0) {
            preview
            Divider().overlay(Color.white.opacity(0.08))
            bar
        }
        .frame(minWidth: 780, minHeight: 540)
        // Dark throughout: the card is the subject and a light chrome around
        // it bleeds into the preview, making every dark background look
        // lighter than it exports.
        .preferredColorScheme(.dark)
    }

    // MARK: - Preview

    private var preview: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 32
            let available = CGSize(
                width: max(1, proxy.size.width - inset * 2),
                height: max(1, proxy.size.height - inset * 2))
            let card = frame.layoutSize
            // Never above 1: the card is already laid out at half its export
            // size, and blowing it up past that would show the preview
            // sharper than the controls next to it while telling the user
            // nothing new.
            let scale = min(available.width / card.width, available.height / card.height, 1)

            ShareCard(
                request: request, widgetSize: widgetSize, background: background, size: card
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(scale)
            .frame(width: card.width * scale, height: card.height * scale)
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Snappy rather than spring: the card changes aspect ratio when
            // the frame changes, and an overshoot on a rectangle whose shape
            // is also animating reads as a wobble.
            .animation(.snappy(duration: 0.24), value: frame)
            .animation(.snappy(duration: 0.24), value: widgetSize)
            .animation(.easeOut(duration: 0.18), value: background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(checkerboard)
    }

    /// A flat dark field, not a real checkerboard.
    ///
    /// The card is always opaque, so there is no transparency for a
    /// checkerboard to reveal — it would only add texture behind a preview
    /// whose whole job is to show one gradient honestly.
    private var checkerboard: some View {
        LinearGradient(
            colors: [Color(white: 0.09), Color(white: 0.045)],
            startPoint: .top, endPoint: .bottom)
    }

    // MARK: - The bar

    /// One row of dropdowns and the two export buttons.
    ///
    /// This was three labelled rows of chips — every frame size, every
    /// background and every span on screen at once, which is most of a
    /// window spent showing options rather than the thing being made. Three
    /// choices do not need twenty controls; they need three menus.
    private var bar: some View {
        HStack(spacing: 14) {
            // `Menu`, not `Picker`. A Picker's button shows the selected
            // row's whole text, so "Square — Instagram post" ended up on the
            // button and three of those pushed Download off the end of the
            // bar. A Menu keeps the long, explanatory row and puts a short
            // word on the trigger.
            menu(label: frame.name, caption: "Frame", icon: ShareMenuIcon.aspect(frame)) {
                ForEach(ShareFrame.presets) { preset in
                    Button {
                        frame = preset
                    } label: {
                        Text("\(preset.name) — \(preset.detail)")
                        Image(nsImage: ShareMenuIcon.aspect(preset))
                    }
                }
            }

            menu(
                label: background.name, caption: "Background",
                icon: ShareMenuIcon.swatch(background)
            ) {
                ForEach(ShareBackground.presets) { preset in
                    Button {
                        background = preset
                    } label: {
                        Text(preset.name)
                        Image(nsImage: ShareMenuIcon.swatch(preset))
                    }
                }
            }

            menu(
                label: ShareTileMetrics.label(for: widgetSize), caption: "Size",
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

            Spacer(minLength: 8)

            status

            Button("Copy") { copy() }
                .controlSize(.large)
                .fixedSize()

            Button { download() } label: {
                Text("Download").fontWeight(.semibold)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(NotchTheme.gradientStart)
            .fixedSize()
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.28))
    }

    /// One dropdown: a quiet caption, the current choice as a picture and a
    /// word, and a chevron.
    ///
    /// The trigger carries the same icon its menu rows do, so the bar shows
    /// the chosen aspect ratio, gradient and span without being opened.
    private func menu(
        label: String, caption: String, icon: NSImage,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 7) {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.tertiaryText)
                Image(nsImage: icon)
                    .renderingMode(icon.isTemplate ? .template : .original)
                    .foregroundStyle(NotchTheme.secondaryText)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchTheme.primaryText)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(NotchTheme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.07)))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        // `.button` + `.plain`, not `.borderlessButton`. The borderless style
        // throws the label away and draws its own — caption, chevron, no
        // value and no pill — so the bar said "Frame" three times and never
        // which frame.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// The export size, or what the last Download or Copy did.
    ///
    /// One line in the bar rather than a sheet. A save that reports nothing
    /// looks like a button that did nothing, and an alert for "wrote a file
    /// where you asked" is worse than the problem.
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
        } else {
            Text("\(Int(frame.pixels.width)) × \(Int(frame.pixels.height)) px")
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchTheme.tertiaryText)
                .fixedSize()
        }
    }


    // MARK: - Export

    private func render() -> Data? {
        ShareExport.png(
            request: request, widgetSize: widgetSize, background: background, frame: frame)
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
