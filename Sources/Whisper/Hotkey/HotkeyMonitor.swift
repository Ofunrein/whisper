import Foundation
import CoreGraphics

/// Watches the keyboard/mouse for the configured hotkey bindings and fires
/// record start/stop callbacks. Uses a listen-only CGEventTap on a dedicated
/// thread so it never blocks event delivery.
final class HotkeyMonitor {
    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var tapRunLoop: CFRunLoop?

    private let lock = NSLock()
    private var bindings: [HotkeyBinding] = []

    // Live state (only touched on the tap thread).
    private var fnDown = false
    private var pressedKeys = Set<UInt16>()
    private var recording = false
    private var holdIndex: Int?   // which binding started the current hold

    private let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]

    init(bindings: [HotkeyBinding] = []) {
        self.bindings = bindings
    }

    func updateBindings(_ newBindings: [HotkeyBinding]) {
        lock.lock()
        bindings = newBindings
        // Reset transient state so a stale hold can't get stuck.
        fnDown = false
        pressedKeys.removeAll()
        holdIndex = nil
        lock.unlock()
    }

    func start() {
        guard thread == nil else { return } // guard against double-start
        let t = Thread { [weak self] in self?.runTapLoop() }
        t.name = "com.whisper.hotkey"
        thread = t
        t.start()
    }

    func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = tapRunLoop { CFRunLoopStop(rl) }
        tap = nil
        runLoopSource = nil
        tapRunLoop = nil
        thread = nil
        if recording { recording = false; fire(start: false) }
    }

    // MARK: - Tap setup

    private func runTapLoop() {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: refcon) else {
            // Almost always missing Accessibility permission. Bail without crashing.
            NSLog("HotkeyMonitor: failed to create event tap (Accessibility permission?)")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        let rl = CFRunLoopGetCurrent()
        self.tapRunLoop = rl
        CFRunLoopAddSource(rl, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        lock.lock()
        let current = bindings
        lock.unlock()

        for (index, binding) in current.enumerated() {
            guard let edge = edge(for: binding, type: type, event: event) else { continue }
            dispatch(index: index, style: binding.style, edge: edge)
        }
    }

    private enum Edge { case press, release }

    private func edge(for binding: HotkeyBinding, type: CGEventType, event: CGEvent) -> Edge? {
        switch binding.kind {
        case .fnKey:
            guard type == .flagsChanged else { return nil }
            let on = event.flags.contains(.maskSecondaryFn)
            if on && !fnDown { fnDown = true; return .press }
            if !on && fnDown { fnDown = false; return .release }
            return nil

        case .keyCombo:
            guard let wantCode = binding.keyCode else { return nil }

            // Modifier-only keys (e.g. Right Command) never fire keyDown/keyUp —
            // only flagsChanged — so they need their own edge detection.
            if let side = ModifierOnlyKeys.side(for: wantCode) {
                guard type == .flagsChanged else { return nil }
                let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                guard code == wantCode else { return nil }
                let on = event.flags.contains(side.cgFlag)
                let wasOn = pressedKeys.contains(wantCode)
                if on && !wasOn { pressedKeys.insert(wantCode); return .press }
                if !on && wasOn { pressedKeys.remove(wantCode); return .release }
                return nil
            }

            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if type == .keyDown {
                guard code == wantCode, modifiersMatch(binding, event.flags) else { return nil }
                if pressedKeys.contains(code) { return nil } // ignore auto-repeat
                pressedKeys.insert(code)
                return .press
            } else if type == .keyUp {
                guard code == wantCode, pressedKeys.contains(code) else { return nil }
                pressedKeys.remove(code)
                return .release
            }
            return nil

        case .mouseButton:
            guard let want = binding.mouseButton else { return nil }
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard button == want else { return nil }
            if type == .otherMouseDown { return .press }
            if type == .otherMouseUp { return .release }
            return nil
        }
    }

    private func modifiersMatch(_ binding: HotkeyBinding, _ flags: CGEventFlags) -> Bool {
        let want = CGEventFlags(rawValue: binding.modifiers ?? 0).intersection(modifierMask)
        let have = flags.intersection(modifierMask)
        return want == have
    }

    private func dispatch(index: Int, style: HotkeyTriggerStyle, edge: Edge) {
        switch style {
        case .hold:
            if edge == .press {
                guard !recording else { return }
                recording = true
                holdIndex = index
                fire(start: true)
            } else if edge == .release {
                guard recording, holdIndex == index else { return }
                recording = false
                holdIndex = nil
                fire(start: false)
            }
        case .toggle:
            guard edge == .press else { return }
            recording.toggle()
            fire(start: recording)
        }
    }

    private func fire(start: Bool) {
        let cb = start ? onRecordStart : onRecordStop
        DispatchQueue.main.async { cb?() }
    }
}
