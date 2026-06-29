import SwiftUI

// MARK: - TransformDetailView

/// Detail sheet for a single marketplace transform: metadata, a read-only body
/// preview, install control, reviews, and (when signed in) rate/review/report.
struct TransformDetailView: View {

    let item: TransformListItem
    @ObservedObject var viewModel: MarketplaceViewModel

    /// Optional signed-in access token. When nil, auth-gated controls are hidden.
    /// Sourced from `AuthManager.shared.accessToken` (stub until S4).
    let accessToken: String?

    @Environment(\.dismiss) private var dismiss

    @State private var detail: TransformDetail?
    @State private var reviews: [MarketplaceReview] = []
    @State private var isLoading = true
    @State private var loadError: String?

    // Auth-gated input state
    @State private var ratingStars = 0
    @State private var reviewBody = ""
    @State private var reportReason = ""
    @State private var actionMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 460, height: 560)
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind == .image ? "photo" : "textformat")
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.title3).bold()
                if let author = detail?.authorName ?? item.authorName {
                    Text("by \(author)").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            errorState(loadError)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statsRow
                    if let description = detail?.description, !description.isEmpty {
                        Text(description).font(.body)
                    }
                    bodyPreview
                    reviewsSection
                    if accessToken != nil {
                        authGatedControls
                    }
                }
                .padding(16)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            Label("\(item.installCount)", systemImage: "arrow.down.circle")
            Label(String(format: "%.1f", item.ratingAvg), systemImage: "star.fill")
                .foregroundStyle(.yellow)
            Text("(\(item.ratingCount))").foregroundStyle(.secondary)
            CategoryBadge(text: item.category)
            if let version = detail?.version {
                Text("v\(version)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var bodyPreview: some View {
        if let body = detail?.body {
            VStack(alignment: .leading, spacing: 6) {
                Text("Body").font(.headline)
                switch body {
                case let .text(js):
                    ScrollView {
                        Text(js)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(height: 120)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                case let .image(steps):
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step.type)")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
        }
    }

    // MARK: Reviews

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reviews").font(.headline)
            if reviews.isEmpty {
                Text("No reviews yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(reviews) { review in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(review.authorName ?? "Anonymous").font(.caption).bold()
                            if let stars = review.stars {
                                Text(String(repeating: "★", count: stars))
                                    .font(.caption).foregroundStyle(.yellow)
                            }
                        }
                        Text(review.body).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Auth-gated controls

    private var authGatedControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Your feedback").font(.headline)

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        ratingStars = star
                        Task { await rate(star) }
                    } label: {
                        Image(systemName: star <= ratingStars ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("Write a review…", text: $reviewBody)
                    .textFieldStyle(.roundedBorder)
                Button("Post") { Task { await postReview() } }
                    .disabled(reviewBody.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                TextField("Report reason…", text: $reportReason)
                    .textFieldStyle(.roundedBorder)
                Button("Report", role: .destructive) { Task { await report() } }
                    .disabled(reportReason.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let actionMessage {
                Text(actionMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let actionMessage, accessToken == nil {
                Text(actionMessage).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            installButton
        }
        .padding(16)
    }

    @ViewBuilder
    private var installButton: some View {
        if viewModel.isInstalled(item.slug) {
            Button("Uninstall", role: .destructive) {
                viewModel.uninstall(slug: item.slug)
            }
        } else {
            Button("Install") {
                Task { await viewModel.install(item) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Error state

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Networking

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            detail = try await viewModel.service.detail(slug: item.slug)
            reviews = (try? await viewModel.service.reviews(transformID: item.id)) ?? []
        } catch {
            loadError = "Couldn't load this transform."
        }
        isLoading = false
    }

    private func rate(_ stars: Int) async {
        guard accessToken != nil, let token = await AuthManager.shared.validToken() else { return }
        do {
            try await viewModel.service.rate(transformID: item.id, stars: stars, accessToken: token)
            actionMessage = "Thanks for rating!"
        } catch {
            actionMessage = "Couldn't submit rating."
        }
    }

    private func postReview() async {
        let body = reviewBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        guard accessToken != nil, let token = await AuthManager.shared.validToken() else { return }
        do {
            try await viewModel.service.postReview(transformID: item.id, body: body, accessToken: token)
            reviewBody = ""
            actionMessage = "Review posted."
            reviews = (try? await viewModel.service.reviews(transformID: item.id)) ?? reviews
        } catch {
            actionMessage = "Couldn't post review."
        }
    }

    private func report() async {
        let reason = reportReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }
        guard accessToken != nil, let token = await AuthManager.shared.validToken() else { return }
        do {
            try await viewModel.service.report(
                targetType: "transform", targetID: item.id, reason: reason, accessToken: token
            )
            reportReason = ""
            actionMessage = "Report submitted."
        } catch {
            actionMessage = "Couldn't submit report."
        }
    }
}

// MARK: - CategoryBadge

/// A small pill displaying a category or kind label.
struct CategoryBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }
}
