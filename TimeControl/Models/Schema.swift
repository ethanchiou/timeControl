import Foundation
import SwiftData

/// The persistent schema. Every `@Model` lives in an extension of this enum. Rules kept for sync
/// compatibility: relationships optional with inverses, scalars defaulted, enums stored raw, no
/// unique constraints.
///
/// Migration is SwiftData's automatic lightweight inference: only add optional or defaulted
/// attributes and new entities, and bump `versionIdentifier` when you do. There is deliberately no
/// staged `SchemaMigrationPlan`: a staged plan refuses any store whose model it does not recognise
/// exactly, and stores in the wild were written by several intermediate models (fields were added
/// without version bumps before v2). See `LegacyStoreTests`.
///
/// v2 (2026-09): the `SharedGroup` model; `Event.groupID` and `Event.authorID`; `syncedAt` on every
/// synced model, the server's `updated_at` for the state last pushed or pulled (nil = never synced).
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Term.self, Series.self, Blackout.self, OccurrenceException.self, Event.self, Project.self, TodoItem.self, SharedGroup.self]
    }
}

typealias Term = SchemaV2.Term
typealias Series = SchemaV2.Series
typealias Blackout = SchemaV2.Blackout
typealias OccurrenceException = SchemaV2.OccurrenceException
typealias Event = SchemaV2.Event
typealias Project = SchemaV2.Project
typealias TodoItem = SchemaV2.TodoItem
typealias SharedGroup = SchemaV2.SharedGroup

enum ModelContainerFactory {
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration("TimeControl", schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Opens (and migrates) the store file at `url`; tests use it on copies of old stores.
    static func make(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration("TimeControl", schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
