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

            OutputTab(store: store)
                .tabItem { Label("Output", systemImage: "square.and.arrow.up") }

            HotkeyTab(store: store)
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
        }
        .padding(20)
        .frame(width: 560)
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

private struct ProvidersTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            GroupBox("Speech-to-Text") {
                Picker("STT Provider", selection: $store.settings.sttProvider) {
                    ForEach(STTProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .padding(8)
            }

            GroupBox("Cleanup Provider") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Cleanup Provider", selection: $store.settings.cleanupProvider) {
                        ForEach(CleanupProviderKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    Divider()
                    Text("Model overrides").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Gemini model") {
                        TextField("", text: $store.settings.geminiModel).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Groq cleanup model") {
                        TextField("", text: $store.settings.groqCleanupModel).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Cerebras model") {
                        TextField("", text: $store.settings.cerebrasModel).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("OpenAI cleanup model") {
                        TextField("", text: $store.settings.openAICleanupModel).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Ollama model") {
                        TextField("", text: $store.settings.ollamaModel).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Ollama base URL") {
                        TextField("", text: $store.settings.ollamaBaseURL).textFieldStyle(.roundedBorder)
                    }
                }
                .padding(8)
            }
        }
        .padding(.top, 8)
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
                    Toggle("Save audio recordings", isOn: $store.settings.saveAudio)
                }
                .padding(8)
            }
        }
        .padding(.top, 8)
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

                    Button("Use Fn key (default)") {
                        addBinding(HotkeyBinding(kind: .fnKey, keyCode: nil, modifiers: nil, mouseButton: nil, style: recordingStyle))
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
                }
                .padding(8)
            }
        }
        .padding(.top, 8)
    }

    private func startRecording() {
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
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
            let code = binding.keyCode.map(String.init) ?? "?"
            return "Key combo (code \(code), \(binding.style.rawValue))"
        case .mouseButton:
            let name: String
            switch binding.mouseButton {
            case 2: name = "Middle button"
            case 3: name = "Mouse4"
            case 4: name = "Mouse5"
            default: name = "Button \(binding.mouseButton ?? -1)"
            }
            return "\(name) (\(binding.style.rawValue))"
        }
    }
}
