using System.Runtime.InteropServices;
using Whisper.Core.Models;

namespace Whisper.App.Hotkeys;

/// Global hold-to-record hotkey via WH_KEYBOARD_LL / WH_MOUSE_LL hooks.
/// Windows has no direct equivalent of the mac app's NSEvent global monitor,
/// but a low-level hook watching raw down/up transitions for the configured
/// key or mouse button gives the same "press and hold" semantics.
///
/// NOT compiled/tested in this environment (no Windows machine available).
/// Signatures below are the standard documented Win32 P/Invoke shapes.
public sealed class HotkeyManager : IDisposable
{
    public event Action? RecordingStarted;
    public event Action? RecordingStopped;

    private const int WH_KEYBOARD_LL = 13;
    private const int WH_MOUSE_LL = 14;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private const int WM_XBUTTONDOWN = 0x020B;
    private const int WM_XBUTTONUP = 0x020C;
    private const int WM_MBUTTONDOWN = 0x0207;
    private const int WM_MBUTTONUP = 0x0208;

    private delegate nint LowLevelProc(int nCode, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public nint dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT
    {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public nint dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int x; public int y; }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWindowsHookEx(int idHook, LowLevelProc lpfn, nint hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(nint hhk);

    [DllImport("user32.dll")]
    private static extern nint CallNextHookEx(nint hhk, int nCode, nint wParam, nint lParam);

    [DllImport("kernel32.dll")]
    private static extern nint GetModuleHandle(string? lpModuleName);

    private nint _keyboardHookId;
    private nint _mouseHookId;
    private readonly LowLevelProc _keyboardProc;
    private readonly LowLevelProc _mouseProc;
    private bool _isDown;

    public HotkeyBinding Binding { get; set; } = HotkeyBinding.DefaultRightControl();

    public HotkeyManager()
    {
        _keyboardProc = KeyboardHookCallback;
        _mouseProc = MouseHookCallback;
    }

    public void Start()
    {
        using var curProcess = System.Diagnostics.Process.GetCurrentProcess();
        using var curModule = curProcess.MainModule!;
        var hModule = GetModuleHandle(curModule.ModuleName);
        _keyboardHookId = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardProc, hModule, 0);
        _mouseHookId = SetWindowsHookEx(WH_MOUSE_LL, _mouseProc, hModule, 0);
    }

    public void Stop()
    {
        if (_keyboardHookId != 0) UnhookWindowsHookEx(_keyboardHookId);
        if (_mouseHookId != 0) UnhookWindowsHookEx(_mouseHookId);
        _keyboardHookId = 0;
        _mouseHookId = 0;
    }

    private nint KeyboardHookCallback(int nCode, nint wParam, nint lParam)
    {
        if (nCode >= 0 && Binding.Kind is HotkeyKind.ModifierKey or HotkeyKind.KeyCombo)
        {
            var data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            if ((int)data.vkCode == Binding.VirtualKeyCode)
            {
                var msg = (int)wParam;
                if (msg is WM_KEYDOWN or WM_SYSKEYDOWN) SetDown(true);
                else if (msg is WM_KEYUP or WM_SYSKEYUP) SetDown(false);
            }
        }
        return CallNextHookEx(_keyboardHookId, nCode, wParam, lParam);
    }

    private nint MouseHookCallback(int nCode, nint wParam, nint lParam)
    {
        if (nCode >= 0 && Binding.Kind == HotkeyKind.MouseButton)
        {
            var msg = (int)wParam;
            var data = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            var xButton = (int)(data.mouseData >> 16); // 1 = XBUTTON1, 2 = XBUTTON2

            var isTargetDown =
                (msg == WM_MBUTTONDOWN && Binding.MouseButton == 2) ||
                (msg == WM_XBUTTONDOWN && Binding.MouseButton == (xButton == 1 ? 3 : 4));
            var isTargetUp =
                (msg == WM_MBUTTONUP && Binding.MouseButton == 2) ||
                (msg == WM_XBUTTONUP && Binding.MouseButton == (xButton == 1 ? 3 : 4));

            if (isTargetDown) SetDown(true);
            else if (isTargetUp) SetDown(false);
        }
        return CallNextHookEx(_mouseHookId, nCode, wParam, lParam);
    }

    private void SetDown(bool down)
    {
        if (down == _isDown) return;
        _isDown = down;

        if (Binding.Style == HotkeyTriggerStyle.Hold)
        {
            if (down) RecordingStarted?.Invoke();
            else RecordingStopped?.Invoke();
        }
        else if (down) // Toggle style only reacts to the down transition.
        {
            RecordingToggled?.Invoke();
        }
    }

    /// Fired on down-transition when Binding.Style == Toggle. Consumers
    /// should track their own is-recording state and route the toggle to
    /// RecordingStarted/RecordingStopped semantics themselves.
    public event Action? RecordingToggled;

    public void Dispose() => Stop();
}
