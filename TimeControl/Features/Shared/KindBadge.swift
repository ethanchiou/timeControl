import SwiftUI
import TimeControlCore

enum KindBadgeStyle {
    case dot, pill, icon
}

struct KindBadge: View {
    var kind: Kind
    var style: KindBadgeStyle = .pill

    private var tint: Color { Color.kind(kind) }

    var body: some View {
        switch style {
        case .dot:
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
        case .pill:
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(kind.displayName)
                    .font(.caption)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
        case .icon:
            Image(systemName: kind.symbolName)
                .foregroundStyle(tint)
        }
    }
}
