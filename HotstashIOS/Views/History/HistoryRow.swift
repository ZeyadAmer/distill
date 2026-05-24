import SwiftUI

struct HistoryRow: View {

    let item: ClipboardItem
    let isCopied: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.content)
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

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
