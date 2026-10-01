import SwiftUI
import SwiftData
import Charts

// Screen 5: pick an exercise to see how your strength has changed.
struct ProgressTabView: View {
    @Query private var sessions: [WorkoutSession]

    private var exerciseNames: [String] {
        Set(sessions.flatMap { $0.sets.map(\.exerciseName) }).sorted()
    }

    var body: some View {
        NavigationStack {
            List(exerciseNames, id: \.self) { name in
                NavigationLink(name) {
                    ExerciseProgressView(exerciseName: name)
                }
            }
            .navigationTitle("Progress")
            .overlay {
                if exerciseNames.isEmpty {
                    ContentUnavailableView(
                        "No data yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Finish a workout to start tracking your progress.")
                    )
                }
            }
        }
    }
}

// One point on the chart: your heaviest set in a single workout.
struct ProgressPoint: Identifiable {
    let date: Date
    let weight: Double
    let reps: Int
    var id: Date { date }
}

struct ExerciseProgressView: View {
    let exerciseName: String
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var points: [ProgressPoint] {
        sessions.compactMap { session -> ProgressPoint? in
            let sets = session.sets.filter { $0.exerciseName == exerciseName }
            guard let best = sets.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }) else {
                return nil
            }
            return ProgressPoint(date: session.date, weight: best.weight, reps: best.reps)
        }
    }

    var body: some View {
        List {
            if let record = points.max(by: { $0.weight < $1.weight }) {
                Section("Personal best") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(unit.text(fromKg: record.weight)) × \(record.reps)")
                            .font(.title2.bold())
                        Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Heaviest set per workout") {
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight (\(unit.rawValue))", unit.display(fromKg: point.weight))
                    )
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight (\(unit.rawValue))", unit.display(fromKg: point.weight))
                    )
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)
                .padding(.vertical, 8)
            }

            Section("Workouts") {
                ForEach(points.reversed()) { point in
                    HStack {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text("\(unit.text(fromKg: point.weight)) × \(point.reps)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
