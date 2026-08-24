using System.Runtime.InteropServices;

namespace Whisper.App;

/// Minimal Shell_NotifyIcon system-tray presence, the Windows analogue of
/// the mac app's NSStatusItem menu-bar icon: a message-only window that
/// owns the tray icon and a right-click context menu (Settings / Quit).
///
/// NOT compiled/tested in this environment (no Windows machine available).
public sealed class TrayIcon : IDisposable
{
    public event Action? SettingsRequested;
    public event Action? QuitRequested;
    public event Action? CheckForUpdatesRequested;

    private const int WM_USER = 0x0400;
    private const int WM_TRAYICON = WM_USER + 1;
    private const int WM_LBUTTONUP = 0x0202;
    private const int WM_RBUTTONUP = 0x0205;
    private const int WM_COMMAND = 0x0111;
    private const int WM_DESTROY = 0x0002;

    private const int ID_SETTINGS = 1001;
    private const int ID_QUIT = 1002;
    private const int ID_CHECK_UPDATES = 1003;

    private const uint NIF_MESSAGE = 0x1;
    private const uint NIF_ICON = 0x2;
    private const uint NIF_TIP = 0x4;
    private const uint NIM_ADD = 0x0;
    private const uint NIM_DELETE = 0x2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATA
    {
        public int cbSize;
        public nint hWnd;
        public int uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public nint hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szTip;
    }

    private delegate nint WndProc(nint hWnd, uint msg, nint wParam, nint lParam);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern bool Shell_NotifyIcon(uint dwMessage, ref NOTIFYICONDATA lpData);

    [DllImport("user32.dll")]
    private static extern nint CreatePopupMenu();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool AppendMenu(nint hMenu, uint uFlags, uint uIDNewItem, string lpNewItem);

    [DllImport("user32.dll")]
    private static extern bool TrackPopupMenuEx(nint hMenu, uint uFlags, int x, int y, nint hwnd, nint lptpm);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(nint hWnd);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int x; public int y; }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern ushort RegisterClassEx(ref WNDCLASSEX lpwcx);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern nint CreateWindowEx(
        uint dwExStyle, string lpClassName, string lpWindowName, uint dwStyle,
        int x, int y, int nWidth, int nHeight,
        nint hWndParent, nint hMenu, nint hInstance, nint lpParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern nint DefWindowProc(nint hWnd, uint msg, nint wParam, nint lParam);

    [DllImport("user32.dll")]
    private static extern nint LoadIcon(nint hInstance, nint lpIconName);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern nint GetModuleHandle(string? lpModuleName);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern uint ExtractIconEx(string lpszFile, int nIconIndex, nint[]? phiconLarge, nint[]? phiconSmall, uint nIcons);

    /// Pulls icon index 0 out of the running exe's own resources -- the
    /// icon embedded there via the csproj's ApplicationIcon (Assets/AppIcon.ico)
    /// -- instead of the IDI_APPLICATION stock placeholder.
    private static nint LoadAppIcon()
    {
        var exePath = Environment.ProcessPath;
        if (string.IsNullOrEmpty(exePath)) return LoadIcon(0, new nint(32512));

        var large = new nint[1];
        var extracted = ExtractIconEx(exePath, 0, large, null, 1);
        return extracted > 0 && large[0] != 0 ? large[0] : LoadIcon(0, new nint(32512));
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASSEX
    {
        public int cbSize;
        public uint style;
        public WndProc lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public nint hInstance;
        public nint hIcon;
        public nint hCursor;
        public nint hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
        public nint hIconSm;
    }

    private readonly WndProc _wndProc;
    private nint _hwnd;
    private NOTIFYICONDATA _icon;

    public TrayIcon()
    {
        _wndProc = WindowProc;
    }

    public void Create()
    {
        var hInstance = GetModuleHandle(null);
        var wc = new WNDCLASSEX
        {
            cbSize = Marshal.SizeOf<WNDCLASSEX>(),
            lpfnWndProc = _wndProc,
            hInstance = hInstance,
            lpszClassName = "WhisperTrayWindow",
        };
        // Every P/Invoke here that touches a string has to be pinned to CharSet.Unicode.
        // Without it DllImport defaults to CharSet.Ansi and binds RegisterClassExA, while
        // WNDCLASSEX is declared CharSet.Unicode and so marshals lpszClassName as UTF-16 --
        // which RegisterClassExA reads as the single byte "W". CreateWindowExA then asks
        // for a class named "WhisperTrayWindow" that was never registered, returns 0, and
        // Shell_NotifyIcon gets hWnd = 0: no icon, no menu, no way to reach Settings or
        // Quit. The app looks like it never started at all.
        if (RegisterClassEx(ref wc) == 0)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "RegisterClassEx failed for the tray window");

        _hwnd = CreateWindowEx(0, "WhisperTrayWindow", "Whisper", 0, 0, 0, 0, 0, 0, 0, hInstance, 0);
        if (_hwnd == 0)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "CreateWindowEx failed for the tray window");

        _icon = new NOTIFYICONDATA
        {
            cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
            hWnd = _hwnd,
            uID = 1,
            uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP,
            uCallbackMessage = WM_TRAYICON,
            hIcon = LoadAppIcon(),
            szTip = "Whisper",
        };
        if (!Shell_NotifyIcon(NIM_ADD, ref _icon))
            throw new InvalidOperationException("Shell_NotifyIcon(NIM_ADD) failed; the tray icon would be invisible.");
    }

    private nint WindowProc(nint hWnd, uint msg, nint wParam, nint lParam)
    {
        if (msg == WM_TRAYICON)
        {
            var evt = (int)lParam;
            if (evt is WM_LBUTTONUP or WM_RBUTTONUP)
                ShowMenu();
        }
        else if (msg == WM_COMMAND)
        {
            var id = (int)(wParam & 0xFFFF);
            if (id == ID_SETTINGS) SettingsRequested?.Invoke();
            else if (id == ID_QUIT) QuitRequested?.Invoke();
            else if (id == ID_CHECK_UPDATES) CheckForUpdatesRequested?.Invoke();
        }
        else if (msg == WM_DESTROY)
        {
            Shell_NotifyIcon(NIM_DELETE, ref _icon);
        }
        return DefWindowProc(hWnd, msg, wParam, lParam);
    }

    private void ShowMenu()
    {
        GetCursorPos(out var pt);
        var menu = CreatePopupMenu();
        AppendMenu(menu, 0, ID_SETTINGS, "Settings...");
        AppendMenu(menu, 0, ID_CHECK_UPDATES, "Check for Updates...");
        AppendMenu(menu, 0, ID_QUIT, "Quit Whisper");
        SetForegroundWindow(_hwnd);
        TrackPopupMenuEx(menu, 0, pt.x, pt.y, _hwnd, 0);
    }

    public void Dispose() => Shell_NotifyIcon(NIM_DELETE, ref _icon);
}
