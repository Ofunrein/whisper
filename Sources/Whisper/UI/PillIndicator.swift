import AppKit
import SwiftUI
import Combine

enum PillState: Equatable {
    case collapsed
    case idle
    case recording
    case processing
}

/// Publishes the current audio level (0...1) for the recording waveform.
final class PillLevelModel: ObservableObject {
    @Published var level: Float = 0
    @Published var state: PillState = .collapsed
    @Published var errorFlash: Bool = false
}

/// Owns a borderless, non-activating floating panel that shows dictation status,
/// SuperWhisper-style, docked near the bottom of the screen.
final class PillController: NSObject {
    static let shared = PillController()

    private var panel: NSPanel!
    private let model = PillLevelModel()
    private var didMoveObserver: NSObjectProtocol?
    private var screenParamsObserver: NSObjectProtocol?

    private let collapsedSize = NSSize(width: 56, height: 14)
    private let expandedSize = NSSize(width: 128, height: 28)

    override init() {
        super.init()
        setupPanel()
        observeNotifications()
    }

    private func setupPanel() {
        let size = collapsedSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        let hosting = NSHostingView(rootView: PillContentView(model: model))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        self.panel = panel
        positionAtDefaultOrRestoredLocation()
    }

    private var programmaticMove = false

    private func observeNotifications() {
        didMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.programmaticMove else { return }

            // Live-clamp during drag so the pill can never be dragged above the
            // menu bar or below/behind the Dock, matching SuperWhisper. This
            // fires continuously while the user drags, so re-entrancy is
            // guarded: clamping to an already-valid frame is a no-op.
            let current = self.panel.frame
            let clamped = self.clampedFrame(current, toScreenContaining: current)
            if clamped != current {
                self.programmaticMove = true
                self.panel.setFrame(clamped, display: true)
                self.programmaticMove = false
            }

            // A user drag switches to a custom placement.
            var settings = SettingsStore.shared.settings
            if settings.pillPlacement != .custom {
                settings.pillPlacement = .custom
                SettingsStore.shared.settings = settings
            }
            self.persistPosition()
        }

        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.avoidDockAndBounds(animated: true)
        }
    }

    deinit {
        if let o = didMoveObserver { NotificationCenter.default.removeObserver(o) }
        if let o = screenParamsObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Public API

    func show() {
        avoidDockAndBounds(animated: false)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func setState(_ s: PillState) {
        let newSize = (s == .collapsed) ? collapsedSize : expandedSize
        // SuperWhisper-style: springy expand when activating.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            model.state = s
        }
        resizeKeepingAnchor(to: newSize, animated: true)
    }

    /// Apply a preset placement (or restore the custom drag position).
    func applyPlacement(_ placement: PillPlacement) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let margin: CGFloat = 24
        var origin: NSPoint

        switch placement {
        case .bottomCenter: origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + margin)
        case .bottomLeft:   origin = NSPoint(x: visible.minX + margin, y: visible.minY + margin)
        case .bottomRight:  origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.minY + margin)
        case .topCenter:    origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - margin)
        case .topLeft:      origin = NSPoint(x: visible.minX + margin, y: visible.maxY - size.height - margin)
        case .topRight:     origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin)
        case .custom:
            let s = SettingsStore.shared.settings
            guard let x = s.pillPositionX, let y = s.pillPositionY else { return }
            origin = NSPoint(x: x, y: y)
        }

        programmaticMove = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().setFrameOrigin(origin)
        }, completionHandler: { [weak self] in
            self?.programmaticMove = false
        })
    }

    func setLevel(_ f: Float) {
        model.level = max(0, min(1, f))
    }

    /// Brief red flash so failures are visible, not just logged.
    func flashError() {
        model.errorFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.model.errorFlash = false
        }
    }

    // MARK: - Positioning

    private func positionAtDefaultOrRestoredLocation() {
        applyPlacement(SettingsStore.shared.settings.pillPlacement)
        avoidDockAndBounds(animated: false)
    }

    private func persistPosition() {
        let origin = panel.frame.origin
        var settings = SettingsStore.shared.settings
        settings.pillPositionX = Double(origin.x)
        settings.pillPositionY = Double(origin.y)
        SettingsStore.shared.settings = settings
    }

    /// Resize the panel around its center so the expand/collapse feels anchored,
    /// then clamp back inside the visible frame (handles top placements).
    private func resizeKeepingAnchor(to size: NSSize, animated: Bool) {
        let oldFrame = panel.frame
        var newFrame = NSRect(
            x: oldFrame.midX - size.width / 2,
            y: oldFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        newFrame = clampedFrame(newFrame, toScreenContaining: oldFrame)
        programmaticMove = true
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(newFrame, display: true)
            }, completionHandler: { [weak self] in
                self?.programmaticMove = false
            })
        } else {
            panel.setFrame(newFrame, display: true)
            programmaticMove = false
        }
    }

    /// If the panel is outside or overlapping beyond the screen's visible frame
    /// (Dock/menu bar excluded), slide it back inside.
    private func avoidDockAndBounds(animated: Bool) {
        let current = panel.frame
        let clamped = clampedFrame(current, toScreenContaining: current)
        guard clamped != current else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().setFrame(clamped, display: true, animate: true)
            }
        } else {
            panel.setFrame(clamped, display: true)
        }
    }

    private func screenContaining(_ frame: NSRect) -> NSScreen {
        for screen in NSScreen.screens {
            if screen.frame.intersects(frame) { return screen }
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private func clampedFrame(_ frame: NSRect, toScreenContaining ref: NSRect) -> NSRect {
        let screen = screenContaining(ref)
        let visible = screen.visibleFrame
        var f = frame

        if f.width > visible.width { f.size.width = visible.width }
        if f.height > visible.height { f.size.height = visible.height }

        if f.minX < visible.minX { f.origin.x = visible.minX }
        if f.maxX > visible.maxX { f.origin.x = visible.maxX - f.width }
        if f.minY < visible.minY { f.origin.y = visible.minY }
        if f.maxY > visible.maxY { f.origin.y = visible.maxY - f.height }

        return f
    }
}

// MARK: - SwiftUI content

/// Matches the real Wispr Flow / SuperWhisper behavior observed on video:
/// idle is an OUTLINED, unfilled capsule with dots; the moment recording
/// starts the capsule becomes solid-filled and shows the waveform. That
/// fill transition (not a colored dot) is what signals "it's recording".
private struct PillContentView: View {
    @ObservedObject var model: PillLevelModel

    private var isFilled: Bool {
        model.state == .recording || model.state == .processing
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(model.errorFlash ? Color.red.opacity(0.75) : Color.black.opacity(isFilled ? 0.88 : 0.35))
            Capsule()
                .strokeBorder(Color.white.opacity(isFilled ? 0.12 : 0.4), lineWidth: 1.25)
            switch model.state {
            case .collapsed:
                EmptyView()
            case .idle:
                IdleDotsView()
            case .recording:
                WaveformView(level: model.level)
                    .padding(.horizontal, 12)
            case .processing:
                ProcessingSpinnerView()
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
    }
}

private struct IdleDotsView: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<6, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 3.5, height: 3.5)
            }
        }
    }
}

/// Symmetric, center-weighted bar waveform matching the reference footage:
/// Wispr Flow and SuperWhisper both render a small equalizer that's tallest
/// in the middle and tapers toward the edges, pulsing with live mic level
/// rather than jittering independently per bar.
private struct WaveformView: View {
    let level: Float
    private let barCount = 9

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    let mid = Double(barCount - 1) / 2
                    let distanceFromCenter = abs(Double(i) - mid) / mid // 0 at center, 1 at edges
                    let envelope = 1.0 - 0.65 * distanceFromCenter // center-weighted taper
                    let sway = 0.7 + 0.3 * sin(t * 5 + Double(i) * 0.8) // organic, not random
                    let base = CGFloat(max(0.12, Double(level)))
                    let height = 4 + 15 * base * CGFloat(envelope) * CGFloat(sway)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2.5, height: max(4, min(20, height)))
                }
            }
            .animation(.easeInOut(duration: 0.12), value: level)
        }
    }
}

private struct ProcessingSpinnerView: View {
    @State private var rotation: Double = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 5, height: 5)
                    .scaleEffect(pulseScale(for: i))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    private func pulseScale(for index: Int) -> CGFloat {
        let phase = rotation / 360 * 2 * .pi + Double(index) * (.pi * 2 / 3)
        return 0.7 + 0.3 * CGFloat(0.5 + 0.5 * sin(phase))
    }
}
