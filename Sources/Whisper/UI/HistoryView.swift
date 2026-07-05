import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var store = HistoryStore.shared
    @State private var showRaw = false
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if store.entries.isEmpty {
                Spacer()
                Text("No history yet")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(store.entries) { entry in
                    HistoryRow(entry: entry, showRaw: showRaw)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private var toolbar: some View {
        HStack {
            Toggle("Show raw", isOn: $showRaw)
            Spacer()
            Button("Clear history", role: .destructive) {
                showClearConfirm = true
            }
            .disabled(store.entries.isEmpty)
        }
        .padding(10)
        .confirmationDialog(
            "Clear all history?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                store.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let showRaw: Bool

    private var displayText: String {
        if showRaw {
            return entry.rawText
        }
        return entry.cleanedText ?? entry.rawText
    }

    private var isFallbackRaw: Bool {
        !showRaw && entry.cleanedText == nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let appName = entry.appName {
                        Text(appName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if isFallbackRaw {
                        Text("raw")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                Text(displayText)
                    .font(.body)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                copyToClipboard(displayText)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
