import SwiftUI

// MARK: - ConnectionStatusPill
//
// A compact nav-bar indicator that reflects the current WebSocket connection
// state. Intended to be placed in a .toolbar ToolbarItem(.navigationBarTrailing).
//
// States:
//  .connected        → green pulsing dot   + "Live"
//  .connecting       → amber static dot    + "Connecting..."
//  .reconnecting     → amber pulsing dot   + "Reconnecting..."
//  .disconnected     → grey static dot     + "Offline"

struct ConnectionStatusPill: View {

    let state: WebSocketConnectionState

    @State private var isPulsing = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: 5) {
            dot
            Text(state.displayLabel)
                .font(.caption2.weight(.semibold))
                .foregroundColor(labelColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(dotColor.opacity(0.3), lineWidth: 1)
        )
        // Animate the whole pill smoothly when state changes
        .animation(.easeInOut(duration: 0.3), value: state)
        .accessibilityLabel(state.displayLabel)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: state) { _ in startPulseIfNeeded() }
    }

    // MARK: - Dot

    private var dot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
            .scaleEffect(isPulsing && shouldPulse ? 1.45 : 1.0)
            .opacity(isPulsing && shouldPulse ? 0.6 : 1.0)
            .animation(
                shouldPulse
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
    }

    // MARK: - Colours

    private var dotColor: Color {
        switch state {
        case .connected:               return .neonGreen
        case .connecting:              return .orange
        case .reconnecting:            return .orange
        case .disconnected:            return Color(.systemGray3)
        }
    }

    private var labelColor: Color {
        switch state {
        case .connected:               return .neonGreen
        case .connecting, .reconnecting: return .orange
        case .disconnected:            return Color(.systemGray)
        }
    }

    /// Only `.connected` and `.reconnecting` pulse — the dot has something to say.
    private var shouldPulse: Bool {
        switch state {
        case .connected, .reconnecting: return true
        default:                        return false
        }
    }

    // MARK: - Pulse Control

    private func startPulseIfNeeded() {
        if shouldPulse {
            isPulsing = true
        } else {
            isPulsing = false
        }
    }
}

// MARK: - Preview

#Preview("All States") {
    VStack(spacing: 20) {
        ConnectionStatusPill(state: .connected)
        ConnectionStatusPill(state: .connecting)
        ConnectionStatusPill(state: .reconnecting(attempt: 2))
        ConnectionStatusPill(state: .disconnected)
    }
    .padding()
    .background(Color.darkBackground)
}
