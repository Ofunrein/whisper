import SwiftUI

/// The "something is happening" window shown during a self-update.
///
/// Deliberately small and non-interactive: the update can't be meaningfully
/// cancelled partway through an install, so this reports rather than asks.
struct UpdateProgressView: View {
    @ObservedObject var model: UpdateProgressModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Updating Whisper to \(model.versionLabel)")
                .font(.headline)

            // Determinate while downloading, indeterminate for the short
            // mount/install/relaunch phases where there's no byte count.
            if let fraction = model.phase.fractionCompleted {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            HStack(spacing: 6) {
                Text(model.phase.title)
                    .font(.subheadline)
                Spacer()
                if let detail = model.phase.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Text("Whisper will restart automatically when the update finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
    }
}
