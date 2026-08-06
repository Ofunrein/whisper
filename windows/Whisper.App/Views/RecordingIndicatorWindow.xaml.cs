using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using WinRT.Interop;

namespace Whisper.App.Views;

/// Small always-on-top, borderless "recording -- click to stop" affordance.
/// Functional counterpart to the mac app's PillIndicator (see the XAML file
/// for what's deliberately not ported). Clicking anywhere on it stops the
/// recording via the same delegate App.xaml.cs already calls for the
/// hold-hotkey release / toggle-off path -- this is not a second code
/// path, just a second trigger for the existing one.
///
/// NOT compiled/tested in this environment (no Windows machine available),
/// same caveat as the rest of Whisper.App.
public sealed partial class RecordingIndicatorWindow : Window
{
    /// Raised when the user clicks the indicator. App.xaml.cs subscribes
    /// this to whatever it already calls on hotkey-release / toggle-off.
    public event Action? StopRequested;

    private readonly AppWindow _appWindow;

    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_NOACTIVATE = 0x08000000;

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(nint hWnd, int nIndex);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(nint hWnd, int nIndex, int dwNewLong);

    public RecordingIndicatorWindow()
    {
        InitializeComponent();

        var hwnd = WindowNative.GetWindowHandle(this);
        var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
        _appWindow = AppWindow.GetFromWindowId(windowId);

        // Tool window + no-activate: no taskbar entry, and clicking it
        // doesn't steal keyboard focus away from whatever app the user is
        // dictating into.
        var exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);

        _appWindow.IsShownInSwitchers = false;
        _appWindow.Resize(new Windows.Graphics.SizeInt32(220, 44));

        if (_appWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = true;
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.SetBorderAndTitleBar(false, false);
        }
    }

    /// Bottom-center of the primary display's work area, roughly matching
    /// the mac pill's default PillPlacement.bottomCenter with a similar
    /// margin above the taskbar/dock.
    private void PositionBottomCenter()
    {
        var displayArea = DisplayArea.GetFromWindowId(_appWindow.Id, DisplayAreaFallback.Primary);
        var work = displayArea.WorkArea;
        var size = _appWindow.Size;
        var x = work.X + (work.Width - size.Width) / 2;
        var y = work.Y + work.Height - size.Height - 48;
        _appWindow.Move(new Windows.Graphics.PointInt32(x, y));
    }

    public void ShowIndicator()
    {
        PositionBottomCenter();
        _appWindow.Show();
    }

    public void HideIndicator() => _appWindow.Hide();

    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        StopRequested?.Invoke();
    }
}
