import SwiftUI

struct ContentView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var activeSession: (session: WorkoutSession, exercises: [SessionExercise])?
    @State private var completedSession: (session: WorkoutSession, sets: [LoggedSet])?

    var body: some View {
        NavigationStack {
            if let completed = completedSession {
                SessionSummaryView(session: completed.session, loggedSets: completed.sets)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") { completedSession = nil }
                        }
                    }
            } else if let active = activeSession {
                WorkoutSessionView(session: active.session, exercises: active.exercises, onSessionFinished: { finished, sets in
                    activeSession = nil
                    completedSession = (finished, sets)
                })
                .navigationTitle("Workout")
            } else {
                TemplatePickerView(onStart: { session, exercises in
                    activeSession = (session, exercises)
                })
            }
        }
        .task {
            await healthKit.requestAuthorization()
        }
        // One consistent accent color across every native control —
        // buttons, nav links, list accessories, toggles — instead of a
        // mix of default iOS blue and the amber used in the workout
        // screens. This is most of what makes an app feel intentionally
        // designed rather than assembled from mismatched defaults.
        .tint(GymTheme.accent)
    }
}

#Preview {
    ContentView()
        .environmentObject(HealthKitManager.shared)
}
