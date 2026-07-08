using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Whisper.App.Hotkeys;
using Whisper.Core;
using Whisper.Core.Models;
using Whisper.App.Security;

namespace Whisper.App.Views;

public sealed partial class SettingsWindow : Window
{
    private readonly SettingsStore _store;
    private readonly HotkeyManager _hotkeys;
    private bool _loaded;

    public SettingsWindow(SettingsStore store, HotkeyManager hotkeys)
    {
        _store = store;
        _hotkeys = hotkeys;
        InitializeComponent();
        LoadFromSettings();
    }

    private void LoadFromSettings()
    {
        var s = _store.Settings;

        GroqKeyBox.Password = CredentialStore.GetApiKey("groq") ?? "";
        CleanupToggle.IsOn = s.CleanupEnabled;
        KeepClipboardToggle.IsOn = s.KeepOnClipboardAfterPaste;
        SaveAudioToggle.IsOn = s.SaveAudio;
        SoundEffectsToggle.IsOn = s.SoundEffectsEnabled;
        SystemAudioToggle.IsOn = s.RecordSystemAudio;

        var binding = s.Bindings.Count > 0 ? s.Bindings[0] : HotkeyBinding.DefaultRightControl();
        HotkeyPicker.SelectedIndex = binding switch
        {
            { Kind: HotkeyKind.ModifierKey, VirtualKeyCode: HotkeyBinding.VK_RCONTROL } => 0,
            { Kind: HotkeyKind.ModifierKey, VirtualKeyCode: HotkeyBinding.VK_RMENU } => 1,
            { Kind: HotkeyKind.ModifierKey, VirtualKeyCode: HotkeyBinding.VK_RSHIFT } => 2,
            { Kind: HotkeyKind.MouseButton, MouseButton: 2 } => 3,
            _ => 0,
        };

        RefreshVocabularyList();
        _loaded = true;
    }

    private void RefreshVocabularyList()
    {
        VocabularyList.ItemsSource = null;
        VocabularyList.ItemsSource = _store.Settings.Vocabulary
            .Select(v => string.IsNullOrEmpty(v.To) ? v.From : $"{v.From} -> {v.To}")
            .ToList();
    }

    private void OnGroqKeyChanged(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        CredentialStore.SetApiKey("groq", GroqKeyBox.Password);
    }

    private void OnCleanupToggled(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        _store.Settings.CleanupEnabled = CleanupToggle.IsOn;
        _store.Save();
    }

    private void OnKeepClipboardToggled(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        _store.Settings.KeepOnClipboardAfterPaste = KeepClipboardToggle.IsOn;
        _store.Save();
    }

    private void OnSaveAudioToggled(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        _store.Settings.SaveAudio = SaveAudioToggle.IsOn;
        _store.Save();
    }

    private void OnSoundEffectsToggled(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        _store.Settings.SoundEffectsEnabled = SoundEffectsToggle.IsOn;
        _store.Save();
    }

    private void OnSystemAudioToggled(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        _store.Settings.RecordSystemAudio = SystemAudioToggle.IsOn;
        _store.Save();
    }

    private void OnHotkeyPickerChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_loaded) return;

        var binding = (HotkeyPicker.SelectedIndex) switch
        {
            0 => new HotkeyBinding { Kind = HotkeyKind.ModifierKey, VirtualKeyCode = HotkeyBinding.VK_RCONTROL },
            1 => new HotkeyBinding { Kind = HotkeyKind.ModifierKey, VirtualKeyCode = HotkeyBinding.VK_RMENU },
            2 => new HotkeyBinding { Kind = HotkeyKind.ModifierKey, VirtualKeyCode = HotkeyBinding.VK_RSHIFT },
            3 => new HotkeyBinding { Kind = HotkeyKind.MouseButton, MouseButton = 2 },
            _ => HotkeyBinding.DefaultRightControl(),
        };

        _store.Settings.Bindings = new List<HotkeyBinding> { binding };
        _store.Save();

        _hotkeys.Stop();
        _hotkeys.Binding = binding;
        _hotkeys.Start();
    }

    private void OnAddVocabulary(object sender, RoutedEventArgs e)
    {
        var from = VocabFromBox.Text?.Trim();
        if (string.IsNullOrEmpty(from)) return;

        _store.Settings.Vocabulary.Add(new VocabularyEntry
        {
            From = from,
            To = string.IsNullOrWhiteSpace(VocabToBox.Text) ? null : VocabToBox.Text.Trim(),
        });
        _store.Save();

        VocabFromBox.Text = "";
        VocabToBox.Text = "";
        RefreshVocabularyList();
    }
}
