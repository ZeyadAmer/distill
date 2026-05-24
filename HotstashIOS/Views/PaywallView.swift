import SwiftUI
import StoreKit

struct PaywallView: View {

    @ObservedObject private var purchase = PurchaseManager.shared
    @State private var product: Product?
    @State private var purchaseError: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            iconSection

            Spacer().frame(height: 32)

            featureList

            Spacer()

            actionSection

            Spacer().frame(height: 40)
        }
        .padding(.horizontal, 32)
        .task { await loadProduct() }
    }

    // MARK: - Sections

    private var iconSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "clipboard.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Hotstash Pro")
                .font(.title.bold())

            Text("Your free trial has ended. Unlock Hotstash to continue using all features.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(icon: "clock",             text: "Unlimited clipboard history")
            FeatureRow(icon: "wand.and.sparkles", text: "Text transforms")
            FeatureRow(icon: "bookmark",          text: "Saved snippets")
            FeatureRow(icon: "list.number",       text: "Paste queue")
            FeatureRow(icon: "square.and.arrow.up", text: "Share extension")
        }
        .padding(.horizontal, 8)
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            if let error = purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await buy() }
            } label: {
                Group {
                    if purchase.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else if let product {
                        Text("Unlock for \(product.displayPrice)")
                            .fontWeight(.semibold)
                    } else {
                        Text("Unlock Hotstash Pro")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(purchase.isLoading)

            Button("Restore Purchases") {
                Task { await purchase.restorePurchases() }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .disabled(purchase.isLoading)
        }
    }

    // MARK: - Actions

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
        }
    }
}

// MARK: - FeatureRow

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}
