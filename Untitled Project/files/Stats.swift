import SwiftUI
import SwiftData
import Charts

// Progress › Stats & Charts.
struct StatsView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.inProgress == false },
           sort: \WorkoutSession.date)
    private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(WeeklyGoal.key) private var weeklyGoal = 3
    @AppStorage("statsRange") private var rangeRaw = StatsRange.twelveWeeks.rawValue
    @AppStorage("statsMetric") private var metricRaw = WeeklyMetric.volume.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var range: StatsRange { StatsRange(rawValue: rangeRaw) ?? .twelveWeeks }
    private var metric: WeeklyMetric { WeeklyMetric(rawValue: metricRaw) ?? .volume }

    enum StatsRange: String, CaseIterable, Identifiable {
        case fourWeeks = "4W", twelveWeeks = "12W", sixMonths = "6M", year = "1Y", all = "All"
        var id: String { rawValue }

        var start: Date? {
            let calendar = Calendar.current
            switch self {
            case .fourWeeks: return calendar.date(byAdding: .weekOfYear, value: -4, to: .now)
            case .twelveWeeks: return calendar.date(byAdding: .weekOfYear, value: -12, to: .now)
            case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: .now)
            case .year: return calendar.date(byAdding: .year, value: -1, to: .now)
            case .all: return nil
            }
        }
    }

    enum WeeklyMetric: String, CaseIterable, Identifiable {
        case volume = "Volume", workouts = "Workouts", sets = "Sets", minutes = "Minutes"
        var id: String { rawValue }
    }

    struct WeekPoint: Identifiable {
        let week: Date
        var workouts = 0
        var sets = 0
        var volumeKg: Double = 0
        var minutes: Double = 0
        var id: Date { week }
    }

    struct GroupPoint: Identifiable {
        let group: String
        let sets: Int
        var id: String { group }
    }

    struct ExercisePoint: Identifiable {
        let name: String
        let sets: Int
        var id: String { name }
    }

    private var inRange: [WorkoutSession] {
        guard let start = range.start else { return sessions }
        return sessions.filter { $0.date >= start }
    }

    var body: some View {
        let selected = inRange
        let weeks = weekly(selected)
        let groups = muscleGroups(selected)
        let top = topExercises(selected)
        let prCount = PersonalRecords.compute(sessions).events
            .filter { range.start == nil || $0.date >= range.start! }.count
        let durations = selected.compactMap(\.duration)
        let streak = WeeklyGoal.status(sessions: sessions, goal: weeklyGoal).streak

        List {
            Section {
                Picker("Range", selection: $rangeRaw) {
                    ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    tile("Workouts", "\(selected.count)", symbol: "figure.strengthtraining.traditional")
                    tile("Volume", unit.wholeText(fromKg: selected.reduce(0) { $0 + $1.volumeKg }), symbol: "scalemass")
                    tile("Sets", "\(selected.reduce(0) { $0 + $1.completedSets.count })", symbol: "square.stack.3d.up")
                    tile("Avg. workout", durations.isEmpty ? "–" : AppFormat.duration(durations.reduce(0, +) / Double(durations.count)), symbol: "timer")
                    tile("New PRs", "\(prCount)", symbol: "trophy")
                    tile("Week streak", "\(streak)", symbol: "flame")
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Chart", selection: $metricRaw) {
                    ForEach(WeeklyMetric.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                Chart(weeks) { point in
                    BarMark(x: .value("Week", point.week, unit: .weekOfYear),
                            y: .value(metric.rawValue, value(of: point)))
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(4)
                    if metric == .workouts {
                        RuleMark(y: .value("Goal", weeklyGoal))
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
                .frame(height: 200)
                .padding(.vertical, 8)
                .accessibilityLabel("\(metric.rawValue) per week")
            } header: {
                Text("Per week")
            } footer: {
                Text(metric == .workouts ? "The dashed line is your weekly goal." : footer)
            }

            if !groups.isEmpty {
                Section {
                    Chart(groups) { point in
                        BarMark(x: .value("Sets", point.sets), y: .value("Muscle group", point.group))
                            .foregroundStyle(by: .value("Muscle group", point.group))
                            .annotation(position: .trailing) {
                                Text("\(point.sets)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                    }
                    .chartLegend(.hidden)
                    .frame(height: CGFloat(groups.count) * 30 + 20)
                    .padding(.vertical, 8)
                } header: {
                    Text("Sets by muscle group")
                } footer: {
                    Text("Helps you spot muscles you train less often.")
                }
            }

            if !top.isEmpty {
                Section("Most trained") {
                    ForEach(top) { point in
                        NavigationLink {
                            ExerciseProgressView(exerciseName: point.name)
                        } label: {
                            LabeledContent(point.name, value: "\(point.sets) sets")
                        }
                    }
                }
            }
        }
        .navigationTitle("Stats & Charts")
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No workouts yet", systemImage: "chart.bar",
                                       description: Text("Finish a workout to see your stats."))
            }
        }
    }

    private var footer: String {
        switch metric {
        case .volume: "Total weight lifted (weight × reps) each week, in \(unit.rawValue)."
        case .sets: "Completed sets each week."
        case .minutes: "Time spent training each week."
        case .workouts: ""
        }
    }

    private func value(of point: WeekPoint) -> Double {
        switch metric {
        case .volume: unit.display(fromKg: point.volumeKg)
        case .workouts: Double(point.workouts)
        case .sets: Double(point.sets)
        case .minutes: point.minutes.rounded()
        }
    }

    // Every week in the range, including empty ones, so gaps show up.
    private func weekly(_ selected: [WorkoutSession]) -> [WeekPoint] {
        let calendar = Calendar.current
        var points: [Date: WeekPoint] = [:]
        for session in selected {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: session.date)?.start else { continue }
            var point = points[week] ?? WeekPoint(week: week)
            point.workouts += 1
            point.sets += session.completedSets.count
            point.volumeKg += session.volumeKg
            point.minutes += (session.duration ?? 0) / 60
            points[week] = point
        }
        guard let first = (range.start ?? selected.first?.date),
              var week = calendar.dateInterval(of: .weekOfYear, for: first)?.start,
              let last = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        var result: [WeekPoint] = []
        while week <= last {
            result.append(points[week] ?? WeekPoint(week: week))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
            week = next
        }
        return result
    }

    private func muscleGroups(_ selected: [WorkoutSession]) -> [GroupPoint] {
        let groupOf = Dictionary(exercises.map { ($0.name.lowercased(), $0.groupName) },
                                 uniquingKeysWith: { first, _ in first })
        var counts: [String: Int] = [:]
        for session in selected {
            for set in session.completedSets {
                counts[groupOf[set.exerciseName.lowercased()] ?? MuscleGroup.other, default: 0] += 1
            }
        }
        return counts.map { GroupPoint(group: $0.key, sets: $0.value) }
            .sorted { $0.sets > $1.sets }
    }

    private func topExercises(_ selected: [WorkoutSession]) -> [ExercisePoint] {
        var counts: [String: Int] = [:]
        for session in selected {
            for set in session.completedSets { counts[set.exerciseName, default: 0] += 1 }
        }
        return counts.map { ExercisePoint(name: $0.key, sets: $0.value) }
            .sorted { $0.sets > $1.sets }
            .prefix(5)
            .map { $0 }
    }

    private func tile(_ title: String, _ value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
