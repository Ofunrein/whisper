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
        OpenAIKeyBox.Password = CredentialStore.GetApiKey("openai") ?? "";
        DeepgramKeyBox.Password = CredentialStore.GetApiKey("deepgram") ?? "";
        ElevenLabsKeyBox.Password = CredentialStore.GetApiKey("elevenlabs") ?? "";
        CerebrasKeyBox.Password = CredentialStore.GetApiKey("cerebras") ?? "";
        GeminiKeyBox.Password = CredentialStore.GetApiKey("gemini") ?? "";
        AnthropicKeyBox.Password = CredentialStore.GetApiKey("anthropic") ?? "";

        SttProviderPicker.SelectedIndex = s.SttProvider switch
        {
            SttProviderKind.Groq => 0,
            SttProviderKind.OpenAI => 1,
            SttProviderKind.Deepgram => 2,
            SttProviderKind.ElevenLabs => 3,
            _ => 0,
        };

        CleanupToggle.IsOn = s.CleanupEnabled;
        CleanupProviderPicker.SelectedIndex = s.CleanupProvider switch
        {
            CleanupProviderKind.None => 0,
            CleanupProviderKind.Groq => 1,
            CleanupProviderKind.Cerebras => 2,
            CleanupProviderKind.OpenAI => 3,
            CleanupProviderKind.Gemini => 4,
            CleanupProviderKind.Ollama => 5,
            CleanupProviderKind.Anthropic => 6,
            _ => 1,
        };
        OllamaBaseUrlBox.Text = s.OllamaBaseUrl;
        OllamaModelBox.Text = s.OllamaModel;

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
            { Kind: HotkeyKind.MouseButton, MouseButton: 3 } => 4,
            { Kind: HotkeyKind.MouseButton, MouseButton: 4 } => 5,
            _ => 0,
        };
        TriggerStylePicker.SelectedIndex = binding.Style == HotkeyTriggerStyle.Toggle ? 1 : 0;

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

    private void OnOpenAIKeyChanged(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        CredentialStore.SetApiKey("openai", OpenAIKeyBox.Password);
    }

    private void OnDeepgramKeyChanged(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        CredentialStore.SetApiKey("deepgram", DeepgramKeyBox.Password);
    }

    private void OnElevenLabsKeyChanged(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        CredentialStore.SetApiKey("elevenlabs", ElevenLabsKeyBox.Password);
    }

    private void OnCerebrasKeyChanged(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        CredentialStore.SetApiKey("cerebras", CerebrasKeyBox.Password);
    }

    private void OnGeminiKeyChanged(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        CredentialStore.SetApiKey("gemini", GeminiKeyBox.Password);
    }

    private void OnAnthropicKeyChanged(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        CredentialStore.SetApiKey("anthropic", AnthropicKeyBox.Password);
    }

    private void OnSttProviderChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_loaded) return;
        _store.Settings.SttProvider = (SttProviderPicker.SelectedIndex) switch
        {
            0 => SttProviderKind.Groq,
            1 => SttProviderKind.OpenAI,
            2 => SttProviderKind.Deepgram,
            3 => SttProviderKind.ElevenLabs,
            _ => SttProviderKind.Groq,
        };
        _store.Save();
    }

    private void OnCleanupToggled(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        _store.Settings.CleanupEnabled = CleanupToggle.IsOn;
        _store.Save();
    }

    private void OnCleanupProviderChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_loaded) return;
        _store.Settings.CleanupProvider = (CleanupProviderPicker.SelectedIndex) switch
        {
            0 => CleanupProviderKind.None,
            1 => CleanupProviderKind.Groq,
            2 => CleanupProviderKind.Cerebras,
            3 => CleanupProviderKind.OpenAI,
            4 => CleanupProviderKind.Gemini,
            5 => CleanupProviderKind.Ollama,
            6 => CleanupProviderKind.Anthropic,
            _ => CleanupProviderKind.Groq,
        };
        _store.Save();
    }

    private void OnOllamaBaseUrlChanged(object sender, TextChangedEventArgs e)
    {
        if (!_loaded) return;
        _store.Settings.OllamaBaseUrl = string.IsNullOrWhiteSpace(OllamaBaseUrlBox.Text)
            ? AppSettings.DefaultOllamaBaseUrl
            : OllamaBaseUrlBox.Text.Trim();
        _store.Save();
    }

    private void OnOllamaModelChanged(object sender, TextChangedEventArgs e)
    {
        if (!_loaded) return;
        _store.Settings.OllamaModel = string.IsNullOrWhiteSpace(OllamaModelBox.Text)
            ? AppSettings.DefaultOllamaModel
            : OllamaModelBox.Text.Trim();
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
        ApplyBindingFromPickers();
    }

    private void OnTriggerStylePickerChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_loaded) return;
        ApplyBindingFromPickers();
    }

    /// Both the key/button picker and the Hold/Toggle picker write into the
    /// same single HotkeyBinding, so either one changing re-derives the
    /// whole binding from current picker state rather than each handler
    /// mutating just its own field (which would drop whichever field the
    /// *other* handler set most recently, since HotkeyBinding is a record
    /// class replaced wholesale below, not mutated in place).
    private void ApplyBindingFromPickers()
    {
        var style = TriggerStylePicker.SelectedIndex == 1 ? HotkeyTriggerStyle.Toggle : HotkeyTriggerStyle.Hold;

        var binding = (HotkeyPicker.SelectedIndex) switch
        {
            0 => new HotkeyBinding { Kind = HotkeyKind.ModifierKey, VirtualKeyCode = HotkeyBinding.VK_RCONTROL },
            1 => new HotkeyBinding { Kind = HotkeyKind.ModifierKey, VirtualKeyCode = HotkeyBinding.VK_RMENU },
            2 => new HotkeyBinding { Kind = HotkeyKind.ModifierKey, VirtualKeyCode = HotkeyBinding.VK_RSHIFT },
            3 => new HotkeyBinding { Kind = HotkeyKind.MouseButton, MouseButton = 2 },
            4 => new HotkeyBinding { Kind = HotkeyKind.MouseButton, MouseButton = 3 },
            5 => new HotkeyBinding { Kind = HotkeyKind.MouseButton, MouseButton = 4 },
            _ => HotkeyBinding.DefaultRightControl(),
        };
        binding.Style = style;

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
