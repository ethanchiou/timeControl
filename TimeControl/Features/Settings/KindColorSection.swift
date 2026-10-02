import SwiftUI
import TimeControlCore

/// The "Colours" section of Settings: one swatch row per kind, so assignments can be orange for
/// this user whatever the default says. The leading swatch is the default; picking it clears the
/// override. Signed in, the choice follows the account to every device and the web.
struct KindColorSection: View {
    @State private var overrides: [Kind: String?] = Dictionary(
        uniqueKeysWithValues: Kind.allCases.map { ($0, KindColorSettings.override(for: $0)) }
    )

    var body: some View {
        Section {
            ForEach(Kind.allCases) { kind in
                VStack(alignment: .leading, spacing: 6) {
                    Label(kind.displayName, systemImage: kind.symbolName)
                    ColorSwatchRow(
                        selection: binding(for: kind),
                        matching: nil,
                        inherited: (hex: kind.colorHex, symbol: kind.symbolName, label: "Default colour")
                    )
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Colours")
        } footer: {
            Text(AuthService.shared.isSignedIn
                ? "What each kind looks like on your calendar. Saved to your account, so every device agrees. Items with a colour of their own keep it."
                : "What each kind looks like on your calendar. Items with a colour of their own keep it.")
        }
    }

    private func binding(for kind: Kind) -> Binding<String?> {
        Binding(
            get: { overrides[kind] ?? nil },
            set: { newValue in
                overrides[kind] = newValue
                KindColorSettings.set(newValue, for: kind)
            }
        )
    }
}
