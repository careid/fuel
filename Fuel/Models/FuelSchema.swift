import SwiftData

// MARK: - Current Schema

/// All model types for the current schema version.
/// Bump the version and add a migration stage whenever a @Model class changes.
enum FuelSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DayLog.self, Meal.self, FoodItem.self, UserSettings.self, HealthSnapshot.self]
    }
}

// MARK: - Migration Plan

enum FuelMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FuelSchemaV1.self] }
    /// No migrations needed yet — add lightweight or custom stages here as the schema evolves.
    static var stages: [MigrationStage] { [] }
}
