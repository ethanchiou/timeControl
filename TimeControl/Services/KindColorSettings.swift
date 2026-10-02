import Foundation
import TimeControlCore

/// The user's own colour per kind: assignments orange for them, say. UserDefaults-backed like the
/// other per-kind settings, so it works signed out; signed in, the whole map also lives on the
/// profile (`profiles.kind_colors`) and every device and the web read the same one.
@MainActor
enum KindColorSettings {
    private static func key(_ kind: Kind) -> String { "kindColor.\(kind.rawValue)" }

    /// The colour the user chose for `kind`, or nil for the kind's default.
    static func override(for kind: Kind) -> String? {
        UserDefaults.standard.string(forKey: key(kind))
    }

    /// What `kind` paints with: the user's colour, else the default.
    static func hex(for kind: Kind) -> String {
        override(for: kind) ?? kind.colorHex
    }

    /// Every recoloured kind, as the profile stores it.
    static var overrides: [String: String] {
        var map: [String: String] = [:]
        for kind in Kind.allCases {
            if let hex = override(for: kind) { map[kind.rawValue] = hex }
        }
        return map
    }

    /// Picked by the user: stored here and, when signed in, pushed to the profile.
    static func set(_ hex: String?, for kind: Kind) {
        store(hex, for: kind)
        let all = overrides
        Task { try? await AuthService.shared.updateKindColors(all) }
    }

    /// The profile's map, as pulled. Replaces the local one: a kind missing from the profile is back
    /// on its default.
    static func applyRemote(_ map: [String: String]) {
        for kind in Kind.allCases {
            store(map[kind.rawValue], for: kind)
        }
    }

    private static func store(_ hex: String?, for kind: Kind) {
        if let hex {
            UserDefaults.standard.set(hex, forKey: key(kind))
        } else {
            UserDefaults.standard.removeObject(forKey: key(kind))
        }
    }
}
