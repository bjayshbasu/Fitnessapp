import SwiftUI
import SwiftData

// Badges for milestones, plus a level that grows as you train.
enum Rewards {
    struct Stats {
        var workouts = 0
        var sets = 0
        var volumeKg: Double = 0
        var prs = 0
        var bestStreakWeeks = 0

        init() {}

        init(sessions: [WorkoutSession], weeklyGoal: Int) {
            let finished = sessions.filter { !$0.inProgress }
            workouts = finished.count
            sets = finished.reduce(0) { $0 + $1.completedSets.count }
            volumeKg = finished.reduce(0) { $0 + $1.volumeKg }
            prs = PersonalRecords.compute(finished).events.count
            bestStreakWeeks = WeeklyGoal.bestStreak(sessions: finished, goal: weeklyGoal)
        }

        // 100 per workout, 50 per PR, 2 per set.
        var xp: Int { workouts * 100 + prs * 50 + sets * 2 }
    }

    enum Category: String, CaseIterable {
        case workouts = "Workouts"
        case streaks = "Streaks"
        case records = "Records"
        case volume = "Volume"
    }

    struct Achievement: Identifiable {
        let id: String
        let category: Category
        let title: String
        let detail: String
        let symbol: String
        let target: Double
        let value: (Stats) -> Double

        func progress(_ stats: Stats) -> Double { min(1, value(stats) / target) }
        func isUnlocked(_ stats: Stats) -> Bool { value(stats) >= target }
    }

    static let achievements: [Achievement] = {
        var list: [Achievement] = []
        let workoutMilestones: [(Int, String)] = [
            (1, "First Rep"), (5, "Warming Up"), (10, "Double Digits"), (25, "Committed"),
            (50, "Half Century"), (100, "Centurion"), (250, "Iron Habit"), (500, "Legend")
        ]
        for (count, title) in workoutMilestones {
            list.append(Achievement(id: "workouts-\(count)", category: .workouts, title: title,
                                    detail: count == 1 ? "Finish your first workout" : "Finish \(count) workouts",
                                    symbol: "figure.strengthtraining.traditional", target: Double(count),
                                    value: { Double($0.workouts) }))
        }
        let streaks: [(Int, String)] = [(2, "On a Roll"), (4, "Month Strong"), (8, "Unstoppable"),
                                        (12, "Quarter Beast"), (26, "Half-Year Hero"), (52, "Year of Gains")]
        for (weeks, title) in streaks {
            list.append(Achievement(id: "streak-\(weeks)", category: .streaks, title: title,
                                    detail: "Hit your weekly goal \(weeks) weeks in a row",
                                    symbol: "flame.fill", target: Double(weeks),
                                    value: { Double($0.bestStreakWeeks) }))
        }
        let records: [(Int, String)] = [(1, "New Best"), (10, "Record Breaker"), (25, "PR Machine"),
                                        (50, "Limit Pusher"), (100, "Record Legend")]
        for (count, title) in records {
            list.append(Achievement(id: "prs-\(count)", category: .records, title: title,
                                    detail: count == 1 ? "Set your first personal record" : "Set \(count) personal records",
                                    symbol: "trophy.fill", target: Double(count),
                                    value: { Double($0.prs) }))
        }
        let volumes: [(Double, String)] = [(10_000, "Ten Tonnes"), (100_000, "Heavy Lifter"),
                                           (500_000, "Mountain Mover"), (1_000_000, "Million Club")]
        for (kg, title) in volumes {
            list.append(Achievement(id: "volume-\(Int(kg))", category: .volume, title: title,
                                    detail: "Lift \(Int(kg).formatted()) kg in total",
                                    symbol: "scalemass.fill", target: kg,
                                    value: { $0.volumeKg }))
        }
        return list
    }()

    // Level n starts at 250 × n × (n − 1) / 2 XP: 0, 250, 750, 1500…
    static func level(for xp: Int) -> (level: Int, title: String, intoLevel: Int, levelSize: Int) {
        var level = 1
        while xpNeeded(for: level + 1) <= xp { level += 1 }
        let start = xpNeeded(for: level)
        let size = xpNeeded(for: level + 1) - start
        return (level, title(for: level), xp - start, size)
    }

    private static func xpNeeded(for level: Int) -> Int { 250 * level * (level - 1) / 2 }

    private static func title(for level: Int) -> String {
        switch level {
        case 1...2: "Apprentice"
        case 3...5: "Spark"
        case 6...9: "Conjurer"
        case 10...14: "Enchanter"
        case 15...19: "Sorcerer"
        default: "Grand Genie"
        }
    }

    static func newlyUnlocked(before: Stats, after: Stats) -> [Achievement] {
        achievements.filter { !$0.isUnlocked(before) && $0.isUnlocked(after) }
    }
}

extension WeeklyGoal {
    // Longest run of weeks in a row where the goal was met.
    static func bestStreak(sessions: [WorkoutSession], goal: Int, calendar: Calendar = .current) -> Int {
        var counts: [Date: Int] = [:]
        for session in sessions where !session.inProgress {
            if let week = calendar.dateInterval(of: .weekOfYear, for: session.date)?.start {
                counts[week, default: 0] += 1
            }
        }
        let metWeeks = counts.filter { $0.value >= goal }.keys.sorted()
        var best = 0, run = 0
        var previous: Date?
        for week in metWeeks {
            if let previous, calendar.date(byAdding: .weekOfYear, value: 1, to: previous) == week {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = week
        }
        return best
    }
}

// The level card: "Level 4 · Spark" with a progress bar.
struct LevelCard: View {
    let stats: Rewards.Stats

    var body: some View {
        let level = Rewards.level(for: stats.xp)
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.gradient)
                Text("\(level.level)")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Level \(level.level) · \(level.title)")
                    .font(.headline)
                ProgressView(value: Double(level.intoLevel), total: Double(max(level.levelSize, 1)))
                Text("\(level.levelSize - level.intoLevel) XP to level \(level.level + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// One badge, unlocked or still in progress.
struct BadgeView: View {
    let achievement: Rewards.Achievement
    let stats: Rewards.Stats

    var body: some View {
        let unlocked = achievement.isUnlocked(stats)
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(unlocked ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                Image(systemName: achievement.symbol)
                    .font(.title2)
                    .foregroundStyle(unlocked ? Color.white : Color.secondary)
            }
            .frame(width: 64, height: 64)
            Text(achievement.title)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if unlocked {
                Text("Unlocked")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView(value: achievement.progress(stats))
                    .frame(width: 60)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(achievement.title), \(achievement.detail), \(unlocked ? "unlocked" : "\(Int(achievement.progress(stats) * 100)) percent")")
    }

    private var color: Color {
        switch achievement.category {
        case .workouts: .purple
        case .streaks: .orange
        case .records: .yellow
        case .volume: .blue
        }
    }
}

// Progress › Achievements.
struct AchievementsView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.inProgress == false })
    private var sessions: [WorkoutSession]
    @AppStorage(WeeklyGoal.key) private var weeklyGoal = 3
    @State private var selected: Rewards.Achievement?

    var body: some View {
        let stats = Rewards.Stats(sessions: sessions, weeklyGoal: weeklyGoal)
        let unlockedCount = Rewards.achievements.filter { $0.isUnlocked(stats) }.count
        List {
            Section {
                LevelCard(stats: stats)
            } footer: {
                Text("Earn XP for every workout (100), personal record (50) and set (2). \(unlockedCount) of \(Rewards.achievements.count) badges unlocked.")
            }

            ForEach(Rewards.Category.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 16) {
                        ForEach(Rewards.achievements.filter { $0.category == category }) { achievement in
                            Button { selected = achievement } label: {
                                BadgeView(achievement: achievement, stats: stats)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Achievements")
        .alert(selected?.title ?? "", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let selected {
                Text(selected.isUnlocked(stats) ? "\(selected.detail). Unlocked!" : "\(selected.detail). \(Int(selected.progress(stats) * 100))% there.")
            }
        }
    }
}
