import SwiftUI
import UIKit

// MARK: - KeyboardDataSource

/// Loads mirrored clips for display inside the keyboard.
final class KeyboardDataSource: ObservableObject {
    @Published private(set) var clips: [KeyboardClip] = []
    @Published private(set) var hasFullAccess = false

    func reload(hasFullAccess: Bool) {
        self.hasFullAccess = hasFullAccess
        clips = hasFullAccess ? KeyboardClipsMirror.read() : []
    }
}

// MARK: - KeyboardView

/// Compact list of recent clips with a globe key (keyboard switching) and a
/// delete-backward key.
struct KeyboardView: View {

    @ObservedObject var dataSource: KeyboardDataSource
    let showsGlobeKey: Bool
    let configureGlobeButton: (UIButton) -> Void
    let onInsert: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            if showsGlobeKey {
                GlobeButton(configure: configureGlobeButton)
                    .frame(width: 36, height: 30)
            }

            Label("Hotstash", systemImage: "doc.on.clipboard.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "delete.left")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !dataSource.hasFullAccess {
            message(
                icon: "lock",
                title: "Enable Full Access to see your clips",
                detail: "Settings › General › Keyboard › Keyboards › Hotstash › Allow Full Access"
            )
        } else if dataSource.clips.isEmpty {
            message(
                icon: "clipboard",
                title: "No clips yet",
                detail: "Copy text in Hotstash (or on your Mac) and it will show up here."
            )
        } else {
            clipList
        }
    }

    private var clipList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(dataSource.clips) { clip in
                    Button {
                        onInsert(clip.content)
                    } label: {
                        HStack(spacing: 8) {
                            if clip.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Text(clip.content)
                                .font(.subheadline)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - GlobeButton

/// The "next keyboard" key. Must be a UIControl so
/// `handleInputModeList(from:with:)` receives the raw touch events
/// (long-press shows the keyboard picker).
private struct GlobeButton: UIViewRepresentable {
    let configure: (UIButton) -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = "Next keyboard"
        configure(button)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}
