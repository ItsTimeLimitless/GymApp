import Foundation

/// One past session's result for a single exercise — the weight used and
/// every working (non-warmup) set's reps, most sets first in whatever
/// order they were logged.
struct SessionPerformance {
    let weightKg: Double
    var reps: [Int]
}

/// The double-progression rule worked out earlier, made objective since
/// LogSetView doesn't capture RPE:
///
/// - Hit the TOP of the rep range on every set → move the weight one
///   increment in the "harder" direction next time.
/// - Missed the BOTTOM of the rep range at the same weight for 3
///   sessions running → that's the plateau signal, deload — move one
///   increment back toward "easier".
/// - Anything else (hit within range but not at the top, or an isolated
///   miss) → repeat the same weight.
/// - No history at all → nothing to suggest; that's the session-1
///   calibration case, where the person finds their own starting weight
///   via the steppers.
///
/// `incrementKg`'s sign encodes which direction is "harder": positive
/// for ordinary exercises (more weight = harder — most of them). For an
/// assisted machine (assisted pull-up, assisted dip) it's the opposite —
/// more weight on the stack means more help, so pass a NEGATIVE
/// increment there. Getting stronger then correctly means the suggested
/// weight goes down, and a deload correctly means it goes back up
/// (more assistance), not further down into "even less help while
/// already failing".
enum ProgressionEngine {
    static func suggestedWeightKg(
        history: [SessionPerformance],   // most recent session first
        targetReps: ClosedRange<Int>,
        incrementKg: Double
    ) -> Double? {
        guard let last = history.first, let lastWeight = last.reps.isEmpty ? nil : last.weightKg else {
            return nil
        }

        let hitTop = last.reps.allSatisfy { $0 >= targetReps.upperBound }
        if hitTop {
            return max(0, lastWeight + incrementKg)
        }

        let missedBottom = last.reps.contains { $0 < targetReps.lowerBound }
        if missedBottom {
            let consecutiveMissesAtThisWeight = history.prefix { session in
                approximatelyEqual(session.weightKg, lastWeight)
                    && session.reps.contains { $0 < targetReps.lowerBound }
            }.count
            if consecutiveMissesAtThisWeight >= 3 {
                // Deload moves toward "easier" — for a normal exercise
                // that's less weight (×0.9); for an assisted machine
                // (negative increment) "easier" means MORE assistance,
                // so the weight goes up instead (×1.1).
                let deloadFactor = incrementKg < 0 ? 1.1 : 0.9
                return max(0, lastWeight * deloadFactor)
            }
        }

        return lastWeight
    }

    private static func approximatelyEqual(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.01
    }
}
