import Foundation
import AppKit

/// Watches the keyboard/mouse for the configured hotkey bindings and fires
/// record start/stop callbacks.
///
/// Uses NSEvent global+local monitors instead of a CGEventTap: a CGEventTap
/// on keyboard events silently requires the separate Input Monitoring TCC
/// permission, while NSEvent monitors only need Accessibility (which the app
/// already requests). This is the same fix OpenWhispr shipped.
final class HotkeyMonitor {
    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?

    private var globalMonitors: [Any] = []
    private var localMonitors: [Any] = []

    private var bindings: [HotkeyBinding] = []

    private var fnDown = false
    private var pressedKeys = Set<UInt16>()
    private var recording = false
    private var holdIndex: Int?   // which binding started the current hold

    private var rightClickHoldTimer: DispatchWorkItem?
    private var rightClickHeld = false // true once the hold threshold has fired for the current down-sequence
    private var suppressRightClickUntilUp = false // double-click/rapid-click guard
    private var lastRightClickUpTime: TimeInterval?

    private let modifierMask: NSEvent.ModifierFlags = [.command, .shift, .control, .option]

    init(bindings: [HotkeyBinding] = []) {
        self.bindings = bindings
    }

    func updateBindings(_ newBindings: [HotkeyBinding]) {
        bindings = newBindings
        fnDown = false
        pressedKeys.removeAll()
        holdIndex = nil
        rightClickHoldTimer?.cancel()
        rightClickHoldTimer = nil
        rightClickHeld = false
        suppressRightClickUntilUp = false
        lastRightClickUpTime = nil
        // A settings edit (e.g. deleting the binding that's mid-toggle) must
        // never leave `recording` stranded true with no matching stop fired --
        // that desync is what made toggle mode look like it "loops back on".
        if recording {
            recording = false
            fire(start: false)
        }
    }

    func start() {
        guard globalMonitors.isEmpty else { return } // guard against double-start
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp, .otherMouseDown, .otherMouseUp, .rightMouseDown, .rightMouseUp]

        // Global monitor: events while other apps are focused (the normal case).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            globalMonitors.append(m)
        } else {
            NSLog("HotkeyMonitor: failed to install global monitor (Accessibility permission?)")
        }

        // Local monitor: events while Whisper itself is focused (Settings open etc.).
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        if let local { localMonitors.append(local) }
    }

    func stop() {
        globalMonitors.forEach { NSEvent.removeMonitor($0) }
        localMonitors.forEach { NSEvent.removeMonitor($0) }
        globalMonitors.removeAll()
        localMonitors.removeAll()
        if recording { recording = false; fire(start: false) }
    }

    // MARK: - Event handling

    private func handle(_ event: NSEvent) {
        for (index, binding) in bindings.enumerated() where binding.kind == .rightClick {
            handleRightClick(index: index, binding: binding, event: event)
        }
        for (index, binding) in bindings.enumerated() where binding.kind != .rightClick {
            guard let edge = edge(for: binding, event: event) else { continue }
            dispatch(index: index, style: binding.style, edge: edge)
        }
    }

    /// Right-click has one job: hold to record.
 /// Quick clicks and double-clicks must pass through untouched.
 /// Even if old settings stored right-click as toggle, force hold here.
 private func handleRightClick(index: Int, binding: HotkeyBinding, event: NSEvent) {
 switch event.type {
 case .rightMouseDown:
 rightClickHoldTimer?.cancel()
 rightClickHoldTimer = nil
 rightClickHeld = false

 let now = event.timestamp
 let isRapidSecondClick = lastRightClickUpTime.map { now - $0 <= NSEvent.doubleClickInterval } ?? false
 guard event.clickCount == 1, !isRapidSecondClick else {
 suppressRightClickUntilUp = true
 return
 }

 suppressRightClickUntilUp = false
 let thresholdMs = SettingsStore.shared.settings.rightClickHoldThresholdMs
 let work = DispatchWorkItem { [weak self] in
 guard let self, !self.suppressRightClickUntilUp else { return }
 self.rightClickHeld = true
 self.dispatch(index: index, style: .hold, edge: .press)
 }
 rightClickHoldTimer = work
 DispatchQueue.main.asyncAfter(deadline: .now() + thresholdMs / 1000, execute: work)
 case .rightMouseUp:
 lastRightClickUpTime = event.timestamp
 rightClickHoldTimer?.cancel()
 rightClickHoldTimer = nil

 if suppressRightClickUntilUp {
 suppressRightClickUntilUp = false
 rightClickHeld = false
 return
 }

 guard rightClickHeld else { return }
 rightClickHeld = false
 dispatch(index: index, style: .hold, edge: .release)
 default:
 break
 }
 }

 private enum Edge { case press, release }

    private func edge(for binding: HotkeyBinding, event: NSEvent) -> Edge? {
        switch binding.kind {
        case .fnKey:
            guard event.type == .flagsChanged else { return nil }
            let on = event.modifierFlags.contains(.function)
            if on && !fnDown { fnDown = true; return .press }
            if !on && fnDown { fnDown = false; return .release }
            return nil

        case .keyCombo:
            guard let wantCode = binding.keyCode else { return nil }

            // Modifier-only keys (e.g. Right Command) never fire keyDown/keyUp —
            // only flagsChanged — so they need their own edge detection.
            if let side = ModifierOnlyKeys.side(for: wantCode) {
                guard event.type == .flagsChanged else { return nil }
                let on = event.modifierFlags.contains(side.nsFlag)
                let wasOn = pressedKeys.contains(wantCode)
                // Press requires the exact key; release trusts the flag bit —
                // if it cleared, the key is up no matter which event told us
                // (a missed release event must not leave recording stuck on).
                if event.keyCode == wantCode, on && !wasOn { pressedKeys.insert(wantCode); return .press }
                if !on && wasOn { pressedKeys.remove(wantCode); return .release }
                return nil
            }

            if event.type == .keyDown {
                guard event.keyCode == wantCode, modifiersMatch(binding, event.modifierFlags) else { return nil }
                if event.isARepeat || pressedKeys.contains(wantCode) { return nil }
                pressedKeys.insert(wantCode)
                return .press
            } else if event.type == .keyUp {
                guard event.keyCode == wantCode, pressedKeys.contains(wantCode) else { return nil }
                pressedKeys.remove(wantCode)
                return .release
            }
            return nil

        case .mouseButton:
            guard let want = binding.mouseButton, event.buttonNumber == want else { return nil }
            if event.type == .otherMouseDown { return .press }
            if event.type == .otherMouseUp { return .release }
            return nil

        case .rightClick:
            return nil // handled separately in handleRightClick, never reaches here
        }
    }

    private func modifiersMatch(_ binding: HotkeyBinding, _ flags: NSEvent.ModifierFlags) -> Bool {
        let want = NSEvent.ModifierFlags(rawValue: UInt(binding.modifiers ?? 0)).intersection(modifierMask)
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
