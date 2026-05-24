import SwiftUI

struct TransformRow: View {

    let transform: any Transform
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: transform.icon)
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)

                Text(transform.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
