import SwiftUI

// How many workouts you want each week, and how many weeks in a row you've hit it.
enum WeeklyGoal {
    static let key = "weeklyWorkoutGoal"

    struct Status {
        let done: Int
        let goal: Int
        let streak: Int

        var isMet: Bool { done >= goal }
    }

    // The current week only adds to the streak once its goal is met,
    // so an unfinished week never breaks it.
    static func status(sessions: [WorkoutSession], goal: Int,
                       now: Date = .now, calendar: Calendar = .current) -> Status {
        var counts: [Date: Int] = [:]
        for session in sessions where !session.inProgress {
            if let week = calendar.dateInterval(of: .weekOfYear, for: session.date)?.start {
                counts[week, default: 0] += 1
            }
        }
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return Status(done: 0, goal: goal, streak: 0)
        }
        let done = counts[thisWeek] ?? 0
        var streak = done >= goal ? 1 : 0
        var week = thisWeek
        while let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week),
              (counts[previous] ?? 0) >= goal {
            streak += 1
            week = previous
        }
        return Status(done: done, goal: goal, streak: streak)
    }
}

// The card at the top of the Routines tab.
struct WeeklyGoalCard: View {
    let status: WeeklyGoal.Status

    var body: some View {
        HStack(spacing: 16) {
            Gauge(value: Double(min(status.done, status.goal)),
                  in: 0...Double(max(status.goal, 1))) {
                EmptyView()
            } currentValueLabel: {
                Text("\(status.done)")
                    .font(.headline.monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(status.isMet ? Color.green : Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(status.isMet ? "Weekly goal hit!" : "\(status.done) of \(status.goal) workouts this week")
                    .font(.headline)
                Label(streakText, systemImage: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .labelStyle(StreakLabelStyle(active: status.streak > 0))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var streakText: String {
        switch status.streak {
        case 0: "Hit \(status.goal) this week to start a streak"
        case 1: "1-week streak"
        default: "\(status.streak)-week streak"
        }
    }
}

private struct StreakLabelStyle: LabelStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .foregroundStyle(active ? Color.orange : Color.secondary)
            configuration.title
        }
    }
}
