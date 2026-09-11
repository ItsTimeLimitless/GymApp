import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false

    private init() {}

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let typesToShare: Set = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate)
        ]
        let typesToRead: Set = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.bodyMass)
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            isAuthorized = true
        } catch {
            print("⚠️ HealthKit authorization failed: \(error)")
        }
    }

    /// Most recent body weight logged in Health, in kg — used to make the
    /// workout calorie estimate below more accurate. Returns nil if no
    /// weight has ever been logged (e.g. from a smart scale or the
    /// Health app itself).
    func fetchLatestBodyWeightKg() async -> Double? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.bodyMass),
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            healthStore.execute(query)
        }
    }

    /// Writes a weight entry to Health so it also shows up in the
    /// Fitness/Health app's own weight tracking, even though it was
    /// entered here rather than there.
    func writeBodyWeight(kg: Double, date: Date = Date()) async -> Bool {
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date,
            end: date
        )
        do {
            try await healthStore.save(sample)
            return true
        } catch {
            print("⚠️ Failed to save body weight to HealthKit: \(error)")
            return false
        }
    }

    /// Rough calorie estimate for a strength session, used so the workout
    /// isn't written to Health with 0 calories (which under-credits the
    /// Move ring). Uses MET × bodyweight × duration when a logged weight
    /// is available; otherwise falls back to a flat per-minute estimate.
    /// Prefers the weight entered in GymApp (fast, always available)
    /// over Health's own record, since the latter may never have one.
    /// Not a substitute for a Watch-measured value — just better than
    /// zero, and written scoped to the workout itself (not as a
    /// free-floating sample) so it doesn't stack on top of whatever the
    /// Watch already estimated passively for the same time window.
    func estimateCalories(duration: TimeInterval) async -> Double {
        let hours = duration / 3600
        let strengthTrainingMET = 5.0 // moderate-vigorous resistance training
        let weightKg: Double?
        if let localWeightKg = Database.shared.latestBodyWeightKg() {
            weightKg = localWeightKg
        } else {
            weightKg = await fetchLatestBodyWeightKg()
        }
        if let weightKg {
            return strengthTrainingMET * weightKg * hours
        }
        let flatKcalPerMinute = 6.0
        return flatKcalPerMinute * (duration / 60)
    }

    /// Writes a completed session to Apple Health so it shows up in the
    /// Fitness app and counts toward Activity rings. Returns the HKWorkout
    /// UUID so it can be stored in workout_sessions.healthkit_uuid.
    func saveWorkout(startDate: Date, endDate: Date, totalCalories: Double?) async -> String? {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        do {
            try await builder.beginCollection(at: startDate)

            if let calories = totalCalories {
                let energyType = HKQuantityType(.activeEnergyBurned)
                let energySample = HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                    start: startDate,
                    end: endDate
                )
                try await builder.addSamples([energySample])
            }

            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()
            return workout?.uuid.uuidString
        } catch {
            print("⚠️ Failed to save workout to HealthKit: \(error)")
            return nil
        }
    }
}
