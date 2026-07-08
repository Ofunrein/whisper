namespace Whisper.Core.Models;

public enum HotkeyKind { ModifierKey, KeyCombo, MouseButton }

public enum HotkeyTriggerStyle { Hold, Toggle }

/// Windows analogue of Sources/Whisper/Store/Settings.swift HotkeyBinding.
/// There's no RegisterHotKey equivalent that reports hold-vs-release, so
/// HotkeyManager tracks these via a WH_KEYBOARD_LL / WH_MOUSE_LL hook
/// (down = start, up = stop), the same shape as the mac NSEvent monitor.
public sealed class HotkeyBinding
{
    public HotkeyKind Kind { get; set; }

    /// Win32 virtual-key code (e.g. VK_RCONTROL = 0xA3). Used for
    /// ModifierKey and KeyCombo.
    public int? VirtualKeyCode { get; set; }

    /// Extra modifiers required alongside VirtualKeyCode for KeyCombo
    /// (bitmask: 1=Ctrl, 2=Alt, 4=Shift, 8=Win).
    public int? Modifiers { get; set; }

    /// 2 = middle, 3 = XButton1, 4 = XButton2.
    public int? MouseButton { get; set; }

    public HotkeyTriggerStyle Style { get; set; } = HotkeyTriggerStyle.Hold;

    public string? Name { get; set; }

    public const int VK_RCONTROL = 0xA3;
    public const int VK_LCONTROL = 0xA2;
    public const int VK_RMENU = 0xA5;   // right Alt
    public const int VK_LMENU = 0xA4;   // left Alt
    public const int VK_RSHIFT = 0xA1;
    public const int VK_LSHIFT = 0xA0;
    public const int VK_RWIN = 0x5C;
    public const int VK_LWIN = 0x5B;

    public static HotkeyBinding DefaultRightControl() => new()
    {
        Kind = HotkeyKind.ModifierKey,
        VirtualKeyCode = VK_RCONTROL,
        Style = HotkeyTriggerStyle.Hold,
    };
}
