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
    private let expandedSize = NSSize(width: 110, height: 28)

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

    private func observeNotifications() {
        didMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.persistPosition()
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
        withAnimation(.easeInOut(duration: 0.18)) {
            model.state = s
        }
        resizeKeepingCenterX(to: newSize, animated: true)
    }

    func setLevel(_ f: Float) {
        model.level = max(0, min(1, f))
    }

    // MARK: - Positioning

    private func positionAtDefaultOrRestoredLocation() {
        let settings = SettingsStore.shared.settings
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin: NSPoint

        if let x = settings.pillPositionX, let y = settings.pillPositionY {
            origin = NSPoint(x: x, y: y)
        } else {
            let size = panel.frame.size
            origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + 24
            )
        }
        panel.setFrameOrigin(origin)
        avoidDockAndBounds(animated: false)
    }

    private func persistPosition() {
        let origin = panel.frame.origin
        var settings = SettingsStore.shared.settings
        settings.pillPositionX = Double(origin.x)
        settings.pillPositionY = Double(origin.y)
        SettingsStore.shared.settings = settings
    }

    /// Resize the panel while keeping it horizontally centered on its current position.
    private func resizeKeepingCenterX(to size: NSSize, animated: Bool) {
        let oldFrame = panel.frame
        let centerX = oldFrame.midX
        var newFrame = NSRect(
            x: centerX - size.width / 2,
            y: oldFrame.minY,
            width: size.width,
            height: size.height
        )
        newFrame = clampedFrame(newFrame, toScreenContaining: oldFrame)
        if animated {
            panel.animator().setFrame(newFrame, display: true, animate: true)
        } else {
            panel.setFrame(newFrame, display: true)
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

private struct PillContentView: View {
    @ObservedObject var model: PillLevelModel

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.85))
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
            switch model.state {
            case .collapsed:
                EmptyView()
            case .idle:
                IdleDotsView()
            case .recording:
                WaveformView(level: model.level)
                    .padding(.horizontal, 10)
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

private struct WaveformView: View {
    let level: Float
    private let barCount = 12

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let jitter = 0.5 + 0.5 * sin(t * 6 + Double(i) * 0.9)
                    let base = CGFloat(level)
                    let height = 3 + (16 * base * CGFloat(jitter)) + CGFloat.random(in: 0...1.5)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 2.5, height: max(3, min(20, height)))
                }
            }
            .animation(.linear(duration: 0.08), value: level)
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
