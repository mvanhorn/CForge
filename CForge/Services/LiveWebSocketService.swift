import Foundation
import Combine

// MARK: - LiveWebSocketService

/// Concrete WebSocket implementation backed by `URLSessionWebSocketTask`.
///
/// Key design decisions:
/// - Uses a recursive `.receive()` loop (URLSessionWebSocketTask requires re-arming after each message)
/// - Exponential backoff reconnect (2^attempt seconds, capped at 5 attempts)
/// - 30-second ping/pong loop to detect silent connection drops
/// - All socket callbacks are dispatched to a serial background queue to avoid blocking
/// - Events are published on the main scheduler via the PassthroughSubject
final class LiveWebSocketService: NSObject, WebSocketServiceProtocol {

    // MARK: - Publishers

    private let eventSubject = PassthroughSubject<WebSocketEvent, Never>()
    private let stateSubject = CurrentValueSubject<WebSocketConnectionState, Never>(.disconnected)

    var events: AnyPublisher<WebSocketEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    var connectionState: AnyPublisher<WebSocketConnectionState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var currentState: WebSocketConnectionState {
        stateSubject.value
    }

    // MARK: - Internal State

    private var webSocketTask: URLSessionWebSocketTask?
    private var activeURL: URL?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - Connection Lifecycle

    func connect(to url: URL) {
        guard stateSubject.value == .disconnected else {
            AppLog.debug("WS: Already connected or connecting — ignoring connect(to:)", category: .network)
            return
        }
        activeURL = url
        openConnection(to: url)
    }

    private func openConnection(to url: URL) {
        AppLog.debug("WS: Connecting to \(url)", category: .network)
        stateSubject.send(.connecting)
        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()
        beginListening()
        startPingLoop()
    }

    func disconnect() {
        AppLog.debug("WS: Disconnecting", category: .network)
        cancelSupportTasks()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        stateSubject.send(.disconnected)
        reconnectAttempts = 0
        activeURL = nil
    }

    func send(_ message: String) async throws {
        guard let task = webSocketTask else {
            throw NetworkError.transportError(
                wrapped: NSError(domain: "WebSocket", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: "Not connected"])
            )
        }
        try await task.send(.string(message))
    }

    // MARK: - Recursive Listen Loop
    //
    // URLSessionWebSocketTask does NOT auto-repeat receive — you must call
    // .receive() again after each successful message. This recursive pattern
    // is the correct idiomatic approach (not a while loop, which would block).

    private func beginListening() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handle(message: message)
                self.beginListening() // Re-arm for next message
            case .failure(let error):
                AppLog.error("WS: Receive error — \(error.localizedDescription)", category: .network)
                self.handleConnectionLoss(error: error)
            }
        }
    }

    // MARK: - Message Parsing

    private func handle(message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            guard let d = text.data(using: .utf8) else { return }
            data = d
        case .data(let d):
            data = d
        @unknown default:
            return
        }

        guard let envelope = try? JSONDecoder().decode(WebSocketEnvelope.self, from: data) else {
            AppLog.debug("WS: Could not decode envelope", category: .network)
            return
        }

        dispatch(envelope: envelope)
    }

    private func dispatch(envelope: WebSocketEnvelope) {
        switch envelope.event {
        case "submission_verdict":
            if let submission = envelope.payload?.submission {
                eventSubject.send(.submissionVerdict(submission: submission))
            }
        case "rating_update":
            if let handle = envelope.payload?.handle, let rating = envelope.payload?.newRating {
                eventSubject.send(.ratingUpdate(handle: handle, newRating: rating))
            }
        default:
            AppLog.debug("WS: Unknown event type '\(envelope.event)'", category: .network)
        }
    }

    // MARK: - Reconnect with Exponential Backoff

    private func handleConnectionLoss(error: Error) {
        cancelSupportTasks()
        webSocketTask = nil

        guard reconnectAttempts < maxReconnectAttempts, let url = activeURL else {
            AppLog.error("WS: Max reconnect attempts reached or no active URL", category: .network)
            stateSubject.send(.disconnected)
            eventSubject.send(.error(error))
            return
        }

        reconnectAttempts += 1
        let delaySeconds = pow(2.0, Double(reconnectAttempts)) // 2, 4, 8, 16, 32
        AppLog.debug("WS: Reconnecting in \(Int(delaySeconds))s (attempt \(reconnectAttempts))", category: .network)

        stateSubject.send(.reconnecting(attempt: reconnectAttempts))

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.openConnection(to: url)
        }
    }

    // MARK: - Ping Loop (keep-alive)

    private func startPingLoop() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard !Task.isCancelled else { break }
                self?.webSocketTask?.sendPing { error in
                    if let error {
                        AppLog.error("WS: Ping failed — \(error.localizedDescription)", category: .network)
                        self?.handleConnectionLoss(error: error)
                    }
                }
            }
        }
    }

    private func cancelSupportTasks() {
        pingTask?.cancel()
        pingTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
    }
}

// MARK: - URLSessionWebSocketDelegate

extension LiveWebSocketService: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        AppLog.debug("WS: Connection opened", category: .network)
        reconnectAttempts = 0
        stateSubject.send(.connected)
        eventSubject.send(.connectionStateChanged(.connected))
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        AppLog.debug("WS: Connection closed — code: \(closeCode.rawValue), reason: \(reasonStr)", category: .network)
        stateSubject.send(.disconnected)
        eventSubject.send(.connectionStateChanged(.disconnected))
    }
}
