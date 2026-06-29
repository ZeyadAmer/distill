import SwiftUI

// MARK: - ReviewQueueView

/// Admin-only moderation queue: lists transforms awaiting review and lets an
/// admin approve (→ live) or reject (→ removed) via the server-side RPCs.
/// Only shown when `AuthManager.isAdmin` is true.
struct ReviewQueueView: View {

    let accessToken: String

    @State private var pending: [TransformListItem] = []
    @State private var isLoading = false
    @State private var message: String?
    @State private var working: Set<UUID> = []

    private let service = MarketplaceServiceProvider.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pending review").font(.headline)
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
            .padding(12)

            if let message {
                Text(message)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }

            Divider()

            content
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && pending.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if pending.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(.secondary)
                Text("Nothing waiting for review.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(pending) { item in row(item) }
                }
                .padding(12)
            }
        }
    }

    private func row(_ item: TransformListItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .image ? "photo" : "textformat")
                .foregroundStyle(.tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body)
                HStack(spacing: 6) {
                    if let author = item.authorName {
                        Text(author).font(.caption).foregroundStyle(.secondary)
                    }
                    CategoryBadge(text: item.category)
                    CategoryBadge(text: item.kind.rawValue)
                }
            }
            Spacer()
            if working.contains(item.id) {
                ProgressView().controlSize(.small)
            } else {
                Button("Approve") { Task { await act(item, approve: true) } }
                    .controlSize(.small)
                Button("Reject", role: .destructive) { Task { await act(item, approve: false) } }
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func load() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        guard let token = await AuthManager.shared.validToken() else {
            message = "Session expired — sign in again."
            return
        }
        do {
            pending = try await service.pendingReview(accessToken: token)
        } catch {
            message = "Couldn't load the queue. \(error.localizedDescription)"
        }
    }

    private func act(_ item: TransformListItem, approve: Bool) async {
        working.insert(item.id)
        defer { working.remove(item.id) }
        guard let token = await AuthManager.shared.validToken() else {
            message = "Session expired — sign in again."
            return
        }
        do {
            if approve {
                try await service.approve(transformID: item.id, accessToken: token)
            } else {
                try await service.reject(transformID: item.id, accessToken: token)
            }
            pending.removeAll { $0.id == item.id }
            message = approve ? "Approved \(item.name)." : "Rejected \(item.name)."
        } catch {
            message = "Action failed. \(error.localizedDescription)"
        }
    }
}
