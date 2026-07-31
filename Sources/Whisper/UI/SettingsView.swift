import SwiftUI
import AppKit

/// Reports a tab's natural content height so the window can snap to it.
/// macOS's SwiftUI TabView is inconsistent across versions about whether it
/// lays out only the selected tab or all tabs at once — `reduce` takes the
/// max, and each tab only reports its real height when selected (0
/// otherwise), so the result is always the *selected* tab's height
/// regardless of which layout behavior is actually happening under the hood.
private struct TabHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MeasuredTabContent<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder let content: Content
    var body: some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(key: TabHeightKey.self, value: isSelected ? proxy.size.height : 0)
            }
        )
    }
}

private enum SettingsTab: Hashable {
    case apiKeys, providers, cleanup, vocabulary, output, hotkey
}

struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var selectedTab: SettingsTab = .apiKeys

    /// Called with the currently-selected tab's ideal content height whenever
    /// it changes (tab switch, or content within a tab growing/shrinking).
    /// WindowPresenter uses this to snap the window to fit — so switching to
    /// a short tab shrinks the window back down instead of staying stuck at
    /// the tallest tab ever visited (a known SwiftUI TabView-on-macOS quirk).
    var onIdealHeightChange: ((CGFloat) -> Void)?

    var body: some View {
        TabView(selection: $selectedTab) {
            MeasuredTabContent(isSelected: selectedTab == .apiKeys) { APIKeysTab() }
                .tabItem { Label("API Keys", systemImage: "key.fill") }
                .tag(SettingsTab.apiKeys)

            MeasuredTabContent(isSelected: selectedTab == .providers) { ProvidersTab(store: store) }
                .tabItem { Label("Providers", systemImage: "cpu") }
                .tag(SettingsTab.providers)

            MeasuredTabContent(isSelected: selectedTab == .cleanup) { CleanupTab(store: store) }
                .tabItem { Label("Cleanup", systemImage: "wand.and.stars") }
                .tag(SettingsTab.cleanup)

            MeasuredTabContent(isSelected: selectedTab == .vocabulary) { VocabularyTab(store: store) }
                .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }
                .tag(SettingsTab.vocabulary)

            MeasuredTabContent(isSelected: selectedTab == .output) { OutputTab(store: store) }
                .tabItem { Label("Output", systemImage: "square.and.arrow.up") }
                .tag(SettingsTab.output)

            MeasuredTabContent(isSelected: selectedTab == .hotkey) { HotkeyTab(store: store) }
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
                .tag(SettingsTab.hotkey)
        }
        .padding(20)
        .frame(width: 560)
        .onPreferenceChange(TabHeightKey.self) { height in
            // Add back the outer padding (20 top + 20 bottom) and an
            // allowance for the tab bar chrome NSTabView draws above the
            // content, neither of which the inner GeometryReader can see.
            onIdealHeightChange?(height + 40 + 38)
        }
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
    @State private var anthropic: String = ""
    @State private var pendingClear: (title: String, text: Binding<String>, account: String)? = nil
    @State private var revealed: Set<String> = []

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
                    keyRow("Claude", text: $anthropic, account: Keychain.anthropicKey)
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
            Group {
                if revealed.contains(account) {
                    TextField("API key", text: text)
                } else {
                    SecureField("API key", text: text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .onChange(of: text.wrappedValue) { _, newValue in
                Keychain.set(newValue, for: account)
            }
            Button {
                if revealed.contains(account) {
                    revealed.remove(account)
                } else {
                    revealed.insert(account)
                }
            } label: {
                Image(systemName: revealed.contains(account) ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .disabled(text.wrappedValue.isEmpty)
            .help(revealed.contains(account) ? "Hide \(title) key" : "Show \(title) key")
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
        anthropic = Keychain.get(Keychain.anthropicKey) ?? ""
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

                    HStack {
                        Text("STT deadline")
                        Slider(
                            value: Binding(
                                get: { store.settings.effectiveSTTTimeoutSeconds },
                                set: { store.settings.sttTimeoutSeconds = $0 }
                            ),
                            in: 3...20,
                            step: 1
                        )
                        Text("\(Int(store.settings.effectiveSTTTimeoutSeconds))s")
                            .frame(width: 32, alignment: .trailing)
                            .monospacedDigit()
                    }
                    Text("On failure or timeout, Whisper tries configured cloud backups: Deepgram, Groq, ElevenLabs, then OpenAI.")
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
                    activeCleanupModelPicker

                    HStack {
                        Spacer()
                        Button("Restore Model Defaults") { restoreModelDefaults() }
                    }
                }
                .padding(8)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var activeCleanupModelPicker: some View {
        switch store.settings.cleanupProvider {
        case .gemini:
            ModelPicker(label: "Gemini model", provider: .gemini, selection: $store.settings.geminiModel)
        case .groq:
            ModelPicker(label: "Groq cleanup model", provider: .groq, selection: $store.settings.groqCleanupModel)
        case .cerebras:
            ModelPicker(label: "Cerebras model", provider: .cerebras, selection: $store.settings.cerebrasModel)
        case .openAI:
            ModelPicker(label: "OpenAI cleanup model", provider: .openAI, selection: $store.settings.openAICleanupModel)
        case .anthropic:
            ModelPicker(label: "Claude model", provider: .anthropic, selection: $store.settings.anthropicModel)
        case .ollama:
            ModelPicker(label: "Ollama model", provider: .ollama, selection: $store.settings.ollamaModel)
        }
    }

    private func restoreModelDefaults() {
        store.settings.geminiModel = AppSettings.defaultGeminiModel
        store.settings.groqCleanupModel = AppSettings.defaultGroqCleanupModel
        store.settings.cerebrasModel = AppSettings.defaultCerebrasModel
        store.settings.openAICleanupModel = AppSettings.defaultOpenAICleanupModel
        store.settings.anthropicModel = AppSettings.defaultAnthropicCleanupModel
        store.settings.ollamaModel = AppSettings.defaultOllamaModel
        store.settings.ollamaBaseURL = AppSettings.defaultOllamaBaseURL
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
                        Text("Max cleanup time")
                        Slider(value: $store.settings.cleanupTimeoutSeconds, in: 3...15, step: 1)
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

    private func fromBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { store.settings.vocabulary[index].from },
            set: { store.settings.vocabulary[index].from = $0 }
        )
    }

    /// Empty text = plain vocabulary word (known term); non-empty = replacement pair.
    private func toBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { store.settings.vocabulary[index].to ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                store.settings.vocabulary[index].to = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

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
                        // Scrolls internally with a capped height instead of
                        // stacking every row full-height — otherwise this
                        // list (already 26+ entries) would make the tab, and
                        // therefore the window, grow without bound as more
                        // vocabulary is added.
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(store.settings.vocabulary.enumerated()), id: \.element.id) { index, entry in
                                    HStack(spacing: 6) {
                                        TextField("Word or phrase", text: fromBinding(index), axis: .vertical)
                                            .textFieldStyle(.roundedBorder)
                                            .lineLimit(1...4)
                                            .frame(minWidth: 200)
                                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                        TextField("(known term)", text: toBinding(index), axis: .vertical)
                                            .textFieldStyle(.roundedBorder)
                                            .lineLimit(1...4)
                                            .frame(minWidth: 200)
                                        Button(role: .destructive) {
                                            store.settings.vocabulary.remove(at: index)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 260)
                    }

                    Divider()

                    HStack {
                        TextField("Word or misheard phrase", text: $newFrom, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .frame(minWidth: 200)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Correct spelling (optional)", text: $newTo, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .frame(minWidth: 200)
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

    private var recordSystemAudioBinding: Binding<Bool> {
        Binding(
            get: { store.settings.recordSystemAudio ?? false },
            set: { store.settings.recordSystemAudio = $0 }
        )
    }

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

                    if #available(macOS 14.2, *) {
                        Toggle("Also record system audio", isOn: recordSystemAudioBinding)
                        Text("Mixes in whatever is playing through speakers/headphones (e.g. a call) alongside the mic. Off by default. macOS will ask you to approve this the first time you use it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("Also record system audio", isOn: .constant(false))
                            .disabled(true)
                        Text("Requires macOS 14.2 or later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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

/// A small keycap-style glyph representing one physical key or mouse button in
/// a binding, so bindings read as "what you'd see on the keyboard/mouse"
/// rather than as plain text abbreviations.
private struct Keycap: View {
    private let text: String?
    private let systemImage: String?
    private let badge: String?
    private let tint: Color

    init(_ text: String, badge: String? = nil, tint: Color = .primary) {
        self.text = text
        self.systemImage = nil
        self.badge = badge
        self.tint = tint
    }

    init(systemImage: String, badge: String? = nil, tint: Color = .primary) {
        self.text = nil
        self.systemImage = systemImage
        self.badge = badge
        self.tint = tint
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else if let text {
                    Text(text)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(minWidth: 24, minHeight: 20)
            .padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(tint.opacity(0.35), lineWidth: 1))

            if let badge {
                Text(badge)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .frame(minWidth: 12, minHeight: 12)
                    .background(Circle().fill(tint))
                    .offset(x: 5, y: 5)
            }
        }
    }
}

/// Hold vs. toggle indicator, same visual language as ProviderBadge above.
private struct TriggerBadge: View {
    let style: HotkeyTriggerStyle

    var body: some View {
        Label(style == .hold ? "Hold" : "Toggle", systemImage: style == .hold ? "hand.tap.fill" : "arrow.left.arrow.right.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(style == .hold ? .orange : .purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((style == .hold ? Color.orange : Color.purple).opacity(0.14))
            .clipShape(Capsule())
    }
}

private struct HotkeyTab: View {
    @ObservedObject var store: SettingsStore
    @State private var isRecording = false
    @State private var recordingStyle: HotkeyTriggerStyle = .hold
    @State private var mouseButtonSelection: Int = 2
    @State private var keyMonitor: Any?

    private let modifierPresets: [(name: String, code: UInt16)] = [
        ("Right Command", 54), ("Left Command", 55),
        ("Right Option", 61), ("Left Option", 58),
        ("Right Control", 62), ("Right Shift", 60),
    ]

    var body: some View {
        Form {
            GroupBox("Current Bindings") {
                VStack(alignment: .leading, spacing: 10) {
                    if store.settings.bindings.isEmpty {
                        Text("No bindings configured").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(store.settings.bindings.enumerated()), id: \.offset) { index, binding in
                            HStack(spacing: 10) {
                                glyphs(for: binding)
                                VStack(alignment: .leading, spacing: 2) {
                                    TextField(description(for: binding), text: nameBinding(index))
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13, weight: .medium))
                                    if let name = binding.name, !name.isEmpty {
                                        Text(description(for: binding))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                TriggerBadge(style: binding.style)
                                Button(role: .destructive) {
                                    removeBinding(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
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

                    presetButton(glyph: Keycap("fn", tint: .purple), label: "Use Fn key (default)") {
                        addBinding(HotkeyBinding(kind: .fnKey, keyCode: nil, modifiers: nil, mouseButton: nil, style: recordingStyle))
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(modifierPresets, id: \.code) { preset in
                            presetButton(glyph: modifierKeycap(for: preset.code), label: "Use \(preset.name)") {
                                addBinding(HotkeyBinding(kind: .keyCombo, keyCode: preset.code, modifiers: 0, mouseButton: nil, style: recordingStyle))
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Picker("Mouse button", selection: $mouseButtonSelection) {
                            Text("Middle").tag(2)
                            Text("Mouse4").tag(3)
                            Text("Mouse5").tag(4)
                        }
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
                    Text("A quick right-click still opens the context menu; holding past the threshold starts recording instead. macOS may briefly flash the context menu before a hold is recognized — a platform limitation of global event monitors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func presetButton(glyph: Keycap, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                glyph
                Text(label)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func glyphs(for binding: HotkeyBinding) -> some View {
        HStack(spacing: 4) {
            switch binding.kind {
            case .fnKey:
                Keycap("fn", tint: .purple)
            case .keyCombo:
                if let code = binding.keyCode, ModifierOnlyKeys.side(for: code) != nil {
                    modifierKeycap(for: code)
                } else {
                    let flags = NSEvent.ModifierFlags(rawValue: UInt(binding.modifiers ?? 0))
                    if flags.contains(.control) { Keycap(systemImage: "control", tint: .blue) }
                    if flags.contains(.option) { Keycap(systemImage: "option", tint: .blue) }
                    if flags.contains(.shift) { Keycap(systemImage: "shift", tint: .blue) }
                    if flags.contains(.command) { Keycap(systemImage: "command", tint: .blue) }
                    if let code = binding.keyCode {
                        Keycap(keyName(for: code), tint: .primary)
                    }
                }
            case .mouseButton:
                Keycap(systemImage: "computermouse.fill", badge: mouseBadge(binding.mouseButton), tint: .orange)
            case .rightClick:
                Keycap(systemImage: "computermouse.fill", badge: "R", tint: .orange)
            }
        }
    }

    /// A modifier symbol (⌘/⌥/⌃/⇧) with an L/R corner badge, so "Right Command"
    /// reads as the command glyph specifically marked right, not a bare ⌘.
    private func modifierKeycap(for keyCode: UInt16) -> Keycap {
        guard let side = ModifierOnlyKeys.side(for: keyCode) else {
            return Keycap(keyName(for: keyCode), tint: .primary)
        }
        let symbol: String
        switch side {
        case .command: symbol = "command"
        case .option: symbol = "option"
        case .control: symbol = "control"
        case .shift: symbol = "shift"
        }
        let rightCodes: Set<UInt16> = [54, 61, 62, 60]
        return Keycap(systemImage: symbol, badge: rightCodes.contains(keyCode) ? "R" : "L", tint: .blue)
    }

    private func mouseBadge(_ button: Int?) -> String {
        switch button {
        case 2: return "M"
        case 3: return "4"
        case 4: return "5"
        default: return "?"
        }
    }

    private func nameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard store.settings.bindings.indices.contains(index) else { return "" }
                return store.settings.bindings[index].name ?? ""
            },
            set: { newValue in
                guard store.settings.bindings.indices.contains(index) else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                store.settings.bindings[index].name = trimmed.isEmpty ? nil : trimmed
            }
        )
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
        guard store.settings.bindings.indices.contains(index) else { return }
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

/// Dropdown fed by provider live /models endpoint plus fallback options.
private struct ModelPicker: View {
    let label: String
    let provider: ModelCatalog.Provider
    @Binding var selection: String
    @ObservedObject private var catalog = ModelCatalog.shared

    private var choices: [String] {
        let live = catalog.models[provider] ?? []
        let fallback = Self.fallbackModels[provider] ?? []
        var seen = Set<String>()
        return ([selection] + live + fallback)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private var isPullingThis: Bool { catalog.pullingOllamaModel == selection }

    var body: some View {
        LabeledContent(label) {
            HStack {
                Picker("", selection: $selection) {
                    ForEach(choices, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 420)

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
                        Button("Download") { Task { await catalog.pullOllamaModel(selection) } }
                            .disabled(catalog.pullingOllamaModel != nil || selection.isEmpty)
                            .help("Pull with local Ollama")
                    }
                }
            }
        }
    }

    private static let fallbackModels: [ModelCatalog.Provider: [String]] = [
        .gemini: [
            "gemini-2.5-flash-lite",
            "gemini-2.5-flash",
            "gemini-2.0-flash-lite",
            "gemini-2.0-flash",
            "gemini-1.5-flash",
            "gemini-2.5-pro",
        ],
        .groq: [
            "openai/gpt-oss-20b",
            "openai/gpt-oss-120b",
            "llama-3.1-8b-instant",
            "llama-3.3-70b-versatile",
            "qwen/qwen3-32b",
            "moonshotai/kimi-k2-instruct",
        ],
        .cerebras: [
            "qwen-3-32b",
            "gpt-oss-120b",
            "llama3.1-8b",
            "llama-3.3-70b",
            "qwen-3-235b-a22b-instruct-2507",
        ],
        .openAI: [
            "gpt-4o-mini",
            "gpt-4.1-mini",
            "o4-mini",
            "gpt-4o",
            "gpt-4.1",
        ],
        .anthropic: [
            "claude-haiku-4-5-20251001",
            "claude-sonnet-4-5-20250929",
            "claude-opus-4-5-20251101",
        ],
        .ollama: [
            "llama3.2",
            "llama3.2:1b",
            "llama3.2:3b",
            "llama3.1:8b",
            "qwen2.5:3b",
            "qwen2.5:7b",
            "gemma3:1b",
            "gemma3:4b",
            "mistral:7b",
            "phi3:mini",
        ],
    ]
}
