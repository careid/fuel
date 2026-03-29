import SwiftData

// MARK: - V1 Schema (original)

enum FuelSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DayLog.self, Meal.self, FoodItem.self, UserSettings.self, HealthSnapshot.self]
    }
}

// MARK: - V2 Schema (adds DailyBrief)

enum FuelSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DayLog.self, Meal.self, FoodItem.self, UserSettings.self, HealthSnapshot.self, DailyBrief.self]
    }
}

// MARK: - V3 Schema (adds Workout)

enum FuelSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DayLog.self, Meal.self, FoodItem.self, UserSettings.self, HealthSnapshot.self, DailyBrief.self, Workout.self]
    }
}

// MARK: - Migration Plan

enum FuelMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FuelSchemaV1.self, FuelSchemaV2.self, FuelSchemaV3.self] }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: FuelSchemaV1.self, toVersion: FuelSchemaV2.self),
            .lightweight(fromVersion: FuelSchemaV2.self, toVersion: FuelSchemaV3.self),
        ]
    }
}
