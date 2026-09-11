import SwiftUI
import SQLite3

struct TemplatePickerView: View {
    var onStart: (WorkoutSession, [SessionExercise]) -> Void

    @State private var templates: [WorkoutTemplate] = []
    @State private var exercisesByTemplate: [Int: [SessionExercise]] = [:]
    @State private var suggestedTemplateId: Int?
    @State private var completedCount = 0
    @State private var showingWeightEntry = false
    @State private var showingAPISettings = false
    @State private var showingDiagnosticLog = false

    var body: some View {
        Group {
            if templates.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No workouts loaded")
                        .font(.headline)
                    Text("Something went wrong during setup. Screenshot this and send it over:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Divider()
                    diagnosticView
                }
                .padding()
            } else {
                List {
                    Section {
                        ForEach(templates) { template in
                            NavigationLink {
                                WorkoutPreviewView(template: template, onStart: { template, exercises in
                                    let session = startSession(from: template)
                                    onStart(session, exercises)
                                })
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(GymTheme.accent.opacity(0.15))
                                        Image(systemName: "dumbbell.fill")
                                            .font(.system(size: 19))
                                            .foregroundColor(GymTheme.accent)
                                    }
                                    .frame(width: 46, height: 46)

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
                                            Text(template.name)
                                                .font(.system(size: 17, weight: .semibold))
                                            if template.id == suggestedTemplateId {
                                                Text("NEXT")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(GymTheme.accent)
                                                    .foregroundColor(.black)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        // A quick row of thumbnails so the
                                        // workout is recognizable at a
                                        // glance, not just by name.
                                        if let exercises = exercisesByTemplate[template.id], !exercises.isEmpty {
                                            HStack(spacing: 4) {
                                                ForEach(exercises.prefix(4)) { exercise in
                                                    ExerciseThumbnailView(demoAssetId: exercise.demoAssetId, size: 24)
                                                }
                                                if exercises.count > 4 {
                                                    Text("+\(exercises.count - 4)")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    } header: {
                        if completedCount > 0 {
                            Text("\(completedCount) workout\(completedCount == 1 ? "" : "s") completed")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Today's Workout")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showingDiagnosticLog = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    Button {
                        showingAPISettings = true
                    } label: {
                        Image(systemName: "key")
                    }
                    Button("Weight") { showingWeightEntry = true }
                }
            }
        }
        .sheet(isPresented: $showingWeightEntry) {
            WeightEntryView()
        }
        .sheet(isPresented: $showingAPISettings) {
            APISettingsView()
        }
        .sheet(isPresented: $showingDiagnosticLog) {
            NavigationStack {
                diagnosticView
                    .navigationTitle("Diagnostic Log")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingDiagnosticLog = false }
                        }
                    }
            }
        }
        .onAppear(perform: loadTemplates)
    }

    // The raw log lines — reused both in the empty-state screen and in
    // the always-available "Diagnostic Log" sheet. Lets a problem be
    // screenshotted and sent over instead of guessed at, since a
    // sideloaded app has no console to check.
    private var diagnosticView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(Database.diagnosticLog.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.footnote, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadTemplates() {
        var results: [WorkoutTemplate] = []
        Database.shared.query("SELECT id, name, goal, notes FROM workout_templates") { statement in
            let id = Int(sqlite3_column_int(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let goal = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let notes = sqlite3_column_text(statement, 3).map { String(cString: $0) }
            results.append(WorkoutTemplate(id: id, name: name, goal: goal, notes: notes))
        }
        templates = results
        for template in results {
            exercisesByTemplate[template.id] = Database.shared.templateExercises(templateId: template.id)
        }

        completedCount = Database.shared.totalCompletedSessionsCount()
        if let lastTemplateId = Database.shared.mostRecentCompletedSessionTemplateId() {
            // Alternate — suggest whichever template ISN'T the one just
            // done. Falls back to the first template if somehow the
            // last one used no longer exists.
            suggestedTemplateId = results.first(where: { $0.id != lastTemplateId })?.id ?? results.first?.id
        } else {
            // No completed sessions yet — start the rotation at the
            // first template (Workout A).
            suggestedTemplateId = results.first?.id
        }
    }

    private func startSession(from template: WorkoutTemplate) -> WorkoutSession {
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now)
        Database.shared.execute(
            "INSERT INTO workout_sessions (template_id, start_time) VALUES (?, ?)"
        ) { statement in
            sqlite3_bind_int(statement, 1, Int32(template.id))
            sqlite3_bind_text(statement, 2, iso, -1, SQLITE_TRANSIENT)
        }
        let sessionId = Database.shared.lastInsertId
        return WorkoutSession(id: sessionId, templateId: template.id, startTime: now)
    }
}
