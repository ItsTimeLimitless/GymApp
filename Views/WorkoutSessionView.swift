import SwiftUI

/// A workout_template_exercises row joined with its exercise's name —
/// a convenience for driving the session flow, not a 1:1 table mirror,
/// so it lives here rather than in Models.swift.
struct SessionExercise: Identifiable {
    let id: Int             // exercise_id
    let name: String
    let targetSets: Int
    let targetRepsMin: Int
    let targetRepsMax: Int
    let incrementKg: Double // how much to add on progression — 2.5 upper body, 5 lower body
    let demoAssetId: String? // bundled folder name under Resources/ExerciseDemos, if one exists
}

/// Replaces ContentView's "Active session UI goes here" placeholder.
/// Walks the session's exercises one at a time, hosting LogSetView for
/// each, and persists every logged set to workout_sets as it happens —
/// so a crash or force-quit mid-workout only loses the set in progress.
struct WorkoutSessionView: View {
    let session: WorkoutSession
    let exercises: [SessionExercise]     // chosen back in WorkoutPreviewView, swaps included
    @EnvironmentObject var healthKit: HealthKitManager
    var onSessionFinished: (WorkoutSession, [LoggedSet]) -> Void

    @State private var exerciseIndex = 0
    @State private var loggedSets: [LoggedSet] = []

    var body: some View {
        Group {
            if exerciseIndex < exercises.count {
                let current = exercises[exerciseIndex]
                LogSetView(
                    exerciseId: current.id,
                    exerciseName: current.name,
                    suggestedWeightKg: Database.shared.suggestedWeightKg(
                        exerciseId: current.id,
                        targetReps: current.targetRepsMin...current.targetRepsMax,
                        incrementKg: current.incrementKg
                    ) ?? 0, // nil = never done before, i.e. session-1 calibration
                    targetReps: current.targetRepsMin...current.targetRepsMax,
                    demoAssetId: current.demoAssetId,
                    onSetLogged: { set in persist(set, for: current) }
                )
                .id(current.id) // forces a fresh view (and fresh @State) per exercise —
                                 // without this, SwiftUI reuses the old exercise's
                                 // weight/rep/rest state instead of resetting it
                .safeAreaInset(edge: .bottom) {
                    advanceButton(isLast: exerciseIndex == exercises.count - 1)
                }
            }
        }
    }

    // Same quiet-text style as LogSetView's "Skip Rest" — an escape
    // hatch, not something that competes with the Done button.
    private func advanceButton(isLast: Bool) -> some View {
        Button(isLast ? "Finish Workout" : "Next Exercise") {
            advance()
        }
        .font(GymTheme.labelFont)
        .foregroundColor(GymTheme.textSecondary)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(GymTheme.background)
    }

    private func persist(_ set: LoggedSet, for exercise: SessionExercise) {
        Database.shared.insertWorkoutSet(
            sessionId: session.id,
            exerciseId: set.exerciseId,
            setNumber: set.setNumber,
            reps: set.reps,
            weightKg: set.weightKg,
            rpe: nil,
            isWarmup: set.isWarmup,
            restSeconds: nil
        )
        loggedSets.append(set)

        // Auto-advance once the templated set count for this exercise is
        // hit — avoids an extra tap in the common case. "Next Exercise"
        // above still covers doing more/fewer sets than planned.
        let completedForExercise = loggedSets.filter { $0.exerciseId == exercise.id && !$0.isWarmup }.count
        if completedForExercise >= exercise.targetSets {
            advance()
        }
    }

    private func advance() {
        if exerciseIndex < exercises.count - 1 {
            exerciseIndex += 1
        } else {
            finishSession()
        }
    }

    private func finishSession() {
        let endTime = Date()
        var finished = session
        finished.endTime = endTime

        Task {
            let duration = endTime.timeIntervalSince(session.startTime)
            let estimatedCalories = await healthKit.estimateCalories(duration: duration)
            let healthKitUUID = await healthKit.saveWorkout(
                startDate: session.startTime,
                endDate: endTime,
                totalCalories: estimatedCalories
            )
            Database.shared.endSession(sessionId: session.id, endTime: endTime, healthKitUUID: healthKitUUID)
            finished.healthKitUUID = healthKitUUID
            onSessionFinished(finished, loggedSets)
        }
    }
}
