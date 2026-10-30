import SwiftUI

// MARK: - StalenessBanner

/// A non-intrusive banner that tells the user when they're viewing cached (stale) data.
/// Slides in from the top when shown, disappears once fresh data arrives.
struct StalenessBanner: View {

    let lastUpdated: Date

    private var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption2.weight(.semibold))
            Text("Last updated \(relativeString)")
                .font(.caption)
        }
        .foregroundColor(.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.darkerBackground.opacity(0.9))
        .overlay(
            Capsule()
                .stroke(Color.textSecondary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Data last updated \(relativeString). Refreshing in background.")
        .onAppear {
            UIAccessibility.post(notification: .announcement,
                                 argument: "Showing cached data from \(relativeString)")
        }
    }
}
