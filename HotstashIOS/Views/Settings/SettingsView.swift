import SwiftUI
import StoreKit

struct AboutView: View {

    @ObservedObject private var purchase = PurchaseManager.shared
    @State private var product: Product?
    @State private var purchaseError: String?
    @State private var showPurchaseError = false

    var body: some View {
        NavigationStack {
            List {
                appIdentitySection
                purchaseSection
                infoSection
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadProduct() }
            .alert("Purchase Failed", isPresented: $showPurchaseError, presenting: purchaseError) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error)
            }
        }
    }

    // MARK: - Sections

    private var appIdentitySection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .padding(.top, 8)

                Text("Hotstash")
                    .font(.title2.bold())

                Text(versionString)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Copy anything. Paste it perfectly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    private var purchaseSection: some View {
        Section("Hotstash Pro") {
            trialStatusRow

            if !purchase.isPurchased {
                Button {
                    Task { await buy() }
                } label: {
                    HStack {
                        if purchase.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(buyLabel, systemImage: "cart")
                        }
                        Spacer()
                    }
                }
                .disabled(purchase.isLoading)

                Button("Restore Purchases") {
                    Task { await purchase.restorePurchases() }
                }
                .foregroundStyle(.secondary)
                .disabled(purchase.isLoading)
            }
        }
    }

    private var infoSection: some View {
        Section {
            Label("Your clipboard never leaves your device.", systemImage: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Link(destination: URL(string: "mailto:zeyad.hesham@icloud.com")!) {
                Label("Contact Support", systemImage: "envelope")
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var trialStatusRow: some View {
        if purchase.isPurchased {
            Label("Full version — thank you!", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .fontWeight(.medium)
        } else if TrialManager.shared.isInTrial {
            let days = TrialManager.shared.trialDaysRemaining
            Label(
                "\(days) day\(days == 1 ? "" : "s") remaining in trial",
                systemImage: "clock"
            )
            .foregroundStyle(.secondary)
        } else {
            Label("Trial expired", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fontWeight(.medium)
        }
    }

    // MARK: - Helpers

    private var buyLabel: String {
        if let product {
            return "Purchase Hotstash — \(product.displayPrice)"
        }
        return "Purchase Hotstash"
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func loadProduct() async {
        let products = try? await Product.products(for: [purchase.productID])
        product = products?.first
    }

    private func buy() async {
        purchaseError = nil
        do {
            try await purchase.purchase()
        } catch {
            purchaseError = error.localizedDescription
            showPurchaseError = true
        }
    }
}
