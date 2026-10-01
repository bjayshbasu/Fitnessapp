import SwiftUI
import SwiftData

// Works out personal records from finished workouts.
enum PersonalRecords {
    enum Kind: String {
        case heaviest = "Heaviest weight"
        case oneRepMax = "Best est. 1RM"
        case volume = "Most volume"

        var symbol: String {
            switch self {
            case .heaviest: "scalemass.fill"
            case .oneRepMax: "bolt.fill"
            case .volume: "square.stack.3d.up.fill"
            }
        }
    }

    // A workout where you beat an exercise's heaviest weight or best est. 1RM.
    // At most one per exercise per workout, so one great set isn't counted twice.
    struct Event: Identifiable {
        let id = UUID()
        let date: Date
        let exercise: String
        let kinds: [Kind]
        let weight: Double
        let reps: Int
        let oneRepMaxKg: Double
    }

    // All-time bests for one exercise.
    struct Best: Identifiable {
        let exercise: String
        var heaviest: (weight: Double, reps: Int, date: Date)
        var oneRepMax: (value: Double, date: Date)
        var volume: (value: Double, date: Date)
        var workouts: Int
        var id: String { exercise }
    }

    struct Summary {
        var events: [Event] = []
        var bests: [String: Best] = [:]
    }

    // Walks workouts oldest first. The first time you log an exercise sets the
    // baseline; each later improvement counts as a PR.
    static func compute(_ sessions: [WorkoutSession]) -> Summary {
        var summary = Summary()
        let ordered = sessions.filter { !$0.inProgress }.sorted { $0.date < $1.date }
        for session in ordered {
            for name in session.exerciseNames {
                let sets = session.sets(for: name).filter { $0.isDone && $0.weight > 0 && $0.reps > 0 }
                guard let heaviest = sets.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }),
                      let best1RM = sets.max(by: { $0.estimatedOneRepMaxKg < $1.estimatedOneRepMaxKg })
                else { continue }
                let volume = sets.reduce(0) { $0 + $1.volumeKg }

                guard var best = summary.bests[name] else {
                    summary.bests[name] = Best(exercise: name,
                                               heaviest: (heaviest.weight, heaviest.reps, session.date),
                                               oneRepMax: (best1RM.estimatedOneRepMaxKg, session.date),
                                               volume: (volume, session.date),
                                               workouts: 1)
                    continue
                }
                best.workouts += 1
                var kinds: [Kind] = []
                if heaviest.weight > best.heaviest.weight {
                    best.heaviest = (heaviest.weight, heaviest.reps, session.date)
                    kinds.append(.heaviest)
                }
                if best1RM.estimatedOneRepMaxKg > best.oneRepMax.value + 0.01 {
                    best.oneRepMax = (best1RM.estimatedOneRepMaxKg, session.date)
                    kinds.append(.oneRepMax)
                }
                // Volume bests are shown but don't count as PRs: an extra set would earn one.
                if volume > best.volume.value + 0.01 {
                    best.volume = (volume, session.date)
                }
                if !kinds.isEmpty {
                    let top = kinds.contains(.heaviest) ? heaviest : best1RM
                    summary.events.append(Event(date: session.date, exercise: name, kinds: kinds,
                                                weight: top.weight, reps: top.reps,
                                                oneRepMaxKg: best1RM.estimatedOneRepMaxKg))
                }
                summary.bests[name] = best
            }
        }
        return summary
    }

    // Best estimated 1RM per exercise, for spotting a PR live during a workout.
    static func bestOneRepMax(in sessions: [WorkoutSession]) -> [String: Double] {
        var bests: [String: Double] = [:]
        for session in sessions where !session.inProgress {
            for set in session.sets where set.isDone && set.weight > 0 && set.reps > 0 {
                bests[set.exerciseName] = max(bests[set.exerciseName] ?? 0, set.estimatedOneRepMaxKg)
            }
        }
        return bests
    }
}

// Progress › Personal Records.
struct RecordsView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.inProgress == false })
    private var sessions: [WorkoutSession]
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    @State private var search = ""

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    var body: some View {
        let summary = PersonalRecords.compute(sessions)
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let bests = summary.bests.values
            .filter { term.isEmpty || $0.exercise.localizedCaseInsensitiveContains(term) }
            .sorted { $0.oneRepMax.date > $1.oneRepMax.date }
        let recent = summary.events
            .filter { term.isEmpty || $0.exercise.localizedCaseInsensitiveContains(term) }
            .sorted { $0.date > $1.date }

        List {
            if !recent.isEmpty {
                Section {
                    ForEach(recent.prefix(15)) { event in
                        HStack(spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.exercise)
                                    .font(.subheadline.bold())
                                Text(text(for: event))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(event.date.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Recent PRs")
                } footer: {
                    Text("\(summary.events.count) personal record\(summary.events.count == 1 ? "" : "s") so far.")
                }
            }

            Section("All-time bests") {
                ForEach(bests) { best in
                    NavigationLink {
                        ExerciseProgressView(exerciseName: best.exercise)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(best.exercise)
                                .font(.headline)
                            HStack(spacing: 16) {
                                stat("Heaviest", "\(unit.text(fromKg: best.heaviest.weight)) × \(best.heaviest.reps)")
                                stat("Est. 1RM", unit.text(fromKg: best.oneRepMax.value))
                                stat("Volume", unit.wholeText(fromKg: best.volume.value))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Personal Records")
        .searchable(text: $search, prompt: "Search exercises")
        .overlay {
            if summary.bests.isEmpty {
                ContentUnavailableView("No records yet", systemImage: "trophy",
                                       description: Text("Finish a workout with weights to start setting records."))
            }
        }
    }

    private func text(for event: PersonalRecords.Event) -> String {
        let set = "\(unit.text(fromKg: event.weight)) × \(event.reps)"
        return event.kinds.contains(.heaviest)
            ? "Heaviest: \(set)"
            : "Best est. 1RM \(unit.text(fromKg: event.oneRepMaxKg)) (\(set))"
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
        }
    }
}

// A quick look at an exercise's past, opened from a workout.
struct ExerciseHistorySheet: View {
    let exerciseName: String

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<WorkoutSession> { $0.inProgress == false },
           sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    var body: some View {
        let past = sessions.compactMap { session -> (date: Date, sets: [LoggedSet])? in
            let sets = session.sets(for: exerciseName).filter(\.isDone)
            return sets.isEmpty ? nil : (session.date, sets)
        }
        let best = PersonalRecords.compute(sessions).bests[exerciseName]

        NavigationStack {
            List {
                if let best {
                    Section("Bests") {
                        LabeledContent("Heaviest set", value: "\(unit.text(fromKg: best.heaviest.weight)) × \(best.heaviest.reps)")
                        LabeledContent("Best est. 1RM", value: unit.text(fromKg: best.oneRepMax.value))
                        LabeledContent("Most volume", value: unit.wholeText(fromKg: best.volume.value))
                    }
                }
                Section("Recent workouts") {
                    ForEach(Array(past.prefix(8).enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline.bold())
                            Text(SetSummary.text(entry.sets, unit: unit))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    NavigationLink("Charts and full history") {
                        ExerciseProgressView(exerciseName: exerciseName)
                    }
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if past.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock",
                                           description: Text("This is your first time logging \(exerciseName)."))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// "60 kg × 8, 8, 7 · drop 45 kg × 10" style summaries.
enum SetSummary {
    static func text(_ sets: [LoggedSet], unit: WeightUnit) -> String {
        var parts: [String] = []
        var currentWeight: Double?
        var reps: [String] = []
        func flush() {
            if let currentWeight, !reps.isEmpty {
                parts.append("\(unit.text(fromKg: currentWeight)) × \(reps.joined(separator: ", "))")
            }
            reps = []
        }
        for set in sets.sorted(by: { $0.setNumber < $1.setNumber }) {
            if set.isDropSet {
                flush()
                currentWeight = nil
                parts.append("drop \(unit.text(fromKg: set.weight)) × \(set.reps)")
                continue
            }
            if set.weight != currentWeight { flush(); currentWeight = set.weight }
            reps.append("\(set.reps)")
        }
        flush()
        return parts.joined(separator: " · ")
    }
}
