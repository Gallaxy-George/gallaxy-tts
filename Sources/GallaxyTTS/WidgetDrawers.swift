import AppKit
import Carbon
import QuartzCore
import SwiftUI

struct VoiceProviderPanel: View {
    var body: some View {
        ZStack {
            GallaxyDrawerGlassBackground(direction: .voice)

            VStack(alignment: .leading, spacing: 8) {
                Text("VOICE SOURCE")
                    .font(GallaxyBrand.displayFont(size: 11.4, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.96))

                Text("LOCAL VOICE")
                    .font(GallaxyBrand.displayFont(size: 9.8, weight: .bold))
                    .foregroundStyle(GallaxyBrand.brandMaroonReadable.opacity(0.96))

                HStack(spacing: 7) {
                    Circle()
                        .fill(GallaxyBrand.textMain)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("LOCAL")
                            .font(GallaxyBrand.displayFont(size: 10.9, weight: .bold))
                        Text("Kokoro 82M")
                            .font(GallaxyBrand.bodyFont(size: 9.4, weight: .semibold))
                            .foregroundStyle(GallaxyBrand.textMain.opacity(0.82))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(GallaxyBrand.textMain)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(GlassRowButtonBackground(active: true, pressed: false))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(GallaxyBrand.textMain.opacity(0.34), lineWidth: 1))

                Spacer(minLength: 0)

                Text("KOKORO LOCAL")
                    .font(GallaxyBrand.displayFont(size: 9.2, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.80))
            }
            .padding(EdgeInsets(top: 12, leading: 34, bottom: 12, trailing: 34))
        }
    }

}

struct PanelCommandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(GallaxyBrand.textMain.opacity(configuration.isPressed ? 0.72 : 0.88))
            .padding(.vertical, 5)
            .background(GlassCommandButtonBackground(pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(GallaxyBrand.textMain.opacity(0.16), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SlideoutRackPanel: View {
    @ObservedObject var viewModel: GallaxyTTSWidgetViewModel

    var body: some View {
        ZStack {
            GallaxyDrawerGlassBackground(direction: .rack)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        viewModel.rightDrawerMode = .clips
                    } label: {
                        Text("CLIPS")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DrawerTabButtonStyle(active: viewModel.rightDrawerMode == .clips))

                    Button {
                        viewModel.rightDrawerMode = .hotkey
                    } label: {
                        Text("HOTKEY")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DrawerTabButtonStyle(active: viewModel.rightDrawerMode == .hotkey))
                }
                .font(GallaxyBrand.displayFont(size: 8.8, weight: .bold))
                .frame(height: 30)

                if viewModel.rightDrawerMode == .clips {
                    ClipTrayPanelContent(viewModel: viewModel)
                } else {
                    HotkeyConfigurationPanel(viewModel: viewModel)
                }
            }
            .padding(EdgeInsets(top: 12, leading: 34, bottom: 12, trailing: 34))
        }
    }
}

struct ClipTrayPanelContent: View {
    @ObservedObject var viewModel: GallaxyTTSWidgetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CLIP TRAY")
                    .font(GallaxyBrand.displayFont(size: 11.4, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.96))
                Spacer()
                Text("\(viewModel.recentClipboardClips.count + (viewModel.currentClipboardClip == nil ? 0 : 1))")
                    .font(GallaxyBrand.displayFont(size: 9.8, weight: .bold))
                    .foregroundStyle(GallaxyBrand.brandMaroonReadable.opacity(0.96))
            }

            Text("CURRENT CLIP")
                .font(GallaxyBrand.displayFont(size: 8.8, weight: .bold))
                .foregroundStyle(GallaxyBrand.brandMaroonReadable.opacity(0.96))

            if let currentClip = viewModel.currentClipboardClip {
                ClipTrayRow(
                    clip: currentClip,
                    badge: "NOW",
                    compact: false,
                    action: { viewModel.speakClip(currentClip) }
                )
                .frame(height: 54)
            } else {
                ClipTrayEmptyRow(text: "clipboard empty")
                    .frame(height: 54)
            }

            Divider()
                .overlay(GallaxyBrand.borderSubtle)

            Text("RECENT CLIPS")
                .font(GallaxyBrand.displayFont(size: 8.8, weight: .bold))
                .foregroundStyle(GallaxyBrand.textMain.opacity(0.78))

            let clips = viewModel.recentClipboardClips
            ScrollView(.vertical, showsIndicators: clips.count > 3) {
                VStack(spacing: 5) {
                    if clips.isEmpty {
                        ClipTrayEmptyRow(text: "no recent clips")
                            .frame(height: 34)
                    } else {
                        ForEach(clips) { clip in
                            ClipTrayRow(
                                clip: clip,
                                badge: clip.source.uppercased().prefix(4).description,
                                compact: true,
                                action: { viewModel.speakClip(clip) }
                            )
                            .frame(height: 34)
                        }
                    }
                }
                .padding(.trailing, clips.count > 3 ? 5 : 0)
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}

struct HotkeyConfigurationPanel: View {
    @ObservedObject var viewModel: GallaxyTTSWidgetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("HOTKEY")
                    .font(GallaxyBrand.displayFont(size: 11.4, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.96))
                Spacer()
                if viewModel.hotkeyMessage.isEmpty == false {
                    Text(viewModel.hotkeyMessage)
                        .font(GallaxyBrand.displayFont(size: 8.2, weight: .bold))
                        .foregroundStyle(viewModel.hotkeyMessage == "UNAVAILABLE" ? GallaxyBrand.brandMaroonReadable : GallaxyBrand.textMain.opacity(0.78))
                }
            }

            Text(viewModel.isCapturingHotkey ? "PRESS A KEY" : "SPEAK SELECTION")
                .font(GallaxyBrand.displayFont(size: 8.8, weight: .bold))
                .foregroundStyle(GallaxyBrand.brandMaroonReadable.opacity(0.96))

            HotkeyRecorderField(
                configuration: viewModel.hotkeyDraft,
                isRecording: $viewModel.isCapturingHotkey,
                onCapture: viewModel.captureHotkey
            )
            .frame(height: 38)

            Button {
                viewModel.saveHotkey()
            } label: {
                Text("SAVE")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelCommandButtonStyle())
            .font(GallaxyBrand.displayFont(size: 9, weight: .bold))

            Spacer(minLength: 0)
        }
    }
}

struct HotkeyRecorderField: NSViewRepresentable {
    let configuration: HotkeyConfiguration
    @Binding var isRecording: Bool
    let onCapture: (HotkeyConfiguration) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        configure(view)
        return view
    }

    func updateNSView(_ view: HotkeyRecorderNSView, context: Context) {
        configure(view)
    }

    private func configure(_ view: HotkeyRecorderNSView) {
        view.displayLabel = isRecording ? "PRESS A KEY" : configuration.displayLabel
        view.isRecording = isRecording
        view.onRecordingChange = { isRecording in
            DispatchQueue.main.async {
                self.isRecording = isRecording
            }
        }
        view.onCapture = { configuration in
            DispatchQueue.main.async {
                self.isRecording = false
                onCapture(configuration)
            }
        }
    }
}

final class HotkeyRecorderNSView: NSView {
    var displayLabel = "" {
        didSet { needsDisplay = true }
    }
    var isRecording = false {
        didSet { needsDisplay = true }
    }
    var onRecordingChange: ((Bool) -> Void)?
    var onCapture: ((HotkeyConfiguration) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if !isRecording {
            isRecording = true
            onRecordingChange?(true)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            onRecordingChange?(false)
            return
        }

        guard let configuration = HotkeyConfiguration.captured(from: event) else { return }
        isRecording = false
        onRecordingChange?(false)
        onCapture?(configuration)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            onRecordingChange?(false)
        }
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor(calibratedWhite: 0.03, alpha: isRecording ? 0.92 : 0.64).setFill()
        shape.fill()

        (isRecording ? NSColor(calibratedRed: 0.68, green: 0.08, blue: 0.12, alpha: 0.96) : NSColor(calibratedWhite: 0.82, alpha: 0.22)).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 0.95)
        ]
        let size = (displayLabel as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: max(8, (bounds.width - size.width) / 2),
            y: (bounds.height - size.height) / 2,
            width: min(size.width, max(0, bounds.width - 16)),
            height: size.height
        )
        (displayLabel as NSString).draw(in: textRect, withAttributes: attributes)
    }
}

struct ClipTrayRow: View {
    let clip: ClipboardClip
    let badge: String
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                HStack(spacing: 5) {
                    Text(badge)
                        .font(GallaxyBrand.displayFont(size: compact ? 7.3 : 7.8, weight: .bold))
                        .foregroundStyle(GallaxyBrand.brandMaroonReadable.opacity(0.96))
                        .frame(width: 24, alignment: .leading)

                    Text(clip.title)
                        .font(GallaxyBrand.displayFont(size: compact ? 8.6 : 9.6, weight: .bold))
                        .foregroundStyle(GallaxyBrand.textMain.opacity(0.94))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(clip.preview)
                    .font(GallaxyBrand.bodyFont(size: compact ? 8.2 : 8.8, weight: .semibold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.76))
                    .lineLimit(compact ? 1 : 2)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, compact ? 4 : 6)
        }
        .buttonStyle(ClipTrayButtonStyle(active: !compact))
        .help(clip.preview)
    }
}

struct ClipTrayEmptyRow: View {
    let text: String

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(GallaxyBrand.pageBackground.opacity(0.22))
            .overlay(
                Text(text.uppercased())
                    .font(GallaxyBrand.displayFont(size: 8.2, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(GallaxyBrand.borderSubtle, lineWidth: 1)
            )
    }
}

struct ClipTrayButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(GlassRowButtonBackground(active: active, pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(active ? GallaxyBrand.textMain.opacity(0.30) : GallaxyBrand.textMain.opacity(0.16), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}


struct DrawerTabButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? GallaxyBrand.textMain : GallaxyBrand.textMain.opacity(0.88))
            .background(GlassRowButtonBackground(active: active, pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(active ? GallaxyBrand.textMain.opacity(0.34) : GallaxyBrand.textMain.opacity(0.20), lineWidth: 1)
            )
    }
}
