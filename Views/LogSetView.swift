import SwiftUI

// MARK: - Design tokens
// Kept in one place so palette/type decisions are easy to swap later.
enum GymTheme {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.07)   // near-black, low glare
    static let surface    = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let accent     = Color(red: 0.91, green: 0.64, blue: 0.24)   // warm amber
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.55)

    static let numberFont = Font.system(size: 64, weight: .semibold, design: .rounded)
    static let labelFont  = Font.system(size: 15, weight: .medium)
}

// MARK: - Model (mirrors workout_sets table)
struct LoggedSet: Identifiable {
    let id = UUID()
    let exerciseId: Int
    var setNumber: Int
    var weightKg: Double
    var reps: Int
    var isWarmup: Bool = false
}

// MARK: - Unit conversion
// DB and HealthKit both store/expect kg (schema column is weight_kg) —
// lbs is a display-only concern, converted right at this UI boundary.
enum WeightUnit {
    static let kgPerLb = 0.45359237
    static func kgToLb(_ kg: Double) -> Double { kg / kgPerLb }
    static func lbToKg(_ lb: Double) -> Double { lb * kgPerLb }
}

// MARK: - Capture-mode screen: ONE question only — weight? reps? done?
struct LogSetView: View {
    let exerciseId: Int                  // so onSetLogged can carry it to the DB insert
    let exerciseName: String
    let suggestedWeightKg: Double        // pre-filled from last session's progression logic
    let targetReps: ClosedRange<Int>     // e.g. 8...10, shown as a quiet hint only
    let demoAssetId: String?             // bundled demo photos, if this exercise has them

    @State private var baseWeightLb: Double  // adjusted by the main ±5lb stepper
    @State private var fineLb: Double = 0    // 0, .25, .5, or .75 — one extra small plate
    @State private var reps: Int
    @State private var setNumber: Int = 1
    @State private var isResting = false
    @State private var restSecondsRemaining = 90

    var onSetLogged: (LoggedSet) -> Void

    init(exerciseId: Int, exerciseName: String, suggestedWeightKg: Double, targetReps: ClosedRange<Int>, demoAssetId: String? = nil, onSetLogged: @escaping (LoggedSet) -> Void) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.suggestedWeightKg = suggestedWeightKg
        self.targetReps = targetReps
        self.demoAssetId = demoAssetId
        self.onSetLogged = onSetLogged
        // Round to the nearest 5lb — matches standard plate increments,
        // avoids showing an odd number like "110.23" from the kg convert.
        let suggestedLb = (WeightUnit.kgToLb(suggestedWeightKg) / 5).rounded() * 5
        _baseWeightLb = State(initialValue: suggestedLb)
        _reps = State(initialValue: targetReps.upperBound)
    }

    private var totalWeightLb: Double { baseWeightLb + fineLb }

    var body: some View {
        ZStack {
            GymTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer()

                if isResting {
                    restTimer
                } else {
                    setLogger
                }

                Spacer()

                doneButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            // Small, out-of-the-way corner button — doesn't compete
            // with the weight/rep steppers, available before or
            // between sets alike.
            VStack {
                HStack {
                    Spacer()
                    ExercisePreviewButton(exerciseName: exerciseName, demoAssetId: demoAssetId)
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Header — exercise name + set count only. No menu, no tabs.
    private var header: some View {
        VStack(spacing: 4) {
            Text(exerciseName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(GymTheme.textPrimary)
            Text("Set \(setNumber) · target \(targetReps.lowerBound)–\(targetReps.upperBound) reps")
                .font(GymTheme.labelFont)
                .foregroundColor(GymTheme.textSecondary)
        }
        .padding(.top, 12)
    }

    // MARK: Core logger — two big steppers, nothing else
    private var setLogger: some View {
        VStack(spacing: 40) {
            VStack(spacing: 16) {
                valueStepper(
                    label: "WEIGHT (LBS)",
                    value: Binding(
                        get: { baseWeightLb },
                        set: { baseWeightLb = max(0, $0) }
                    ),
                    step: 5,
                    display: String(format: fineLb == 0 ? "%.0f" : "%.2f", totalWeightLb)
                )
                finePlateRow
            }

            valueStepper(
                label: "REPS",
                value: Binding(
                    get: { Double(reps) },
                    set: { reps = max(0, Int($0)) }
                ),
                step: 1,
                display: "\(reps)"
            )
        }
    }

    // MARK: Fine plate row — for the odd single 2.5lb plate on one side.
    // Toggle, not additive: only one of these is ever "on" at a time,
    // same as only being able to rack one extra small plate.
    private var finePlateRow: some View {
        HStack(spacing: 10) {
            fineChip(0.25)
            fineChip(0.5)
            fineChip(0.75)
        }
    }

    private func fineChip(_ amount: Double) -> some View {
        let isSelected = fineLb == amount
        return Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            fineLb = isSelected ? 0 : amount
        }) {
            Text("+\(String(format: "%.2f", amount).replacingOccurrences(of: "0.", with: "."))")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .black : GymTheme.textSecondary)
                .frame(width: 52, height: 32)
                .background(isSelected ? GymTheme.accent : GymTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func valueStepper(label: String, value: Binding<Double>, step: Double, display: String) -> some View {
        VStack(spacing: 12) {
            Text(label)
                .font(GymTheme.labelFont)
                .foregroundColor(GymTheme.textSecondary)

            HStack(spacing: 28) {
                stepButton(symbol: "minus") { value.wrappedValue -= step }

                Text(display)
                    .font(GymTheme.numberFont)
                    .foregroundColor(GymTheme.textPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 140)

                stepButton(symbol: "plus") { value.wrappedValue += step }
            }
        }
    }

    private func stepButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(GymTheme.textPrimary)
                .frame(width: 56, height: 56)
                .background(GymTheme.surface)
                .clipShape(Circle())
        }
    }

    // MARK: Done — logs the set and starts rest automatically (no separate action)
    private var doneButton: some View {
        Button(action: logSetAndStartRest) {
            Text("Done")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(GymTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .opacity(isResting ? 0.3 : 1)
        .disabled(isResting)
    }

    private func logSetAndStartRest() {
        let weightKg = WeightUnit.lbToKg(totalWeightLb)
        onSetLogged(LoggedSet(exerciseId: exerciseId, setNumber: setNumber, weightKg: weightKg, reps: reps))
        setNumber += 1
        isResting = true
        restSecondsRemaining = 90
        startRestCountdown()
    }

    // MARK: Rest timer — replaces the logger view entirely; no dual-purpose screen
    private var restTimer: some View {
        VStack(spacing: 16) {
            Text("REST")
                .font(GymTheme.labelFont)
                .foregroundColor(GymTheme.textSecondary)
            Text(timeString(restSecondsRemaining))
                .font(GymTheme.numberFont)
                .foregroundColor(GymTheme.accent)
                .monospacedDigit()
            Button("Skip Rest") { isResting = false }
                .font(GymTheme.labelFont)
                .foregroundColor(GymTheme.textSecondary)
                .padding(.top, 8)
        }
    }

    private func startRestCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if restSecondsRemaining > 0 {
                restSecondsRemaining -= 1
            } else {
                timer.invalidate()
                isResting = false
            }
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Preview
#Preview {
    LogSetView(
        exerciseId: 1,
        exerciseName: "Barbell Squat",
        suggestedWeightKg: 50,
        targetReps: 8...10,
        demoAssetId: "Barbell_Full_Squat",
        onSetLogged: { set in
            print("Logged: \(set.weightKg)kg x \(set.reps)")
        }
    )
}
