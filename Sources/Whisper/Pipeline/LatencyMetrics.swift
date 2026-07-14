import Foundation

struct DictationLatency: Codable, Equatable {
    let date: Date
    let provider: String
    let transport: String
    let words: Int
    let sttMs: Double
    let cleanupMs: Double
    let pasteMs: Double
    let releaseToPasteMs: Double
}

actor LatencyMetrics {
    static let shared = LatencyMetrics()

    private let url: URL
    private var samples: [DictationLatency]
    private let maxSamples = 500

    init(directory: URL = HistoryStore.directory) {
        url = directory.appendingPathComponent("latency.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([DictationLatency].self, from: data) {
            samples = Array(decoded.suffix(maxSamples))
        } else {
            samples = []
        }
    }

    func record(_ sample: DictationLatency) {
        samples.append(sample)
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        if let data = try? JSONEncoder().encode(samples) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }

        let totals = samples.suffix(100).map(\.releaseToPasteMs)
        NSLog(
            "Whisper: latency release-to-paste %.0fms (p50 %.0fms, p95 %.0fms, n %d)",
            sample.releaseToPasteMs,
            Self.percentile(totals, 0.50),
            Self.percentile(totals, 0.95),
            totals.count
        )
    }

    static func percentile(_ values: [Double], _ quantile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(ceil(Double(sorted.count) * min(max(quantile, 0), 1))) - 1
        return sorted[max(0, min(index, sorted.count - 1))]
    }
}
