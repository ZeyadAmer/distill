import SwiftUI

// MARK: - AboutSettingsView

struct AboutSettingsView: View {

    @ObservedObject private var purchaseManager = PurchaseManager.shared

    @State private var purchaseError: String?
    @State private var showingPurchaseError = false
    @State private var restoreMessage: String?
    @State private var showingRestoreMessage = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                purchaseSection
                featuresSection
                transformsSection
                shortcutsSection
                howToUseSection
                footerSection
            }
            .frame(maxWidth: .infinity)
        }
        .alert("Purchase Failed", isPresented: $showingPurchaseError, presenting: purchaseError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error)
        }
        .alert("Restore Purchase", isPresented: $showingRestoreMessage, presenting: restoreMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18), Color.purple.opacity(0.10), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color.accentColor.opacity(0.4), radius: 12, y: 4)
                .padding(.top, 28)

                Text("Hotstash")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Version \(versionString)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text("Copy anything. Paste it perfectly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Purchase

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            trialStatusView

            if !purchaseManager.isPurchased {
                Button {
                    Task {
                        do {
                            try await purchaseManager.purchase()
                        } catch {
                            purchaseError = error.localizedDescription
                            showingPurchaseError = true
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cart.fill")
                        Text("Purchase Hotstash — $9.99")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(purchaseManager.isLoading)
                .padding(.horizontal, 24)

                Button("Restore Purchase") {
                    Task {
                        switch await purchaseManager.restorePurchases() {
                        case .restored:
                            restoreMessage = "Your purchase has been restored."
                        case .nothingToRestore:
                            restoreMessage = "No previous purchase was found for this Apple ID."
                        case .failed(let message):
                            restoreMessage = "Restore failed: \(message)"
                        }
                        showingRestoreMessage = true
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(purchaseManager.isLoading)
            }

            if purchaseManager.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 20)
        .background(Color.primary.opacity(0.03))

    }

    // MARK: - Features

    fileprivate struct FeatureCard: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
        let color: Color
        let premium: Bool
    }

    private let featureCards: [FeatureCard] = [
        FeatureCard(icon: "clock.arrow.circlepath",
                    title: "Clipboard History",
                    description: "Everything you copy, always at hand. Unlimited with Hotstash.",
                    color: .blue, premium: false),
        FeatureCard(icon: "pin.fill",
                    title: "Pin Items",
                    description: "Keep important snippets pinned and drag to reorder them.",
                    color: .orange, premium: false),
        FeatureCard(icon: "magnifyingglass",
                    title: "Instant Search",
                    description: "Find any snippet in milliseconds across your entire history.",
                    color: .purple, premium: false),
        FeatureCard(icon: "wand.and.stars",
                    title: "Text Transforms",
                    description: "30+ transforms: case, encoding, JSON, lists, cleanup, and more.",
                    color: .pink, premium: true),
        FeatureCard(icon: "photo.stack",
                    title: "Image Transforms",
                    description: "Resize, convert, rotate, and filter images right from the panel.",
                    color: .teal, premium: true),
        FeatureCard(icon: "rectangle.stack.fill",
                    title: "Multi-Paste",
                    description: "Paste multiple items at once into any app.",
                    color: .indigo, premium: true),
        FeatureCard(icon: "folder.fill",
                    title: "Folders",
                    description: "Organize snippets into folders, kept safe from history cleanup.",
                    color: .yellow, premium: false),
        FeatureCard(icon: "tag.fill",
                    title: "Item Names",
                    description: "Name any item and it jumps to the top when you search that name.",
                    color: .cyan, premium: false),
    ]

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What's Inside", icon: "sparkles")
                .padding(.horizontal, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(featureCards) { card in
                    FeatureCardView(card: card)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Transforms

    fileprivate struct TransformGroup: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let color: Color
        let items: [String]
    }

    private let transformGroups: [TransformGroup] = [
        TransformGroup(name: "Case", icon: "textformat", color: .blue,
                       items: ["UPPERCASE", "lowercase", "Title Case", "Sentence case"]),
        TransformGroup(name: "Whitespace", icon: "line.3.horizontal", color: .gray,
                       items: ["Trim", "Remove blank lines", "Remove duplicates", "Remove line breaks"]),
        TransformGroup(name: "Encoding", icon: "lock.doc", color: .orange,
                       items: ["Base64 Encode/Decode", "URL Encode/Decode", "Decode JWT"]),
        TransformGroup(name: "JSON", icon: "curlybraces", color: .green,
                       items: ["Format JSON", "Minify JSON"]),
        TransformGroup(name: "Cleanup", icon: "scissors", color: .pink,
                       items: ["Strip HTML", "Remove Markdown", "Extract URLs", "Word Count"]),
        TransformGroup(name: "Images", icon: "photo", color: .teal,
                       items: ["Resize 50%", "Grayscale", "PNG/WebP", "Flip", "Rotate 90°"]),
    ]

    private var transformsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Transforms", icon: "wand.and.stars")
                .padding(.horizontal, 20)

            VStack(spacing: 6) {
                ForEach(transformGroups) { group in
                    TransformGroupRow(group: group)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 20)
        .background(Color.primary.opacity(0.025))
    }

    // MARK: - Shortcuts

    private let shortcuts: [(String, String, String)] = [
        ("⌘⇧V", "Open Hotstash", "Global hotkey (customizable in General)"),
        ("⌘1–9", "Paste by position", "Paste the nth item instantly"),
        ("↑ ↓", "Navigate", "Move through history"),
        ("↵", "Copy", "Copy selected item"),
        ("⌘⇧L", "Multi-paste", "Open the multi-paste panel"),
    ]

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Keyboard Shortcuts", icon: "keyboard")
                .padding(.horizontal, 20)

            VStack(spacing: 1) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { idx, shortcut in
                    HStack(spacing: 12) {
                        Text(shortcut.0)
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 68, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(shortcut.1)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(shortcut.2)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(idx.isMultiple(of: 2) ? Color.primary.opacity(0.03) : Color.clear)
                }
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: - How To Use

    fileprivate struct HowToStep: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
    }

    private let howToSteps: [HowToStep] = [
        HowToStep(title: "Open Hotstash",
                  detail: "Press the global hotkey (default ⌘⇧V, customizable in General) to open the clipboard panel near your cursor or menu bar."),
        HowToStep(title: "Copy & paste",
                  detail: "Everything you copy is saved automatically. Select an item and press Return to copy, or double-click to paste it into the previous app. ⇧Return pastes plain text; ⌘1–9 paste by position."),
        HowToStep(title: "Search",
                  detail: "Start typing in the search box to filter your whole history — it matches content, text inside images via OCR, link titles, and names you assign."),
        HowToStep(title: "Name items",
                  detail: "Right-click any item → \"Name…\" to give it a searchable label (e.g. \"supabase\"), then find it instantly by that name."),
        HowToStep(title: "Pin",
                  detail: "Pin important items to the Pinned tab and drag to reorder them."),
        HowToStep(title: "Folders",
                  detail: "Click the \"＋\" tab to create a folder, then right-click any item → \"Move to Folder\". Folders sit beside Recents and Pinned and are kept safe from history cleanup. Rename or Delete from the gear menu while the tab is open."),
        HowToStep(title: "Transforms",
                  detail: "Select an item and click \"Transform\" to reshape it (case, JSON, encoding, cleanup, and more). Hold ⌘ while clicking transforms to stack several and apply them in sequence."),
        HowToStep(title: "Clean Link",
                  detail: "Right-click a link → \"Copy Clean Link\" to strip tracking parameters (utm, fbclid, etc.) and resolve share redirects to the real destination."),
        HowToStep(title: "Multi-Paste & Paste Stack",
                  detail: "Open Multi-Paste (⌘⇧L) to paste several items at once, or ⌘-click multiple rows and use the Paste Stack so each ⌘V pastes the next item."),
    ]

    private var howToUseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "How To Use", icon: "book.fill")
                .padding(.horizontal, 20)

            VStack(spacing: 6) {
                ForEach(Array(howToSteps.enumerated()), id: \.element.id) { idx, step in
                    HowToStepRow(number: idx + 1, step: step)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 14) {
            Divider().padding(.horizontal, 24)

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Synced privately through your iCloud. No third parties. No tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Link("Contact Support", destination: URL(string: "mailto:zeyad.hesham@icloud.com")!)
                .font(.caption)
                .foregroundStyle(Color.accentColor)

            Text("Made with ♥ by Zeyad Amer")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .padding(.top, 8)
    }

    // MARK: - Trial status

    @ViewBuilder
    private var trialStatusView: some View {
        if purchaseManager.isPurchased {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Full version")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Text("Lifetime license · thank you for your support")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.16), Color.green.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        } else if TrialManager.shared.isInTrial {
            let days = TrialManager.shared.trialDaysRemaining
            HStack(spacing: 4) {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
                Text("\(days) day\(days == 1 ? "" : "s") remaining in your free trial")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        } else {
            Label("Trial expired — unlock full access below", systemImage: "exclamationmark.triangle.fill")
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

// MARK: - SectionHeader

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
        }
    }
}

// MARK: - FeatureCardView

private struct FeatureCardView: View {
    let card: AboutSettingsView.FeatureCard
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(card.color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: card.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(card.color)
                }
                Spacer()
                if card.premium {
                    Text("PRO")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Text(card.title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(card.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isHovered ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(card.color.opacity(isHovered ? 0.25 : 0.08), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - TransformGroupRow

private struct TransformGroupRow: View {
    let group: AboutSettingsView.TransformGroup

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(group.color.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: group.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(group.color)
            }

            Text(group.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 72, alignment: .leading)

            Text(group.items.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - HowToStepRow

private struct HowToStepRow: View {
    let number: Int
    let step: AboutSettingsView.HowToStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 26, height: 26)
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }
}
