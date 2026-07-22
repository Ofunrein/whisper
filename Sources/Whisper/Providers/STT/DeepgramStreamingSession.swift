import Foundation

private final class StreamingWebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    enum State {
        case connecting
        case open
        case failed(Error)
    }

    private let lock = NSLock()
    private var state: State = .connecting

    func snapshot() -> State {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        lock.lock(); state = .open; lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        lock.lock()
        if case .connecting = state { state = .failed(error) }
        lock.unlock()
    }
}

final class DeepgramStreamingSession: @unchecked Sendable {
    struct ResultFrame: Equatable {
        let transcript: String
        let isFinal: Bool
        let speechFinal: Bool
    }

    private let lock = NSLock()
    private let audioStream: AsyncStream<Data>
    private let audioContinuation: AsyncStream<Data>.Continuation
    private var task: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var finalSegments: [String] = []
    private var latestInterim = ""
    private var speechFinal = false
    private var failure: Error?
    private let keyterms: [String]

    init(keyterms: [String] = []) {
        self.keyterms = keyterms
        var continuation: AsyncStream<Data>.Continuation!
        audioStream = AsyncStream<Data> { continuation = $0 }
        audioContinuation = continuation
    }

    func start() {
        task = Task(priority: .userInitiated) { [weak self] in
            await self?.run()
        }
    }

    func push(_ chunk: Data) {
        audioContinuation.yield(chunk)
    }

    func finish() async throws -> String {
        audioContinuation.finish()
        await task?.value
        let (error, transcript, interim) = snapshot()
        let result = transcript.isEmpty ? interim : transcript
        // Deepgram normally closes the socket immediately after CloseStream.
        // URLSession can surface that normal close as an error after the final
        // Results frame arrived. Keep the usable streaming transcript instead
        // of discarding it and paying for a slow batch retry.
        if !result.isEmpty { return result }
        if let error { throw error }
        throw ProviderError.badResponse("Deepgram stream returned no transcript")
    }

    func cancel() {
        audioContinuation.finish()
        task?.cancel()
        cancelSocket()
    }

    private func run() async {
        guard let key = Keychain.get(Keychain.deepgramKey), !key.isEmpty else {
            setFailure(ProviderError.missingKey("Deepgram"))
            return
        }

        let url = Self.url(keyterms: keyterms)
        let delegate = StreamingWebSocketDelegate()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let webSocket = session.webSocketTask(with: url, protocols: ["token", key])
        setSocket(webSocket, session: session)
        webSocket.resume()

        do {
            try await waitUntilOpen(delegate)
        } catch {
            setFailure(error)
            webSocket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            setSocket(nil, session: nil)
            return
        }

        let receiver = Task { [weak self] in
            await self?.receiveLoop(webSocket)
        }

        do {
            for await chunk in audioStream {
                try Task.checkCancellation()
                try await webSocket.send(.data(chunk))
            }
            let closeState = prepareForClose()
            let closeSentAt = Date()
            try await webSocket.send(.string("{\"type\":\"CloseStream\"}"))

            let deadline = Date().addingTimeInterval(1.5)
            while Date() < deadline, !Task.isCancelled {
                if resultIsReady(after: closeState, closeSentAt: closeSentAt) { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        } catch is CancellationError {
        } catch {
            setFailure(error)
        }

        receiver.cancel()
        webSocket.cancel(with: .normalClosure, reason: nil)
        session.finishTasksAndInvalidate()
        setSocket(nil, session: nil)
    }

    static func url(keyterms: [String]) -> URL {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "endpointing", value: "250"),
        ] + keyterms.prefix(100).map { URLQueryItem(name: "keyterm", value: $0) }
        return components.url!
    }

    private func receiveLoop(_ webSocket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await webSocket.receive()
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: continue
                }
                consume(data)
            } catch {
                if !Task.isCancelled { setFailure(error) }
                return
            }
        }
    }

    private func consume(_ data: Data) {
        guard let frame = Self.parseResult(data) else { return }
        lock.lock()
        if frame.isFinal {
            finalSegments.append(frame.transcript)
            latestInterim = ""
        } else {
            latestInterim = frame.transcript
        }
        if frame.speechFinal { speechFinal = true }
        lock.unlock()
    }

    static func parseResult(_ data: Data) -> ResultFrame? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "Results",
              let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let transcript = alternatives.first?["transcript"] as? String else { return nil }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ResultFrame(
            transcript: trimmed,
            isFinal: json["is_final"] as? Bool == true,
            speechFinal: json["speech_final"] as? Bool == true
        )
    }

    private func setFailure(_ error: Error) {
        lock.lock()
        if failure == nil { failure = error }
        lock.unlock()
    }

    private func snapshot() -> (Error?, String, String) {
        lock.lock(); defer { lock.unlock() }
        return (
            failure,
            finalSegments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            latestInterim.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func prepareForClose() -> (finalCount: Int, hadInterim: Bool) {
        lock.lock(); defer { lock.unlock() }
        speechFinal = false
        return (finalSegments.count, !latestInterim.isEmpty)
    }

    private func resultIsReady(
        after state: (finalCount: Int, hadInterim: Bool),
        closeSentAt: Date
    ) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if speechFinal || finalSegments.count > state.finalCount { return true }
        return !state.hadInterim
            && !finalSegments.isEmpty
            && Date().timeIntervalSince(closeSentAt) >= 0.25
    }

    private func setSocket(_ value: URLSessionWebSocketTask?, session: URLSession?) {
        lock.lock()
        socket = value
        urlSession = session
        lock.unlock()
    }

    private func cancelSocket() {
        lock.lock()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        lock.unlock()
    }

    private func waitUntilOpen(_ delegate: StreamingWebSocketDelegate) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !Task.isCancelled {
            switch delegate.snapshot() {
            case .open: return
            case .failed(let error): throw error
            case .connecting: break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw ProviderError.timeout
    }
}
