import SwiftUI

// MARK: - VerdictToast

/// A slide-in toast that surfaces real-time WebSocket submission verdicts.
/// Auto-dismisses after 3 seconds. Can also be manually dismissed.
struct VerdictToast: View {

    let submission: Submission
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            verdictIcon
                .font(.title3)
                .foregroundColor(submission.verdictColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(submission.problem.name ?? "Unknown Problem")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Text(submission.verdict?.displayName ?? "Judging...")
                    .font(.caption)
                    .foregroundColor(submission.verdictColor)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3)) { onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.textSecondary)
                    .padding(6)
                    .background(Circle().fill(Color.darkerBackground.opacity(0.6)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [submission.verdictColor.opacity(0.5), submission.verdictColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .cornerRadius(14)
        .shadow(color: submission.verdictColor.opacity(0.2), radius: 12, x: 0, y: 4)
        .padding(.horizontal)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(submission.problem.name ?? "Problem"): \(submission.verdict?.displayName ?? "Judging")")
        .accessibilityAddTraits(.isStaticText)
        .onAppear {
            UIAccessibility.post(notification: .announcement,
                                 argument: "\(submission.problem.name ?? "Problem") — \(submission.verdict?.displayName ?? "Judging")")
        }
    }

    // MARK: - Verdict Icon

    @ViewBuilder
    private var verdictIcon: some View {
        switch submission.verdict {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
        case .wrongAnswer, .compilationError, .runtimeError:
            Image(systemName: "xmark.circle.fill")
        case .timeLimitExceeded, .memoryLimitExceeded:
            Image(systemName: "clock.badge.exclamationmark.fill")
        case .testing, nil:
            Image(systemName: "ellipsis.circle.fill")
        default:
            Image(systemName: "exclamationmark.circle.fill")
        }
    }
}

// MARK: - View Modifier (convenience)

extension View {
    /// Overlays a `VerdictToast` at the top of the view whenever `verdict` is non-nil.
    func verdictToast(verdict: Binding<Submission?>, onDismiss: @escaping () -> Void) -> some View {
        self.overlay(alignment: .top) {
            if let submission = verdict.wrappedValue {
                VerdictToast(submission: submission, onDismiss: onDismiss)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation(.spring(response: 0.3)) { onDismiss() }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.4), value: verdict.wrappedValue?.id)
    }
}
