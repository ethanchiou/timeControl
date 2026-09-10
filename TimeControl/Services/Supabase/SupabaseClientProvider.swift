import Foundation
import Supabase

/// The one `SupabaseClient` the app shares, or nil when the build carries no project configuration.
/// Every service reaches the backend through this so auth state, retries and headers stay in one place.
@MainActor
enum SupabaseClientProvider {
    static let shared: SupabaseClient? = make()

    private static func make() -> SupabaseClient? {
        guard let url = SupabaseConfig.url, let key = SupabaseConfig.apiKey else { return nil }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                db: .init(encoder: SupabaseCoding.encoder, decoder: SupabaseCoding.decoder),
                global: .init(headers: ["X-Client-Info": "timecontrol-native"])
            )
        )
    }
}

/// JSON coding for PostgREST rows: snake_case columns, ISO-8601 timestamps with fractional seconds
/// and a zone offset (what Postgres emits for `timestamptz`), tolerant of whole-second values.
nonisolated enum SupabaseCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractional.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractional.date(from: string) ?? whole.date(from: string) ?? postgres.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised timestamp: \(string)")
        }
        return decoder
    }()

    /// A timestamp as the server accepts it in a plain update payload.
    static func timestamp(_ date: Date) -> String { fractional.string(from: date) }

    // ISO8601DateFormatter is documented thread-safe; it is never mutated after configuration.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let whole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Postgres can emit "2026-09-10T02:26:16.953598+00:00" with six fractional digits, more than
    /// `ISO8601DateFormatter` accepts; trim to three and retry.
    private static let postgres: PostgresTimestampParser = PostgresTimestampParser()

    nonisolated struct PostgresTimestampParser: Sendable {
        func date(from string: String) -> Date? {
            guard let dot = string.firstIndex(of: "."),
                  let zone = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
            else { return nil }
            let fraction = string[string.index(after: dot)..<zone]
            let trimmed = String(string[...dot]) + String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0) + String(string[zone...])
            return fractional.date(from: trimmed)
        }
    }
}
