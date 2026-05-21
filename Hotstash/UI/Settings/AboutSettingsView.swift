import SwiftUI

// MARK: - AboutSettingsView

struct AboutSettingsView: View {

    // MARK: - Observed state

    @ObservedObject private var purchaseManager = PurchaseManager.shared

    // MARK: - Local state

    @State private var purchaseError: String?
    @State private var showingPurchaseError = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // MARK: App identity

                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 24)

                    Text("Hotstash")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(versionString)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Copy anything. Paste it perfectly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(.bottom, 20)

                Divider()
                    .padding(.horizontal, 24)

                // MARK: Purchase / trial section

                VStack(spacing: 12) {
                    trialStatusView

                    if !purchaseManager.isPurchased {
                        Button {
                            Task { await purchaseManager.purchase() }
                        } label: {
                            Label("Purchase Hotstash — $9.99", systemImage: "cart")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(purchaseManager.isLoading)
                        .padding(.horizontal, 24)

                        Button("Restore Purchase") {
                            Task { await purchaseManager.restorePurchases() }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .disabled(purchaseManager.isLoading)
                    }

                    if purchaseManager.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 16)

                Divider()
                    .padding(.horizontal, 24)

                // MARK: Privacy note + support

                VStack(spacing: 10) {
                    Label(
                        "Your clipboard never leaves your Mac.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Link(
                        "Contact Support",
                        destination: URL(string: "mailto:support@hotstash.app")!
                    )
                    .font(.caption)
                }
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .alert("Purchase Failed", isPresented: $showingPurchaseError, presenting: purchaseError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var trialStatusView: some View {
        if purchaseManager.isPurchased {
            Label("Full version — thank you!", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
                .fontWeight(.medium)
        } else if TrialManager.shared.isInTrial {
            let days = TrialManager.shared.trialDaysRemaining
            Text("\(days) day\(days == 1 ? "" : "s") remaining in trial")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Label("Trial expired", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - Helpers

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
