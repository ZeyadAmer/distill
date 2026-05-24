import SwiftUI

struct EmptyStateView<Action: View>: View {

    let icon: String
    let title: String
    let message: String
    let action: Action

    init(icon: String, title: String, message: String, @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.icon    = icon
        self.title   = title
        self.message = message
        self.action  = action()
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            action
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
