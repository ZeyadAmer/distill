import SwiftUI
import UIKit

struct HistoryRow: View {

    let item: ClipboardItem
    let isCopied: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    preview

                    HStack(spacing: 8) {
                        ContentTypeBadge(type: item.contentType)

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }

                        Text(item.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.title3)
                    .foregroundStyle(isCopied ? .green : .secondary)
                    .animation(.easeOut(duration: 0.15), value: isCopied)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    // MARK: - Preview content

    /// Text items show their content; image items show a thumbnail (synced
    /// from the Mac); file items show the copied file names.
    @ViewBuilder
    private var preview: some View {
        if item.hasImage, let data = item.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Text(previewText)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(3)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
    }

    private var previewText: String {
        if item.contentType == .file {
            let names = item.copiedFiles.map(\.name)
            if !names.isEmpty { return names.joined(separator: ", ") }
        }
        return item.content.isEmpty ? item.contentType.displayName : item.content
    }
}

// MARK: - ContentTypeBadge

struct ContentTypeBadge: View {
    let type: ContentType

    var body: some View {
        Text(type.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(type.badgeColor).opacity(0.18))
            .foregroundStyle(Color(type.badgeColor))
            .clipShape(Capsule())
    }
}
