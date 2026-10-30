import Foundation
import Combine

// MARK: - Connection State

enum WebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)

    var isLive: Bool { self == .connected }

    var displayLabel: String {
        switch self {
        case .connected:          return "Live"
        case .connecting:         return "Connecting..."
        case .reconnecting:       return "Reconnecting..."
        case .disconnected:       return "Offline"
        }
    }
}

// MARK: - Domain Events

/// All possible events the WebSocket layer can emit to the rest of the app.
/// New event types are added here first — the rest of the app remains unaware
/// of the raw wire format.
enum WebSocketEvent {
    case submissionVerdict(submission: Submission)
    case ratingUpdate(handle: String, newRating: Int)
    case connectionStateChanged(WebSocketConnectionState)
    case error(Error)
}

// MARK: - Wire Envelope

/// Raw JSON envelope that arrives over the wire. The `event` field is a
/// discriminator; `payload` is re-decoded based on that discriminator.
struct WebSocketEnvelope: Decodable {
    let event: String
    let payload: PayloadContainer?

    struct PayloadContainer: Decodable {
        // Submission verdict fields
        let submission: Submission?
        // Rating update fields
        let handle: String?
        let newRating: Int?
    }
}

// MARK: - Protocol

protocol WebSocketServiceProtocol: AnyObject {
    /// Multicast publisher of domain-level WebSocket events.
    var events: AnyPublisher<WebSocketEvent, Never> { get }
    /// Current connection state as a publisher.
    var connectionState: AnyPublisher<WebSocketConnectionState, Never> { get }
    /// Current connection state as a synchronous value (for initial binding).
    var currentState: WebSocketConnectionState { get }

    func connect(to url: URL)
    func disconnect()
    func send(_ message: String) async throws
}
