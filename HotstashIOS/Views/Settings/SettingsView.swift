import SwiftUI
import StoreKit
import UIKit

struct AboutView: View {

    @ObservedObject private var purchase = PurchaseManager.shared
    @State private var product: Product?
    @State private var purchaseError: String?
    @State private var showPurchaseError = false
    @State private var showKeyboardSetup = false

    /// 0 = General (about/purchase), 1 = Transforms (order + enablement).
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    Text("General").tag(0)
                    Text("Transforms").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if tab == 0 {
                    List {
                        appIdentitySection
                        purchaseSection
                        infoSection
                    }
                } else {
                    TransformOrderView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showKeyboardSetup) { KeyboardSetupView() }
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
            Button {
                showKeyboardSetup = true
            } label: {
                Label("Set Up the Keyboard", systemImage: "keyboard")
            }

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

// MARK: - KeyboardSetupView

/// Explains how to enable the Hotstash custom keyboard. Shown once on first
/// launch (see `MainTabView`) and reachable any time from Settings, since the
/// keyboard is the main reason users don't realize the app does anything in
/// other apps.
struct KeyboardSetupView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("Enable the Hotstash Keyboard")
                            .font(.title2.bold())
                        Text("Paste your clips, snippets, and transforms straight from any app — without switching back to Hotstash.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        step(1, "Open the Settings app.")
                        step(2, "Go to General → Keyboard → Keyboards.")
                        step(3, "Tap Add New Keyboard…, then choose Hotstash.")
                        step(4, "Tap Hotstash and turn on Allow Full Access so it can read and paste your clipboard.")
                    }

                    Label("Full Access keeps everything on-device — nothing is sent anywhere.",
                          systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .navigationTitle("Keyboard Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
