import Foundation

// These mirror the tables in Database/schema.sql — keep them in sync
// whenever the schema changes.

struct MuscleGroup: Identifiable {
    let id: Int
    let name: String
    let bodyRegion: String?
}

struct Equipment: Identifiable {
    let id: Int
    let name: String
    let category: String?
    let usageInstructions: String?
    let safetyNotes: String?
}

struct Exercise: Identifiable {
    let id: Int
    let name: String
    let exerciseType: String       // "strength" | "cardio" | "mobility"
    let equipmentId: Int?
    let primaryMuscleId: Int?
    let difficulty: String?        // "beginner" | "intermediate" | "advanced"
    let instructions: String?
    let incrementKg: Double        // default progression jump, e.g. 2.5 upper / 5 lower
}

struct WorkoutTemplate: Identifiable {
    let id: Int
    let name: String
    let goal: String?              // "fat_loss" | "muscle_gain" | "recomposition"
    let notes: String?
}

struct TemplateExercise: Identifiable {
    let id: Int
    let templateId: Int
    let exerciseId: Int
    let targetSets: Int
    let targetRepsMin: Int
    let targetRepsMax: Int
    let orderIndex: Int
}

struct WorkoutSession: Identifiable {
    let id: Int
    let templateId: Int?
    let startTime: Date
    var endTime: Date?
    var totalCalories: Double?
    var avgHeartRate: Double?
    var notes: String?
    var healthKitUUID: String?
}

struct WorkoutSet: Identifiable {
    let id: Int
    let sessionId: Int
    let exerciseId: Int
    let setNumber: Int
    let reps: Int
    let weightKg: Double
    let rpe: Double?
    let isWarmup: Bool
}

struct PersonalRecord: Identifiable {
    let id: Int
    let exerciseId: Int
    let recordType: String         // "1rm" | "max_reps" | "max_volume"
    let value: Double
    let achievedAt: Date
}
