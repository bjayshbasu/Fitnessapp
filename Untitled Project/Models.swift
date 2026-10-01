import Foundation
import SwiftData

// An exercise you can reuse across routines (e.g. "Bench Press").
@Model
final class Exercise {
    var name: String
    var muscleGroup: String

    init(name: String, muscleGroup: String = "") {
        self.name = name
        self.muscleGroup = muscleGroup
    }
}

// A saved routine (e.g. "Push Day") made of ordered exercises.
@Model
final class Routine {
    var name: String
    @Relationship(deleteRule: .cascade) var items: [RoutineItem] = []

    init(name: String) {
        self.name = name
    }
}

// One exercise inside a routine, with your target sets and reps.
@Model
final class RoutineItem {
    var order: Int
    var exercise: Exercise?
    var targetSets: Int
    var targetReps: Int

    init(order: Int, exercise: Exercise?, targetSets: Int = 3, targetReps: Int = 10) {
        self.order = order
        self.exercise = exercise
        self.targetSets = targetSets
        self.targetReps = targetReps
    }
}

// One gym session on a given day. This is your history.
@Model
final class WorkoutSession {
    var date: Date
    var routineName: String
    @Relationship(deleteRule: .cascade) var sets: [LoggedSet] = []

    init(date: Date = .now, routineName: String) {
        self.date = date
        self.routineName = routineName
    }
}

// A single set you actually performed.
// Exercise name is copied in, so history survives if you rename or delete an exercise.
@Model
final class LoggedSet {
    var exerciseName: String
    var setNumber: Int
    var reps: Int
    var weight: Double  // kg or lb; pick one in settings later

    init(exerciseName: String, setNumber: Int, reps: Int, weight: Double) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
    }
}

// Put this in your App file: it tells SwiftUI to store these models.
//
// @main
// struct GymLogApp: App {
//     var body: some Scene {
//         WindowGroup { ContentView() }
//             .modelContainer(for: [Exercise.self, Routine.self,
//                                   RoutineItem.self, WorkoutSession.self,
//                                   LoggedSet.self])
//     }
// }
