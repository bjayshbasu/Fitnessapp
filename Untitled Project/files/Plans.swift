import SwiftUI
import SwiftData

// MARK: - Ready-made plans

// A proven training plan someone can add to their routines in one tap.
struct WorkoutPlan: Identifiable {
    struct Item {
        let exercise: String
        let group: String   // used if the exercise isn't in the library yet
        let sets: Int
        let reps: Int
    }

    struct Day {
        let name: String
        let items: [Item]
    }

    let id: String
    let name: String
    let summary: String
    let schedule: String
    let level: String
    let symbol: String
    let days: [Day]
}

enum WorkoutPlans {
    private static func item(_ exercise: String, _ group: String, _ sets: Int, _ reps: Int) -> WorkoutPlan.Item {
        WorkoutPlan.Item(exercise: exercise, group: group, sets: sets, reps: reps)
    }

    static let fullBody = WorkoutPlan(
        id: "full-body",
        name: "Beginner Full Body",
        summary: "Two full-body workouts you alternate. The quickest way to build a strength base and learn the main lifts.",
        schedule: "3 days a week, alternating A and B",
        level: "Beginner",
        symbol: "figure.strengthtraining.traditional",
        days: [
            .init(name: "Full Body A", items: [
                item("Back Squat", "Legs", 3, 8),
                item("Bench Press", "Chest", 3, 8),
                item("Barbell Row", "Back", 3, 10),
                item("Hanging Leg Raise", "Core", 3, 10)
            ]),
            .init(name: "Full Body B", items: [
                item("Romanian Deadlift", "Legs", 3, 10),
                item("Overhead Press", "Shoulders", 3, 8),
                item("Lat Pulldown", "Back", 3, 10),
                item("Dumbbell Curl", "Biceps", 2, 12),
                item("Tricep Pushdown", "Triceps", 2, 12)
            ])
        ]
    )

    static let pushPullLegs = WorkoutPlan(
        id: "push-pull-legs",
        name: "Push / Pull / Legs",
        summary: "Each workout trains related muscles, so you can train often with plenty of volume. A favourite for building muscle.",
        schedule: "3 days a week, or 6 by running it twice",
        level: "Intermediate",
        symbol: "arrow.triangle.2.circlepath",
        days: [
            .init(name: "Push", items: [
                item("Bench Press", "Chest", 4, 8),
                item("Incline Dumbbell Press", "Chest", 3, 10),
                item("Overhead Press", "Shoulders", 3, 8),
                item("Lateral Raise", "Shoulders", 3, 15),
                item("Tricep Pushdown", "Triceps", 3, 12)
            ]),
            .init(name: "Pull", items: [
                item("Deadlift", "Back", 3, 5),
                item("Pull-Up", "Back", 3, 8),
                item("Seated Cable Row", "Back", 3, 10),
                item("Face Pull", "Shoulders", 3, 15),
                item("Barbell Curl", "Biceps", 3, 10)
            ]),
            .init(name: "Legs", items: [
                item("Back Squat", "Legs", 4, 8),
                item("Romanian Deadlift", "Legs", 3, 10),
                item("Leg Press", "Legs", 3, 12),
                item("Leg Curl", "Legs", 3, 12),
                item("Calf Raise", "Legs", 4, 15)
            ])
        ]
    )

    static let upperLower = WorkoutPlan(
        id: "upper-lower",
        name: "Upper / Lower",
        summary: "Heavier sets on the big lifts, with each muscle trained twice a week. Great for getting stronger.",
        schedule: "4 days a week: Upper, Lower, rest, Upper, Lower",
        level: "Intermediate",
        symbol: "arrow.up.arrow.down",
        days: [
            .init(name: "Upper", items: [
                item("Bench Press", "Chest", 4, 6),
                item("Barbell Row", "Back", 4, 6),
                item("Overhead Press", "Shoulders", 3, 8),
                item("Lat Pulldown", "Back", 3, 10),
                item("Hammer Curl", "Biceps", 2, 12)
            ]),
            .init(name: "Lower", items: [
                item("Back Squat", "Legs", 4, 6),
                item("Romanian Deadlift", "Legs", 3, 8),
                item("Bulgarian Split Squat", "Glutes", 3, 10),
                item("Leg Curl", "Legs", 3, 12),
                item("Calf Raise", "Legs", 3, 15)
            ])
        ]
    )

    static let homeDumbbell = WorkoutPlan(
        id: "home-dumbbell",
        name: "Home Dumbbell",
        summary: "Two full-body workouts that only need a pair of dumbbells. Train anywhere.",
        schedule: "3 days a week, alternating A and B",
        level: "Any level",
        symbol: "house",
        days: [
            .init(name: "Home A", items: [
                item("Goblet Squat", "Legs", 3, 12),
                item("Dumbbell Bench Press", "Chest", 3, 10),
                item("Dumbbell Row", "Back", 3, 10),
                item("Dumbbell Shoulder Press", "Shoulders", 3, 10),
                item("Crunch", "Core", 3, 15)
            ]),
            .init(name: "Home B", items: [
                item("Bulgarian Split Squat", "Glutes", 3, 10),
                item("Push-Up", "Chest", 3, 12),
                item("Dumbbell Romanian Deadlift", "Legs", 3, 12),
                item("Lateral Raise", "Shoulders", 3, 15),
                item("Hammer Curl", "Biceps", 3, 12)
            ])
        ]
    )

    static let all = [fullBody, pushPullLegs, upperLower, homeDumbbell]

    // The best fit for someone's profile, and why.
    static func recommended(for profile: UserProfile?) -> (plan: WorkoutPlan, reason: String) {
        guard let profile else {
            return (fullBody, "A great place to start.")
        }
        let experience = Experience(rawValue: profile.experience) ?? .beginner
        let goal = FitnessGoal(rawValue: profile.goal) ?? .buildMuscle
        switch (experience, goal) {
        case (.beginner, _):
            return (fullBody, "Picked for beginners: learn the main lifts and build a base.")
        case (_, .getStronger):
            return (upperLower, "Picked for your goal to get stronger.")
        case (_, .buildMuscle):
            return (pushPullLegs, "Picked for your goal to build muscle.")
        default:
            return (upperLower, "Picked for your experience and goal.")
        }
    }

    // Adds a plan's workouts to the person's routines, creating any missing exercises.
    // Returns the routines it created.
    @discardableResult
    static func add(_ plan: WorkoutPlan, in context: ModelContext) -> [Routine] {
        var exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let existingNames = Set(((try? context.fetch(FetchDescriptor<Routine>())) ?? []).map(\.name))
        var created: [Routine] = []

        for day in plan.days {
            var name = day.name
            var number = 2
            while existingNames.contains(name) || created.contains(where: { $0.name == name }) {
                name = "\(day.name) \(number)"
                number += 1
            }
            let routine = Routine(name: name)
            context.insert(routine)
            for (order, item) in day.items.enumerated() {
                let key = DataMaintenance.normalized(item.exercise)
                let exercise = exercises.first { DataMaintenance.normalized($0.name) == key } ?? {
                    let new = Exercise(name: item.exercise, muscleGroup: item.group)
                    context.insert(new)
                    exercises.append(new)
                    return new
                }()
                routine.items.append(RoutineItem(order: order, exercise: exercise,
                                                 targetSets: item.sets, targetReps: item.reps))
            }
            created.append(routine)
        }
        try? context.save()
        return created
    }
}

// MARK: - Browsing plans

struct PlansView: View {
    var onAdded: () -> Void = {}

    @Environment(AccountManager.self) private var account
    @Query private var profiles: [UserProfile]

    var body: some View {
        let profile = profiles.first { $0.uid == account.uid }
        let pick = WorkoutPlans.recommended(for: profile)
        List {
            Section {
                NavigationLink {
                    PlanDetailView(plan: pick.plan, onAdded: onAdded)
                } label: {
                    PlanRow(plan: pick.plan, badge: "Recommended")
                }
            } footer: {
                Text(pick.reason + (profile == nil ? "" : " Change your goal and experience in your profile."))
            }

            Section("More plans") {
                ForEach(WorkoutPlans.all.filter { $0.id != pick.plan.id }) { plan in
                    NavigationLink {
                        PlanDetailView(plan: plan, onAdded: onAdded)
                    } label: {
                        PlanRow(plan: plan)
                    }
                }
            }
        }
        .navigationTitle("Workout Plans")
    }
}

struct PlanRow: View {
    let plan: WorkoutPlan
    var badge: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: plan.symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plan.name)
                        .font(.headline)
                    if let badge {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text("\(plan.level) · \(plan.schedule)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct PlanDetailView: View {
    let plan: WorkoutPlan
    var onAdded: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var added = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(plan.summary)
                    Label(plan.schedule, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(plan.level, systemImage: "chart.bar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            ForEach(plan.days, id: \.name) { day in
                Section(day.name) {
                    ForEach(day.items, id: \.exercise) { item in
                        LabeledContent(item.exercise, value: "\(item.sets) × \(item.reps)")
                    }
                }
            }

            Section {
                Button {
                    WorkoutPlans.add(plan, in: context)
                    added = true
                } label: {
                    Label(added ? "Added to your routines" : "Add to my routines",
                          systemImage: added ? "checkmark" : "plus")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(added)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Adds \(plan.days.count) routines you can edit like any other. Genie will suggest weight increases as you get stronger.")
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: added)
        .onChange(of: added) { _, isAdded in
            if isAdded { onAdded() }
        }
    }
}

// MARK: - Genie's pick for today

enum GeniePick {
    struct Pick {
        let routine: Routine
        let reason: String
    }

    // Suggests the routine whose muscles have rested longest, avoiding a repeat of the last workout.
    static func today(routines: [Routine], sessions: [WorkoutSession], exercises: [Exercise],
                      now: Date = .now) -> Pick? {
        let candidates = routines.filter { !$0.items.isEmpty }
        guard !candidates.isEmpty else { return nil }

        let groupOf = Dictionary(exercises.map { (DataMaintenance.normalized($0.name), $0.groupName) },
                                 uniquingKeysWith: { first, _ in first })
        var lastTrained: [String: Date] = [:]
        let finished = sessions.filter { !$0.inProgress }
        for session in finished {
            for set in session.completedSets {
                guard let group = groupOf[DataMaintenance.normalized(set.exerciseName)] else { continue }
                lastTrained[group] = max(lastTrained[group] ?? .distantPast, session.date)
            }
        }
        let lastRoutine = finished.max { $0.date < $1.date }?.routineName

        func daysSince(_ group: String) -> Double {
            guard let date = lastTrained[group] else { return 14 }
            return min(14, now.timeIntervalSince(date) / 86_400)
        }
        func groups(of routine: Routine) -> [String] {
            Array(Set(routine.items.compactMap { $0.exercise?.groupName }))
                .filter { $0 != MuscleGroup.other && $0 != "Full Body" }
        }

        let scored = candidates.map { routine -> (routine: Routine, score: Double) in
            let routineGroups = groups(of: routine)
            var score = routineGroups.isEmpty ? 7 : routineGroups.map(daysSince).reduce(0, +) / Double(routineGroups.count)
            if routine.name == lastRoutine { score -= 100 }
            return (routine, score)
        }
        // Ties (e.g. a new plan with no history) follow the plan's intended order: Push before Pull.
        func planOrder(_ routine: Routine) -> Int {
            for plan in WorkoutPlans.all {
                if let index = plan.days.firstIndex(where: { routine.name.hasPrefix($0.name) }) { return index }
            }
            return 99
        }
        guard let best = scored.max(by: {
            ($0.score, -planOrder($0.routine)) < ($1.score, -planOrder($1.routine))
        })?.routine else { return nil }

        // The reason names the muscle that has rested longest.
        let rested = groups(of: best).max { daysSince($0) < daysSince($1) }
        let reason: String
        if finished.isEmpty {
            reason = "A good first workout to get started."
        } else if let rested, let date = lastTrained[rested] {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                       to: Calendar.current.startOfDay(for: now)).day ?? 0
            reason = days <= 0 ? "Next up in your rotation."
                : "You last trained \(rested.lowercased()) \(days == 1 ? "yesterday" : "\(days) days ago")."
        } else if let rested {
            reason = "You haven't trained \(rested.lowercased()) yet."
        } else {
            reason = "Next up in your rotation."
        }
        return Pick(routine: best, reason: reason)
    }
}

struct GeniePickCard: View {
    let pick: GeniePick.Pick
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Genie's pick for today", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(pick.routine.name)
                    .font(.title3.bold())
                Text(pick.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(action: onStart) {
                Label("Start workout", systemImage: "play.fill")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.vertical, 6)
    }
}
