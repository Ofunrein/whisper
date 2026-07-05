import Foundation
import CoreGraphics
import AppKit

/// Command, Option, Control, and Shift are "modifier-only" keys: pressing one
/// alone never generates keyDown/keyUp, only flagsChanged. To use e.g. Right
/// Command as a standalone hotkey we detect it by keycode on flagsChanged
/// rather than waiting for a keyDown that will never come.
enum ModifierSide {
    case command, option, control, shift

    var cgFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }

    var nsFlag: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }
}

enum ModifierOnlyKeys {
    /// Hardware keycodes for the left/right variant of each modifier.
    static let table: [UInt16: ModifierSide] = [
        54: .command, // Right Command
        55: .command, // Left Command
        61: .option,  // Right Option
        58: .option,  // Left Option
        62: .control, // Right Control
        59: .control, // Left Control
        60: .shift,   // Right Shift
        56: .shift,   // Left Shift
    ]

    static func side(for keyCode: UInt16) -> ModifierSide? { table[keyCode] }

    static func isModifierOnly(_ keyCode: UInt16) -> Bool { table[keyCode] != nil }

    static func displayName(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 54: return "Right Command"
        case 55: return "Left Command"
        case 61: return "Right Option"
        case 58: return "Left Option"
        case 62: return "Right Control"
        case 59: return "Left Control"
        case 60: return "Right Shift"
        case 56: return "Left Shift"
        default: return nil
        }
    }
}
