import SwiftUI
import SwiftData
import Charts

// Screen 5: pick an exercise to see how your strength has changed.
struct ProgressTabView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.inProgress == false },
           sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]
    @State private var search = ""
    @AppStorage(WeeklyGoal.key) private var weeklyGoal = 3

    private struct ExerciseSummary: Identifiable {
        let name: String
        let lastDate: Date
        let workouts: Int
        var id: String { name }
    }

    // Each exercise you've logged, most recently trained first.
    private var exercises: [ExerciseSummary] {
        var lastDate: [String: Date] = [:]
        var counts: [String: Int] = [:]
        for session in sessions {
            for name in Set(session.completedSets.map(\.exerciseName)) {
                counts[name, default: 0] += 1
                if lastDate[name] == nil { lastDate[name] = session.date }
            }
        }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastDate
            .map { ExerciseSummary(name: $0.key, lastDate: $0.value, workouts: counts[$0.key] ?? 0) }
            .filter { term.isEmpty || $0.name.localizedCaseInsensitiveContains(term) }
            .sorted { $0.lastDate > $1.lastDate }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Section {
                        NavigationLink {
                            AchievementsView()
                        } label: {
                            LevelCard(stats: Rewards.Stats(sessions: sessions, weeklyGoal: weeklyGoal))
                        }
                        NavigationLink {
                            StatsView()
                        } label: {
                            Label("Stats & Charts", systemImage: "chart.bar.xaxis")
                        }
                        NavigationLink {
                            RecordsView()
                        } label: {
                            Label("Personal Records", systemImage: "trophy")
                        }
                    }
                }

                Section {
                    ForEach(exercises) { exercise in
                        NavigationLink {
                            ExerciseProgressView(exerciseName: exercise.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .font(.headline)
                                Text("\(exercise.workouts) workout\(exercise.workouts == 1 ? "" : "s") · last \(exercise.lastDate.formatted(.relative(presentation: .named)))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Exercises")
                } footer: {
                    if sessions.isEmpty {
                        Text("Finish a workout to start tracking your progress.")
                    }
                }
            }
            .navigationTitle("Progress")
            .searchable(text: $search, prompt: "Search exercises")
            .overlay {
                if !sessions.isEmpty && exercises.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }
}

// What the chart plots.
enum ProgressMetric: String, CaseIterable, Identifiable {
    case heaviest = "Heaviest"
    case oneRepMax = "Est. 1RM"
    case volume = "Volume"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .heaviest: "Heaviest weight lifted in each workout."
        case .oneRepMax: "Estimated one-rep max from your best set (Epley formula), so more reps at a lighter weight still count."
        case .volume: "Total weight moved (weight × reps) across all sets in each workout."
        }
    }
}

// One point on the chart: one workout that included this exercise.
struct ProgressPoint: Identifiable {
    let id: PersistentIdentifier
    let date: Date
    let heaviest: LoggedSet
    let bestOneRepMaxKg: Double
    let volumeKg: Double

    func valueKg(for metric: ProgressMetric) -> Double {
        switch metric {
        case .heaviest: heaviest.weight
        case .oneRepMax: bestOneRepMaxKg
        case .volume: volumeKg
        }
    }
}

struct ExerciseProgressView: View {
    let exerciseName: String
    @Query(filter: #Predicate<WorkoutSession> { $0.inProgress == false },
           sort: \WorkoutSession.date)
    private var sessions: [WorkoutSession]
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage("progressMetric") private var metricRaw = ProgressMetric.oneRepMax.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var metric: ProgressMetric { ProgressMetric(rawValue: metricRaw) ?? .oneRepMax }

    private var points: [ProgressPoint] {
        sessions.compactMap { session -> ProgressPoint? in
            let sets = session.sets(for: exerciseName).filter(\.isDone)
            guard let heaviest = sets.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }) else {
                return nil
            }
            return ProgressPoint(id: session.persistentModelID,
                                 date: session.date,
                                 heaviest: heaviest,
                                 bestOneRepMaxKg: sets.map(\.estimatedOneRepMaxKg).max() ?? 0,
                                 volumeKg: sets.reduce(0) { $0 + $1.volumeKg })
        }
    }

    var body: some View {
        List {
            if !points.isEmpty {
                Section("Personal records") {
                    if let best = points.max(by: { ($0.heaviest.weight, $0.heaviest.reps) < ($1.heaviest.weight, $1.heaviest.reps) }) {
                        recordRow("Heaviest set",
                                  value: "\(unit.text(fromKg: best.heaviest.weight)) × \(best.heaviest.reps)",
                                  date: best.date)
                    }
                    if let best = points.max(by: { $0.bestOneRepMaxKg < $1.bestOneRepMaxKg }) {
                        recordRow("Best est. 1RM", value: unit.text(fromKg: best.bestOneRepMaxKg), date: best.date)
                    }
                    if let best = points.max(by: { $0.volumeKg < $1.volumeKg }) {
                        recordRow("Most volume", value: unit.wholeText(fromKg: best.volumeKg), date: best.date)
                    }
                }
            }

            Section {
                Picker("Chart", selection: $metricRaw) {
                    ForEach(ProgressMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                Chart(points) { point in
                    let value = unit.display(fromKg: point.valueKg(for: metric))
                    LineMark(x: .value("Date", point.date),
                             y: .value("\(metric.rawValue) (\(unit.rawValue))", value))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date),
                              y: .value("\(metric.rawValue) (\(unit.rawValue))", value))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)
                .padding(.vertical, 8)
                .accessibilityLabel("\(metric.rawValue) chart for \(exerciseName)")
            } header: {
                Text("Trend")
            } footer: {
                Text(points.count < 2
                     ? "Log this exercise again to see a trend. \(metric.explanation)"
                     : metric.explanation)
            }

            Section("Workouts") {
                ForEach(points.reversed()) { point in
                    HStack {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text("\(unit.text(fromKg: point.heaviest.weight)) × \(point.heaviest.reps)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recordRow(_ title: String, value: String, date: Date) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.bold())
            }
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
