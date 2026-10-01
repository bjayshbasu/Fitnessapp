import Foundation
import SwiftData

// An exercise you can reuse across routines (e.g. "Bench Press").
@Model
final class Exercise {
    var name: String
    var muscleGroup: String
    // Matches this item with its copy in the account's cloud backup.
    var syncID: String = ""

    init(name: String, muscleGroup: String = "") {
        self.name = name
        self.muscleGroup = muscleGroup
        self.syncID = UUID().uuidString
    }

    // Groups an exercise is shown under. Empty means "Other".
    var groupName: String {
        muscleGroup.isEmpty ? MuscleGroup.other : muscleGroup
    }
}

// The muscle groups used to organise the exercise library.
enum MuscleGroup {
    static let other = "Other"
    static let all = ["Chest", "Back", "Shoulders", "Biceps", "Triceps",
                      "Legs", "Glutes", "Core", "Full Body", other]

    // Sort position for a group name; unknown groups go last.
    static func rank(of group: String) -> Int {
        all.firstIndex(of: group) ?? all.count
    }

    // A starter library so a brand-new user isn't facing an empty screen.
    static let starterExercises: [(name: String, group: String)] = [
        ("Bench Press", "Chest"), ("Incline Bench Press", "Chest"),
        ("Dumbbell Bench Press", "Chest"), ("Incline Dumbbell Press", "Chest"),
        ("Chest Fly", "Chest"), ("Push-Up", "Chest"), ("Dip", "Chest"),
        ("Deadlift", "Back"), ("Barbell Row", "Back"), ("Dumbbell Row", "Back"),
        ("Pull-Up", "Back"), ("Chin-Up", "Back"), ("Lat Pulldown", "Back"),
        ("Seated Cable Row", "Back"),
        ("Overhead Press", "Shoulders"), ("Dumbbell Shoulder Press", "Shoulders"),
        ("Lateral Raise", "Shoulders"), ("Rear Delt Fly", "Shoulders"),
        ("Face Pull", "Shoulders"),
        ("Barbell Curl", "Biceps"), ("Dumbbell Curl", "Biceps"), ("Hammer Curl", "Biceps"),
        ("Tricep Pushdown", "Triceps"), ("Skull Crusher", "Triceps"),
        ("Overhead Tricep Extension", "Triceps"),
        ("Back Squat", "Legs"), ("Front Squat", "Legs"), ("Leg Press", "Legs"),
        ("Romanian Deadlift", "Legs"), ("Lunge", "Legs"), ("Leg Extension", "Legs"),
        ("Leg Curl", "Legs"), ("Calf Raise", "Legs"),
        ("Hip Thrust", "Glutes"), ("Bulgarian Split Squat", "Glutes"),
        ("Hanging Leg Raise", "Core"), ("Cable Crunch", "Core")
    ]
}

// A saved routine (e.g. "Push Day") made of ordered exercises.
@Model
final class Routine {
    var name: String
    @Relationship(deleteRule: .cascade) var items: [RoutineItem] = []
    var syncID: String = ""

    init(name: String) {
        self.name = name
        self.syncID = UUID().uuidString
    }

    var sortedItems: [RoutineItem] {
        items.sorted { $0.order < $1.order }
    }
}

// One exercise inside a routine, with your target sets and reps.
@Model
final class RoutineItem {
    var order: Int
    var exercise: Exercise?
    var targetSets: Int
    var targetReps: Int
    // Linked to the next exercise as a superset (done back to back, rest after the round).
    var supersetWithNext: Bool = false

    init(order: Int, exercise: Exercise?, targetSets: Int = 3, targetReps: Int = 10) {
        self.order = order
        self.exercise = exercise
        self.targetSets = targetSets
        self.targetReps = targetReps
    }
}

// One gym session. `date` is when it started.
// While you're training, `inProgress` is true and every set is saved as you go,
// so nothing is lost if you leave the app or it gets closed.
@Model
final class WorkoutSession {
    var date: Date
    var routineName: String
    var endDate: Date? = nil
    var inProgress: Bool = false
    @Relationship(deleteRule: .cascade) var sets: [LoggedSet] = []
    var syncID: String = ""

    init(date: Date = .now, routineName: String, inProgress: Bool = false) {
        self.date = date
        self.routineName = routineName
        self.inProgress = inProgress
        self.syncID = UUID().uuidString
    }

    // How long the workout took, if it has been finished.
    var duration: TimeInterval? {
        guard let endDate else { return nil }
        return max(0, endDate.timeIntervalSince(date))
    }

    var completedSets: [LoggedSet] {
        sets.filter(\.isDone)
    }

    // Total weight lifted (kg × reps) across completed sets.
    var volumeKg: Double {
        completedSets.reduce(0) { $0 + $1.volumeKg }
    }

    // Exercise names in the order they were done, without duplicates.
    var exerciseNames: [String] {
        var seen = Set<String>()
        return sets
            .sorted { ($0.exerciseOrder, $0.setNumber) < ($1.exerciseOrder, $1.setNumber) }
            .map(\.exerciseName)
            .filter { seen.insert($0).inserted }
    }

    func sets(for exerciseName: String) -> [LoggedSet] {
        sets.filter { $0.exerciseName == exerciseName }
            .sorted { $0.setNumber < $1.setNumber }
    }
}

// A single set. The exercise name is copied in, so history survives
// if you rename or delete an exercise.
@Model
final class LoggedSet {
    var exerciseName: String
    var setNumber: Int
    var reps: Int
    var weight: Double  // always kilograms; converted for display in Units.swift
    var exerciseOrder: Int = 0
    var isDone: Bool = true
    // What Genie added on top of last time when the workout started (0 = nothing).
    var genieIncreaseKg: Double = 0
    var genieExtraReps: Int = 0
    // "drop" for a drop set; anything else is a normal set.
    var kind: String = SetKind.normal.rawValue
    // Exercises sharing a non-zero number were done as a superset.
    var supersetGroup: Int = 0

    init(exerciseName: String, setNumber: Int, reps: Int, weight: Double,
         exerciseOrder: Int = 0, isDone: Bool = true) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.exerciseOrder = exerciseOrder
        self.isDone = isDone
    }

    var volumeKg: Double {
        weight * Double(max(reps, 0))
    }

    var isDropSet: Bool { kind == SetKind.drop.rawValue }

    // Estimated one-rep max (Epley formula). Lets 100 kg × 8 beat 105 kg × 1.
    var estimatedOneRepMaxKg: Double {
        reps <= 1 ? weight : weight * (1 + Double(reps) / 30)
    }
}

enum SetKind: String {
    case normal, drop
}

extension Routine {
    // Superset number for each item: linked runs share a number, others get 0.
    var supersetGroups: [PersistentIdentifier: Int] {
        var groups: [PersistentIdentifier: Int] = [:]
        var current = 0, next = 1
        var previousLinked = false
        for item in sortedItems {
            if previousLinked {
                groups[item.persistentModelID] = current
            } else if item.supersetWithNext {
                current = next
                next += 1
                groups[item.persistentModelID] = current
            } else {
                groups[item.persistentModelID] = 0
            }
            previousLinked = item.supersetWithNext
        }
        return groups
    }
}

// "Superset A", "Superset B"… for display.
enum SupersetLabel {
    static func text(for group: Int) -> String? {
        guard group > 0 else { return nil }
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return "Superset \(letters[(group - 1) % letters.count])"
    }
}
