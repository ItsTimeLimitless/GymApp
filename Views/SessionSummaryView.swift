import SwiftUI
import Charts

struct SessionSummaryView: View {
    let session: WorkoutSession
    let loggedSets: [LoggedSet]

    @State private var notes: String = ""
    @State private var newPRs: [String] = []   // exercise names that hit a new PR this session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                if !newPRs.isEmpty {
                    prBanner
                }

                volumeChart

                notesField
            }
            .padding()
        }
        .navigationTitle("Session Summary")
        .onAppear(perform: checkForPRs)
    }

    // MARK: PR recap — computed once, shown as a reward, not live
    private var prBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🏆 New PRs today")
                .font(.headline)
            ForEach(newPRs, id: \.self) { name in
                Text(name)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Simple volume-over-session chart
    private var volumeChart: some View {
        VStack(alignment: .leading) {
            Text("Sets this session")
                .font(.headline)
            Chart(loggedSets) { set in
                BarMark(
                    x: .value("Set", String(set.id.uuidString.prefix(4))),
                    y: .value("Weight (lbs)", WeightUnit.kgToLb(set.weightKg))
                )
            }
            .frame(height: 200)
        }
    }

    // MARK: Single optional note — not per-set
    private var notesField: some View {
        VStack(alignment: .leading) {
            Text("How did that feel?")
                .font(.headline)
            TextField("Optional note...", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func checkForPRs() {
        // Compare today's top set per exercise against personal_records.
        // Left as a stub — wire up against Database.shared once exercise
        // grouping is in place.
    }
}
