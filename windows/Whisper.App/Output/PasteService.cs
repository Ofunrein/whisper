using System.Runtime.InteropServices;
using Windows.ApplicationModel.DataTransfer;

namespace Whisper.App.Output;

/// Sets the transcript on the clipboard and synthesizes Ctrl+V, mirroring
/// the mac app's paste-at-cursor output mode. If KeepOnClipboardAfterPaste
/// is false, the previous clipboard contents are restored afterward.
///
/// NOT compiled/tested in this environment (no Windows machine available).
public static class PasteService
{
    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public nint dwExtraInfo;
    }

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_V = 0x56;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    public static async Task PasteAsync(string text, bool keepOnClipboard)
    {
        string? previous = null;
        if (!keepOnClipboard)
        {
            try
            {
                var existing = Clipboard.GetContent();
                if (existing.Contains(StandardDataFormats.Text))
                    previous = await existing.GetTextAsync();
            }
            catch
            {
                // No prior clipboard text (or access denied) -- nothing to restore.
            }
        }

        var data = new DataPackage();
        data.SetText(text);
        Clipboard.SetContent(data);

        // Give the clipboard a moment to settle before the target app reads it.
        await Task.Delay(50);
        SendCtrlV();

        if (!keepOnClipboard)
        {
            await Task.Delay(150);
            if (previous != null)
            {
                var restore = new DataPackage();
                restore.SetText(previous);
                Clipboard.SetContent(restore);
            }
        }
    }

    private static void SendCtrlV()
    {
        var inputs = new[]
        {
            KeyInput(VK_CONTROL, down: true),
            KeyInput(VK_V, down: true),
            KeyInput(VK_V, down: false),
            KeyInput(VK_CONTROL, down: false),
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    private static INPUT KeyInput(ushort vk, bool down) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                dwFlags = down ? 0u : KEYEVENTF_KEYUP,
            },
        },
    };
}
