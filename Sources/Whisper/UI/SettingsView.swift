import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        TabView {
            APIKeysTab()
                .tabItem { Label("API Keys", systemImage: "key.fill") }

            ProvidersTab(store: store)
                .tabItem { Label("Providers", systemImage: "cpu") }

            CleanupTab(store: store)
                .tabItem { Label("Cleanup", systemImage: "wand.and.stars") }

            VocabularyTab(store: store)
                .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }

            OutputTab(store: store)
                .tabItem { Label("Output", systemImage: "square.and.arrow.up") }

            HotkeyTab(store: store)
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { ModelCatalog.shared.refresh() }
    }
}

// MARK: - API Keys

private struct APIKeysTab: View {
    @State private var groq: String = ""
    @State private var elevenLabs: String = ""
    @State private var deepgram: String = ""
    @State private var gemini: String = ""
    @State private var cerebras: String = ""
    @State private var openAI: String = ""
    @State private var pendingClear: (title: String, text: Binding<String>, account: String)? = nil

    var body: some View {
        Form {
            GroupBox("Provider API Keys") {
                VStack(alignment: .leading, spacing: 10) {
                    keyRow("Groq", text: $groq, account: Keychain.groqKey)
                    keyRow("ElevenLabs", text: $elevenLabs, account: Keychain.elevenLabsKey)
                    keyRow("Deepgram", text: $deepgram, account: Keychain.deepgramKey)
                    keyRow("Gemini", text: $gemini, account: Keychain.geminiKey)
                    keyRow("Cerebras", text: $cerebras, account: Keychain.cerebrasKey)
                    keyRow("OpenAI", text: $openAI, account: Keychain.openAIKey)
                }
                .padding(8)
            }
        }
        .padding(.top, 8)
        .onAppear(perform: loadAll)
        .alert("Clear \(pendingClear?.title ?? "") key?", isPresented: Binding(
            get: { pendingClear != nil },
            set: { if !$0 { pendingClear = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingClear = nil }
            Button("Clear", role: .destructive) {
                if let pending = pendingClear {
                    pending.text.wrappedValue = ""
                    Keychain.set("", for: pending.account)
                }
                pendingClear = nil
            }
        } message: {
            Text("This removes the stored key. You'll need to paste it again to use this provider.")
        }
    }

    private func keyRow(_ title: String, text: Binding<String>, account: String) -> some View {
        HStack {
            Text(title)
                .frame(width: 90, alignment: .leading)
            SecureField("API key", text: text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { newValue in
                    Keychain.set(newValue, for: account)
                }
            Button {
                pendingClear = (title, text, account)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(text.wrappedValue.isEmpty)
            .help("Clear \(title) key")
        }
    }

    private func loadAll() {
        groq = Keychain.get(Keychain.groqKey) ?? ""
        elevenLabs = Keychain.get(Keychain.elevenLabsKey) ?? ""
        deepgram = Keychain.get(Keychain.deepgramKey) ?? ""
        gemini = Keychain.get(Keychain.geminiKey) ?? ""
        cerebras = Keychain.get(Keychain.cerebrasKey) ?? ""
        openAI = Keychain.get(Keychain.openAIKey) ?? ""
    }
}

// MARK: - Providers

private struct ProviderBadge: View {
    let isLocal: Bool

    var body: some View {
        Label(isLocal ? "Local" : "Cloud", systemImage: isLocal ? "desktopcomputer" : "cloud")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isLocal ? .green : .blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isLocal ? Color.green : Color.blue).opacity(0.14))
            .clipShape(Capsule())
    }
}

private struct ProvidersTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            GroupBox("Microphone") {
                Picker("Input device", selection: Binding(
                    get: { store.settings.preferredInputDevice ?? "" },
                    set: { store.settings.preferredInputDevice = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System Default").tag("")
                    ForEach(AudioDevices.inputDeviceNames(), id: \.self) { Text($0).tag($0) }
                }
                .padding(8)
            }

            GroupBox("Speech-to-Text") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("STT Provider", selection: $store.settings.sttProvider) {
                            ForEach(STTProviderKind.allCases) { kind in
                                Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                            }
                        }
                        ProviderBadge(isLocal: store.settings.sttProvider.isLocal)
                    }

                    Text(store.settings.sttProvider.isLocal ? "Local STT runs on this Mac." : "Cloud STT uses external API billing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if store.settings.sttProvider == .localWhisper {
                        Divider()
                        LocalWhisperSettings(store: store)
                    }
                }
                .padding(8)
            }

            GroupBox("Cleanup") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("Cleanup Provider", selection: $store.settings.cleanupProvider) {
                            ForEach(CleanupProviderKind.allCases) { kind in
                                Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                            }
                        }
                        ProviderBadge(isLocal: store.settings.cleanupProvider.isLocal)
                    }

                    Text(store.settings.cleanupProvider.isLocal ? "Local cleanup runs through Ollama." : "Cloud cleanup uses external API billing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                    Text("Model overrides")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ModelPicker(label: "Gemini model", provider: .gemini, selection: $store.settings.geminiModel)
                    ModelPicker(label: "Groq cleanup model", provider: .groq, selection: $store.settings.groqCleanupModel)
                    ModelPicker(label: "Cerebras model", provider: .cerebras, selection: $store.settings.cerebrasModel)
                    ModelPicker(label: "OpenAI cleanup model", provider: .openAI, selection: $store.settings.openAICleanupModel)
                    ModelPicker(label: "Ollama model", provider: .ollama, selection: $store.settings.ollamaModel)
                    LabeledContent("Ollama base URL") {
                        TextField("", text: $store.settings.ollamaBaseURL).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Spacer()
                        Button("Restore Model Defaults") {
                            store.settings.geminiModel = AppSettings.defaultGeminiModel
                            store.settings.groqCleanupModel = AppSettings.defaultGroqCleanupModel
                            store.settings.cerebrasModel = AppSettings.defaultCerebrasModel
                            store.settings.openAICleanupModel = AppSettings.defaultOpenAICleanupModel
                            store.settings.ollamaModel = AppSettings.defaultOllamaModel
                            store.settings.ollamaBaseURL = AppSettings.defaultOllamaBaseURL
                        }
                    }
                }
                .padding(8)
            }
        }
        .padding(.top, 8)
    }
}

private struct LocalWhisperSettings: View {
    @ObservedObject var store: SettingsStore
    @State private var downloadingID: String?
    @State private var downloadStatus = ""

    private var installedModels: [String] { LocalWhisperTranscriber.installedModels() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Model path", text: $store.settings.localWhisperModelPath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse") { chooseModel() }
                Button("Folder") { openModelsFolder() }
            }

            if !installedModels.isEmpty {
                Picker("Installed", selection: $store.settings.localWhisperModelPath) {
                    ForEach(installedModels, id: \.self) { path in
                        Text(URL(fileURLWithPath: path).lastPathComponent).tag(path)
                    }
                }
            }

            Text("Download local models")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(LocalWhisperTranscriber.downloadableModels) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.label)
                            Text("\(model.filename) · \(model.size)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if FileManager.default.fileExists(atPath: model.localURL.path) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Button("Use") { store.settings.localWhisperModelPath = model.localURL.path }
                        } else if downloadingID == model.id {
                            ProgressView().controlSize(.small)
                            Text(downloadStatus).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Download") { download(model) }
                        }
                    }
                }
            }

            Text("Install binary once: brew install whisper-cpp")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chooseModel() {
        LocalWhisperTranscriber.ensureModelDirectory()
        let panel = NSOpenPanel()
        panel.title = "Choose local Whisper model"
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = LocalWhisperTranscriber.modelDirectory
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.localWhisperModelPath = url.path
        }
    }

    private func openModelsFolder() {
        LocalWhisperTranscriber.ensureModelDirectory()
        NSWorkspace.shared.open(LocalWhisperTranscriber.modelDirectory)
    }

    private func download(_ model: LocalWhisperModel) {
        downloadingID = model.id
        downloadStatus = model.size
        Task {
            do {
                let local = try await LocalWhisperDownloader.download(model)
                await MainActor.run {
                    store.settings.localWhisperModelPath = local.path
                    downloadingID = nil
                    downloadStatus = ""
                }
            } catch {
                await MainActor.run {
                    downloadingID = nil
                    downloadStatus = "Failed"
                }
            }
        }
    }
}

// MARK: - Cleanup

private struct CleanupTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            GroupBox("Cleanup") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Clean up my speech", isOn: $store.settings.cleanupEnabled)

                    Text("Instructions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $store.settings.cleanupInstructions)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    HStack {
                        Button("Reset to default") {
                            store.settings.cleanupInstructions = defaultCleanupInstructions
                        }
                        Spacer()
                    }

                    Divider()

                    HStack {
                        Text("Cleanup timeout")
                        Slider(value: $store.settings.cleanupTimeoutSeconds, in: 2...15, step: 1)
                        Text("\(Int(store.settings.cleanupTimeoutSeconds))s")
                            .frame(width: 32, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
                .padding(8)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Vocabulary

private struct VocabularyTab: View {
    @ObservedObject var store: SettingsStore
    @State private var newFrom: String = ""
    @State private var newTo: String = ""

    var body: some View {
        Form {
            GroupBox("Vocabulary") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Words the cleanup model should always spell exactly as given (names, brands, jargon), plus replacement pairs applied directly to every transcript — even with cleanup off — to fix consistent mishears.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if store.settings.vocabulary.isEmpty {
                        Text("No vocabulary entries yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(store.settings.vocabulary.enumerated()), id: \.element.id) { index, entry in
                            HStack {
                                Text(entry.from)
                                if let to = entry.to {
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                    Text(to)
                                } else {
                                    Text("(known term)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    store.settings.vocabulary.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Divider()

                    HStack {
                        TextField("Word or misheard phrase", text: $newFrom)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Correct spelling (optional)", text: $newTo)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            guard !newFrom.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let to = newTo.trimmingCharacters(in: .whitespaces)
                            store.settings.vocabulary.append(VocabularyEntry(from: newFrom, to: to.isEmpty ? nil : to))
                            newFrom = ""
                            newTo = ""
                        }
                        .disabled(newFrom.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Leave the right side blank to just teach spelling; fill it in to replace a specific mishearing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button("Restore Defaults") {
                            store.settings.vocabulary = defaultVocabulary
                        }
                    }
                }
                .padding(8)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Output

private struct OutputTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            GroupBox("Output") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Output mode", selection: $store.settings.outputMode) {
                        ForEach(OutputMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    if store.settings.outputMode == .pasteAtCursor {
                        Toggle("Keep transcript on clipboard after paste", isOn: $store.settings.keepOnClipboardAfterPaste)
                    }
                    Toggle("Save audio recordings", isOn: $store.settings.saveAudio)
                    Toggle("Play sound when recording starts/stops", isOn: $store.settings.soundEffectsEnabled)

                    Divider()

                    Picker("Sound", selection: $store.settings.soundSet) {
                        ForEach(SoundSet.allCases) { set in
                            Text(set.displayName).tag(set)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Start") {
                            SoundPlayer.preview(.start, set: store.settings.soundSet)
                        }
                        Button("Stop") {
                            SoundPlayer.preview(.stop, set: store.settings.soundSet)
                        }
                        Button("Error") {
                            SoundPlayer.preview(.error, set: store.settings.soundSet)
                        }
                        Spacer()
                    }
                }
                .padding(8)
            }

            GroupBox("Recordings") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Save location") {
                        HStack {
                            Text(store.settings.recordingsDirectory ?? HistoryStore.directory.appendingPathComponent("audio").path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Button("Browse…") { chooseFolder() }
                            if store.settings.recordingsDirectory != nil {
                                Button("Restore Default") { store.settings.recordingsDirectory = nil }
                            }
                        }
                    }
                    Picker("Keep recordings for", selection: $store.settings.recordingRetention) {
                        ForEach(RecordingRetention.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Pill Position") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Placement", selection: $store.settings.pillPlacement) {
                        ForEach(PillPlacement.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                Text("Drag near an edge or corner to magnet-snap like SuperWhisper. Drop in the middle to keep Custom.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    Picker("Style", selection: $store.settings.pillStyle) {
                        ForEach(PillStyle.allCases) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    Toggle("Always show (even when idle)", isOn: $store.settings.pillAlwaysShow)
                    HStack {
                        Text("Size")
                        Slider(value: $store.settings.pillScale, in: 0.6...1.6, step: 0.05)
                        Text("\(Int(store.settings.pillScale * 100))%")
                            .frame(width: 44, alignment: .trailing)
                            .monospacedDigit()
                        Button("Reset") { store.settings.pillScale = 1.0 }
                    }
                }
                .padding(8)
            }

            GroupBox("While Recording") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Other audio playback", selection: $store.settings.playbackDuckMode) {
                        ForEach(PlaybackDuckMode.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Application") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Launch at login", isOn: $store.settings.launchAtLogin)
                }
                .padding(8)
            }
        }
        .padding(.top, 8)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.recordingsDirectory = url.path
        }
    }
}

// MARK: - Hotkey

private struct HotkeyTab: View {
    @ObservedObject var store: SettingsStore
    @State private var isRecording = false
    @State private var recordingStyle: HotkeyTriggerStyle = .hold
    @State private var mouseButtonSelection: Int = 2
    @State private var keyMonitor: Any?

    var body: some View {
        Form {
            GroupBox("Current Bindings") {
                VStack(alignment: .leading, spacing: 6) {
                    if store.settings.bindings.isEmpty {
                        Text("No bindings configured").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(store.settings.bindings.enumerated()), id: \.offset) { index, binding in
                            HStack {
                                Text(description(for: binding))
                                Spacer()
                                Button(role: .destructive) {
                                    removeBinding(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Add Binding") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Trigger style", selection: $recordingStyle) {
                        Text("Hold").tag(HotkeyTriggerStyle.hold)
                        Text("Toggle").tag(HotkeyTriggerStyle.toggle)
                    }
                    .pickerStyle(.segmented)

                    Button(isRecording ? "Press any key…" : "Record shortcut") {
                        startRecording()
                    }
                    .disabled(isRecording)

                    Divider()

                    Text("Common defaults").font(.caption).foregroundStyle(.secondary)

                    Button("Use Fn key (default)") {
                        addBinding(HotkeyBinding(kind: .fnKey, keyCode: nil, modifiers: nil, mouseButton: nil, style: recordingStyle))
                    }

                    let modifierPresets: [(String, UInt16)] = [
                        ("Right Command", 54), ("Left Command", 55),
                        ("Right Option", 61), ("Left Option", 58),
                        ("Right Control", 62), ("Right Shift", 60),
                    ]
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(modifierPresets, id: \.1) { name, code in
                            Button("Use \(name)") {
                                addBinding(HotkeyBinding(kind: .keyCombo, keyCode: code, modifiers: 0, mouseButton: nil, style: recordingStyle))
                            }
                        }
                    }

                    HStack {
                        Text("Mouse button")
                        Picker("", selection: $mouseButtonSelection) {
                            Text("Middle").tag(2)
                            Text("Mouse4").tag(3)
                            Text("Mouse5").tag(4)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        Button("Use") {
                            addBinding(HotkeyBinding(kind: .mouseButton, keyCode: nil, modifiers: nil, mouseButton: mouseButtonSelection, style: recordingStyle))
                        }
                    }

                    HStack {
                        Text("Hold threshold (right-click)")
                        Slider(value: $store.settings.rightClickHoldThresholdMs, in: 100...2000, step: 50)
                        Text("\(String(format: "%.1f", store.settings.rightClickHoldThresholdMs / 1000))s")
                            .frame(width: 48, alignment: .trailing)
                            .monospacedDigit()
                    }
                    Button("Use Right-Click (hold)") {
                        addBinding(HotkeyBinding(kind: .rightClick, keyCode: nil, modifiers: nil, mouseButton: nil, style: .hold))
                    }
                    Text("A quick right-click still opens the context menu; holding past the threshold starts recording instead. macOS may briefly flash the context menu before the hold is recognized — this is a platform limitation of global event monitors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
        }
        .padding(.top, 8)
    }

    private func startRecording() {
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // Modifier-only keys (Right Command, Right Option, etc.) never
                // send keyDown — only flagsChanged — so capture them here.
                guard let side = ModifierOnlyKeys.side(for: event.keyCode) else { return event }
                guard event.modifierFlags.contains(side.nsFlag) else { return event } // fire on press, not release
                let binding = HotkeyBinding(
                    kind: .keyCombo,
                    keyCode: event.keyCode,
                    modifiers: 0,
                    mouseButton: nil,
                    style: recordingStyle
                )
                addBinding(binding)
                stopRecording()
                return nil
            }

            let binding = HotkeyBinding(
                kind: .keyCombo,
                keyCode: event.keyCode,
                modifiers: UInt64(event.modifierFlags.rawValue),
                mouseButton: nil,
                style: recordingStyle
            )
            addBinding(binding)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func addBinding(_ binding: HotkeyBinding) {
        store.settings.bindings.append(binding)
    }

    private func removeBinding(at index: Int) {
        store.settings.bindings.remove(at: index)
    }

    private func description(for binding: HotkeyBinding) -> String {
        switch binding.kind {
        case .fnKey:
            return "Fn key (\(binding.style.rawValue))"
        case .keyCombo:
            if let code = binding.keyCode, let modName = ModifierOnlyKeys.displayName(for: code) {
                return "\(modName) (\(binding.style.rawValue))"
            }
            var parts: [String] = []
            let flags = NSEvent.ModifierFlags(rawValue: UInt(binding.modifiers ?? 0))
            if flags.contains(.control) { parts.append("⌃") }
            if flags.contains(.option) { parts.append("⌥") }
            if flags.contains(.shift) { parts.append("⇧") }
            if flags.contains(.command) { parts.append("⌘") }
            parts.append(keyName(for: binding.keyCode ?? 0))
            return "\(parts.joined()) (\(binding.style.rawValue))"
        case .mouseButton:
            let name: String
            switch binding.mouseButton {
            case 2: name = "Middle button"
            case 3: name = "Mouse4"
            case 4: name = "Mouse5"
            default: name = "Button \(binding.mouseButton ?? -1)"
            }
            return "\(name) (\(binding.style.rawValue))"
        case .rightClick:
            return "Right-Click hold (\(binding.style.rawValue))"
        }
    }

    private func keyName(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
            34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
            35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
            13: "W", 7: "X", 16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
            26: "7", 28: "8", 25: "9",
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

/// Dropdown fed by the provider's live /models endpoint; falls back to a
/// free-text field until the list loads (no key, offline, etc.). Current
/// value is always selectable even if the provider no longer lists it.
private struct ModelPicker: View {
    let label: String
    let provider: ModelCatalog.Provider
    @Binding var selection: String
    @ObservedObject private var catalog = ModelCatalog.shared

    private var isPullingThis: Bool { catalog.pullingOllamaModel == selection }

    var body: some View {
        LabeledContent(label) {
            HStack {
                if let list = catalog.models[provider], !list.isEmpty {
                    Picker("", selection: $selection) {
                        if !list.contains(selection) { Text(selection).tag(selection) }
                        ForEach(list, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                } else {
                    TextField("", text: $selection).textFieldStyle(.roundedBorder)
                }

                if provider == .ollama {
                    if catalog.isOllamaModelInstalled(selection) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if let bytes = catalog.ollamaModelSizes[selection] {
                            Text(ModelCatalog.formattedSize(bytes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if isPullingThis {
                        ProgressView().controlSize(.small)
                        Text(catalog.pullProgress).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Download") {
                            Task { await catalog.pullOllamaModel(selection) }
                        }
                        .disabled(catalog.pullingOllamaModel != nil || selection.isEmpty)
                        .help("Not installed locally — pull it via Ollama before selecting")
                    }
                }
            }
        }
    }
}
