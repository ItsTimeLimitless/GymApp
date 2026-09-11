import SwiftUI

/// Shown after picking a template from the home screen, before any
/// workout_sessions row exists — lets you review the full plan ahead of
/// time and swap an exercise if you already know a machine's going to
/// be busy. Nothing is written to the database until "Start workout".
struct WorkoutPreviewView: View {
    let template: WorkoutTemplate
    var onStart: (WorkoutTemplate, [SessionExercise]) -> Void

    @State private var exercises: [SessionExercise] = []
    @State private var swapTarget: SessionExercise?

    var body: some View {
        List {
            ForEach(exercises) { exercise in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.headline)
                        Text("\(exercise.targetSets) sets × \(exercise.targetRepsMin)–\(exercise.targetRepsMax) reps")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    ExercisePreviewButton(exerciseName: exercise.name, demoAssetId: exercise.demoAssetId)
                    Button("Swap") { swapTarget = exercise }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(template.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Start Workout") { onStart(template, exercises) }
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .sheet(item: $swapTarget) { target in
            ExerciseSwapView(current: target) { replacement in
                if let index = exercises.firstIndex(where: { $0.id == target.id }) {
                    exercises[index] = replacement
                }
            }
        }
        .onAppear {
            exercises = Database.shared.templateExercises(templateId: template.id)
        }
    }
}

/// Picks a same-muscle-group replacement for one exercise. Sets/reps
/// carry over unchanged from the original slot — only the exercise
/// itself (and therefore the equipment it needs) changes. Also offers
/// photo-ID for a machine that isn't in the library at all yet.
private struct ExerciseSwapView: View {
    let current: SessionExercise
    var onPick: (SessionExercise) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showingCamera = false
    @State private var isIdentifying = false
    @State private var identified: EquipmentIdentifier.IdentifiedEquipment?
    @State private var identifyErrorMessage: String?

    var body: some View {
        NavigationStack {
            let alternates = Database.shared.alternateExercises(excluding: current.id)
            List {
                Section {
                    if isIdentifying {
                        HStack {
                            ProgressView()
                            Text("Identifying…")
                                .foregroundColor(.secondary)
                        }
                    } else if let identified {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(identified.name).font(.headline)
                            Text("Captioned from your photo — no usage instructions with this simpler model.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        Button("Use this exercise") { useIdentified(identified) }
                    } else {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take a photo to identify", systemImage: "camera")
                        }
                        if let identifyErrorMessage {
                            Text(identifyErrorMessage)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                    }
                }

                if !alternates.isEmpty {
                    Section("Already in the library") {
                        ForEach(alternates, id: \.id) { alternate in
                            Button(alternate.name) { pick(alternate.id, alternate.name, alternate.incrementKg, alternate.demoAssetId) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Swap \(current.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCaptureView(onCapture: handleCapture)
                    .ignoresSafeArea()
            }
        }
    }

    private func pick(_ id: Int, _ name: String, _ incrementKg: Double, _ demoAssetId: String?) {
        onPick(SessionExercise(
            id: id,
            name: name,
            targetSets: current.targetSets,
            targetRepsMin: current.targetRepsMin,
            targetRepsMax: current.targetRepsMax,
            incrementKg: incrementKg,
            demoAssetId: demoAssetId
        ))
        dismiss()
    }

    private func handleCapture(_ image: UIImage) {
        isIdentifying = true
        identifyErrorMessage = nil
        Task {
            do {
                identified = try await EquipmentIdentifier.identify(image: image)
            } catch {
                identifyErrorMessage = error.localizedDescription
            }
            isIdentifying = false
        }
    }

    private func useIdentified(_ result: EquipmentIdentifier.IdentifiedEquipment) {
        guard let muscleGroupId = Database.shared.muscleGroupId(forExerciseId: current.id) else { return }
        let equipmentId = Database.shared.insertIdentifiedEquipment(name: result.name)
        Database.shared.logMachineRecognition(equipmentId: equipmentId, rawResponse: result.rawResponse)
        let exerciseId = Database.shared.insertCustomExercise(
            name: result.name,
            muscleGroupId: muscleGroupId,
            equipmentId: equipmentId,
            instructions: "Identified from a photo — no detailed usage instructions available.",
            incrementKg: current.incrementKg // best guess — same as the exercise it's replacing
        )
        // No bundled demo photo exists for a machine identified from
        // your own photo — the photo you just took already serves that
        // purpose for this one.
        pick(exerciseId, result.name, current.incrementKg, nil)
    }
}
