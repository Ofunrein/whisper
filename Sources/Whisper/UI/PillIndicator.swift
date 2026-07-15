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
    @Published var isHovering: Bool = false
    @Published var isPressed: Bool = false
}

/// Owns a borderless, non-activating floating panel that shows dictation status,
/// SuperWhisper-style, docked near the bottom of the screen.
final class PillController: NSObject {
    static let shared = PillController()

    /// Fired when the user clicks the pill while it's recording — the
    /// SuperWhisper-style tap-to-stop affordance. The app delegate wires
    /// this to the same stop path the hotkey release/toggle uses.
    var onStopClicked: (() -> Void)?

    private var panel: NSPanel!
    private let model = PillLevelModel()
    private var didMoveObserver: NSObjectProtocol?
    private var screenParamsObserver: NSObjectProtocol?

    private var baseCollapsedSize = NSSize(width: 56, height: 14)
    private var baseExpandedSize = NSSize(width: 128, height: 28)
    private var collapsedSize: NSSize { scaled(baseCollapsedSize) }
    private var expandedSize: NSSize { scaled(baseExpandedSize) }

    private func scaled(_ size: NSSize) -> NSSize {
        let scale = SettingsStore.shared.settings.pillScale
        return NSSize(width: size.width * scale, height: size.height * scale)
    }

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
        // Exclude from every system window-management surface (Sequoia's
        // edge-drag tiling overlay, Mission Control window cycling, tab
        // bars, window restoration) — this is an overlay indicator, not a
        // document window, and must never look like one to the WM.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.tabbingMode = .disallowed
        panel.isRestorable = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The SwiftUI content draws its own capsule-shaped shadow (see
        // PillContentView). The native window shadow is a separate,
        // independently-cached layer that AppKit doesn't reliably
        // re-mask on every animated resize/redraw (waveform, expand/
        // collapse) — it lags behind as a stale rectangular "ghost"
        // outline around the capsule. Disabling it leaves only the
        // shadow that always matches the current shape.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        let hosting = NSHostingView(rootView: PillContentView(model: model, onStopClicked: { [weak self] in
            self?.onStopClicked?()
        }))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        self.panel = panel
        positionAtDefaultOrRestoredLocation()
    }

    private var programmaticMove = false
    private var snapWorkItem: DispatchWorkItem?

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

            // Debounce until the drag settles, then snap to the nearest
            // preset spot (or stay custom). Runs once per drag since each
            // move cancels the pending snap.
            self.snapWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.snapToNearestPlacement() }
            self.snapWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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

    /// Origin for a preset placement on the screen containing the pill.
    private func presetOrigin(for placement: PillPlacement, size: NSSize) -> NSPoint? {
        let visible = screenContaining(panel.frame).visibleFrame
        switch placement {
        case .custom:
            let s = SettingsStore.shared.settings
            guard let x = s.pillPositionX, let y = s.pillPositionY else { return nil }
            return NSPoint(x: x, y: y)
        default:
            return Self.origin(for: placement, size: size, in: visible)
        }
    }

    static func origin(for placement: PillPlacement, size: NSSize, in visible: NSRect) -> NSPoint {
        let margin: CGFloat = 24
        let minCenterX = visible.minX + margin + size.width / 2
        let maxCenterX = visible.maxX - margin - size.width / 2
        let minCenterY = visible.minY + margin + size.height / 2
        let maxCenterY = visible.maxY - margin - size.height / 2

        let x25 = visible.minX + visible.width * 0.25
        let x50 = visible.midX
        let x75 = visible.minX + visible.width * 0.75
        let y25 = visible.minY + visible.height * 0.25
        let y50 = visible.midY
        let y75 = visible.minY + visible.height * 0.75

        let center: NSPoint
        switch placement {
        case .bottomLeft: center = NSPoint(x: minCenterX, y: minCenterY)
        case .bottomQuarter: center = NSPoint(x: x25, y: minCenterY)
        case .bottomCenter: center = NSPoint(x: x50, y: minCenterY)
        case .bottomThreeQuarter: center = NSPoint(x: x75, y: minCenterY)
        case .bottomRight: center = NSPoint(x: maxCenterX, y: minCenterY)
        case .leftLower: center = NSPoint(x: minCenterX, y: y25)
        case .middleLeft: center = NSPoint(x: minCenterX, y: y50)
        case .leftUpper: center = NSPoint(x: minCenterX, y: y75)
        case .center: center = NSPoint(x: x50, y: y50)
        case .rightLower: center = NSPoint(x: maxCenterX, y: y25)
        case .middleRight: center = NSPoint(x: maxCenterX, y: y50)
        case .rightUpper: center = NSPoint(x: maxCenterX, y: y75)
        case .topLeft: center = NSPoint(x: minCenterX, y: maxCenterY)
        case .topQuarter: center = NSPoint(x: x25, y: maxCenterY)
        case .topCenter: center = NSPoint(x: x50, y: maxCenterY)
        case .topThreeQuarter: center = NSPoint(x: x75, y: maxCenterY)
        case .topRight: center = NSPoint(x: maxCenterX, y: maxCenterY)
        case .custom: center = NSPoint(x: x50, y: y50)
        }

        return NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
    }

    /// Apply a preset placement (or restore the custom drag position).
    /// Animated by default (Settings picker, live snap); pass animated:false
    /// for the initial launch placement so the move applies synchronously.
    func applyPlacement(_ placement: PillPlacement, animated: Bool = true) {
        guard let origin = presetOrigin(for: placement, size: panel.frame.size) else { return }
        guard animated else {
            panel.setFrameOrigin(origin)
            return
        }
        programmaticMove = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(origin)
        }, completionHandler: { [weak self] in
            self?.programmaticMove = false
        })
    }

    /// SuperWhisper-style snap grid observed in reference video: 5 columns by
    /// 5 rows around the perimeter, plus center. Every drop zone resolves to
    /// the nearest slot, not only when close to an edge.
    private func snapToNearestPlacement() {
        let frame = panel.frame
        let visible = screenContaining(frame).visibleFrame
        let placement = Self.nearestPlacement(for: frame, in: visible)
        var settings = SettingsStore.shared.settings
        settings.pillPlacement = placement
        SettingsStore.shared.settings = settings
        applyPlacement(placement)
    }

    static func nearestPlacement(for frame: NSRect, in visible: NSRect) -> PillPlacement {
        let size = frame.size
        let center = NSPoint(x: frame.midX, y: frame.midY)
        var best: (placement: PillPlacement, distance: CGFloat)?

        for placement in PillPlacement.allCases where placement != .custom {
            let target = Self.origin(for: placement, size: size, in: visible)
            let targetCenter = NSPoint(x: target.x + size.width / 2, y: target.y + size.height / 2)
            let dx = center.x - targetCenter.x
            let dy = center.y - targetCenter.y
            let distance = dx * dx + dy * dy
            if distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (placement, distance)
            }
        }

        return best?.placement ?? .bottomCenter
    }

    func setLevel(_ f: Float) {
        model.level = max(0, min(1, f))
    }

    /// Re-applies the current scale to whichever size matches the pill's
    /// current state (idle/collapsed vs expanded), so a live scale change in
    /// Settings takes effect immediately instead of waiting for the next
    /// state transition.
    func applyScale() {
        let size = (model.state == .collapsed) ? collapsedSize : expandedSize
        resizeKeepingAnchor(to: size, animated: true)
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
        applyPlacement(SettingsStore.shared.settings.pillPlacement, animated: false)
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
    /// SuperWhisper-style tap-to-stop: while recording, clicking the pill
    /// stops the same way releasing/toggling the hotkey does.
    var onStopClicked: () -> Void

    private var isFilled: Bool {
        model.state == .recording || model.state == .processing
    }

    private var isClickToStop: Bool { model.state == .recording }

    var body: some View {
        ZStack {
            Capsule()
                .fill(model.errorFlash ? Color.red.opacity(0.75) : Color.black.opacity(isFilled ? 0.88 : 0.35))
            Capsule()
                .strokeBorder(
                    isClickToStop && model.isHovering
                        ? Color.red.opacity(0.85)
                        : Color.white.opacity(model.isHovering ? 0.7 : (isFilled ? 0.12 : 0.4)),
                    lineWidth: model.isHovering ? 1.75 : 1.25
                )
            switch model.state {
            case .collapsed:
                EmptyView()
            case .idle:
                IdleDotsView()
            case .recording:
                if model.isHovering {
                    // Hovering while recording swaps the waveform for an
                    // explicit stop affordance (SuperWhisper shows a stop
                    // square) so the click target's purpose is unambiguous,
                    // rather than relying on cursor/tooltip alone.
                    StopSquareView()
                } else {
                    WaveformView(level: model.level)
                        .padding(.horizontal, 12)
                }
            case .processing:
                ProcessingSpinnerView()
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
        .scaleEffect(model.isHovering ? 1.06 : (model.isPressed ? 0.94 : 1.0))
        .animation(.easeOut(duration: 0.15), value: model.isHovering)
        .animation(.easeOut(duration: 0.08), value: model.isPressed)
        .background(HoverTrackingView(isHovering: $model.isHovering))
        // Larger-than-visual hit target: the collapsed/recording capsule is
        // small, so clicking near it (not just exactly on the fill) still
        // registers as a stop request, matching SuperWhisper's forgiving
        // click zone.
        .contentShape(Rectangle())
        .padding(isClickToStop ? -8 : 0)
        .onTapGesture {
            guard isClickToStop else { return }
            onStopClicked()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if isClickToStop { model.isPressed = true } }
                .onEnded { _ in model.isPressed = false }
        )
        .help(isClickToStop ? "Click to stop recording" : "")
    }
}

/// Stop affordance shown on hover while recording — a simple filled square,
/// the universal "stop" glyph, sized to read clearly at pill scale.
private struct StopSquareView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.95))
            .frame(width: 10, height: 10)
    }
}

/// SwiftUI's `.onHover` is unreliable inside a borderless, non-activating
/// `NSPanel` — hover events don't consistently propagate the way they do in
/// a normal window. A real `NSTrackingArea` on the backing NSView is the
/// documented, reliable mechanism for hover detection regardless of window
/// style, so this wraps one via NSViewRepresentable.
private struct HoverTrackingView: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onHoverChange = { isHovering = $0 }
        return view
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {}

    final class TrackingNSView: NSView {
        var onHoverChange: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
        override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
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
