#if DEBUG
import Foundation
import SwiftData

// Test-only: launch with "-seedSampleData" to fill an empty app with ten weeks of
// workouts, so stats, records and rewards have something to show. Not in release builds.
enum DebugSampleData {
    static func seedIfRequested(in context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleData"),
              (try? context.fetchCount(FetchDescriptor<WorkoutSession>())) == 0 else { return }

        let plans: [(routine: String, exercises: [(name: String, startKg: Double, reps: Int)])] = [
            ("Push Day", [("Bench Press", 60, 8), ("Overhead Press", 35, 8), ("Tricep Pushdown", 20, 12)]),
            ("Pull Day", [("Barbell Row", 50, 8), ("Lat Pulldown", 45, 10), ("Dumbbell Curl", 10, 12)]),
            ("Leg Day", [("Back Squat", 80, 6), ("Romanian Deadlift", 70, 8), ("Leg Press", 120, 10)])
        ]
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .weekOfYear, value: -10, to: .now) ?? .now

        for week in 0..<10 {
            // Three workouts most weeks, two in weeks 3 and 7.
            for (day, plan) in plans.enumerated() where !(day == 2 && (week == 3 || week == 7)) {
                guard let date = calendar.date(byAdding: .day, value: week * 7 + day * 2, to: start),
                      date < .now else { continue }
                let session = WorkoutSession(date: date, routineName: plan.routine)
                session.endDate = date.addingTimeInterval(Double(50 + day * 5) * 60)
                context.insert(session)
                for (order, exercise) in plan.exercises.enumerated() {
                    let weight = exercise.startKg + Double(week / 2) * 2.5
                    for number in 1...3 {
                        let set = LoggedSet(exerciseName: exercise.name, setNumber: number,
                                            reps: exercise.reps - (number == 3 ? 1 : 0),
                                            weight: weight, exerciseOrder: order)
                        // The last two exercises of each day were a superset.
                        if order > 0 { set.supersetGroup = 1 }
                        session.sets.append(set)
                    }
                    if order == 2 {
                        let drop = LoggedSet(exerciseName: exercise.name, setNumber: 4,
                                             reps: exercise.reps, weight: weight * 0.75, exerciseOrder: order)
                        drop.kind = SetKind.drop.rawValue
                        drop.supersetGroup = 1
                        session.sets.append(drop)
                    }
                }
            }
        }

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for plan in plans {
            let routine = Routine(name: plan.routine)
            context.insert(routine)
            for (order, item) in plan.exercises.enumerated() {
                let exercise = exercises.first { $0.name == item.name }
                let routineItem = RoutineItem(order: order, exercise: exercise, targetSets: 3, targetReps: item.reps)
                routineItem.supersetWithNext = order == 1
                routine.items.append(routineItem)
            }
        }
        try? context.save()
    }
}
#endif
