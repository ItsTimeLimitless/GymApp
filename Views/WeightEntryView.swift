import SwiftUI

/// A single-field sheet for logging body weight — the thing GymApp does
/// instead of the Fitness app's own weight entry, which you've never
/// used. Saves locally to body_measurements and mirrors to Health's
/// bodyMass so Fitness sees it too, and so future calorie estimates
/// have something better than the flat fallback to work with.
struct WeightEntryView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var weightLb: Double

    init() {
        let existingKg = Database.shared.latestBodyWeightKg()
        let existingLb = existingKg.map { WeightUnit.kgToLb($0) }
        _weightLb = State(initialValue: existingLb ?? 150)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Text("BODY WEIGHT (LBS)")
                        .font(GymTheme.labelFont)
                        .foregroundColor(.secondary)

                    HStack(spacing: 28) {
                        Button {
                            weightLb = max(0, weightLb - 1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 20, weight: .bold))
                                .frame(width: 48, height: 48)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())
                        }

                        Text(String(format: "%.0f", weightLb))
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(minWidth: 110)

                        Button {
                            weightLb += 1
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold))
                                .frame(width: 48, height: 48)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())
                        }
                    }
                }

                Spacer()

                Button(action: save) {
                    Text("Save")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(GymTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .navigationTitle("Update weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let kg = WeightUnit.lbToKg(weightLb)
        Database.shared.insertBodyWeight(kg: kg)
        Task {
            await healthKit.writeBodyWeight(kg: kg)
        }
        dismiss()
    }
}
