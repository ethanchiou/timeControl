import Foundation
import SwiftData

/// Version 1 of the persistent schema. Every `@Model` lives in an extension of this enum so a future
/// `SchemaV2` can coexist with it during migration. Rules kept for CloudKit compatibility:
/// relationships optional with inverses, scalars defaulted, enums stored raw, no unique constraints.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Term.self, Series.self, Blackout.self, OccurrenceException.self, Event.self, Project.self, TodoItem.self]
    }
}

typealias Term = SchemaV1.Term
typealias Series = SchemaV1.Series
typealias Blackout = SchemaV1.Blackout
typealias OccurrenceException = SchemaV1.OccurrenceException
typealias Event = SchemaV1.Event
typealias Project = SchemaV1.Project
typealias TodoItem = SchemaV1.TodoItem

enum TimeControlMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum ModelContainerFactory {
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration("TimeControl", schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, migrationPlan: TimeControlMigrationPlan.self, configurations: [config])
    }
}
