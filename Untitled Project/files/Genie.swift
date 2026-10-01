import Foundation

// Genie suggestions: if you hit every target rep last time, the next workout
// starts a little heavier (or with one more rep for bodyweight exercises).
enum Genie {
    static let enabledKey = "genieSuggestions"

    struct Suggestion {
        var increaseKg: Double = 0
        var extraReps: Int = 0
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    // The smallest sensible jump in the chosen unit: 2.5 kg or 5 lb.
    static var increaseKg: Double {
        let raw = UserDefaults.standard.string(forKey: "weightUnit") ?? ""
        let unit = WeightUnit(rawValue: raw) ?? .kg
        return unit == .kg ? 2.5 : unit.kg(fromDisplay: 5)
    }

    // A suggestion only when last time covered every target set at the target reps.
    static func suggestion(previous: [LoggedSet], targetSets: Int, targetReps: Int) -> Suggestion? {
        guard isEnabled, targetReps > 0, !previous.isEmpty,
              previous.count >= targetSets,
              previous.allSatisfy({ $0.reps >= targetReps }) else { return nil }
        if previous.contains(where: { $0.weight > 0 }) {
            return Suggestion(increaseKg: increaseKg)
        }
        return Suggestion(extraReps: 1)
    }

    // Applies a suggestion to a pre-filled set.
    static func apply(_ suggestion: Suggestion, to set: LoggedSet, targetReps: Int) {
        if suggestion.increaseKg > 0, set.weight > 0 {
            set.weight += suggestion.increaseKg
            set.reps = targetReps
            set.genieIncreaseKg = suggestion.increaseKg
        } else if suggestion.extraReps > 0 {
            set.reps += suggestion.extraReps
            set.genieExtraReps = suggestion.extraReps
        }
    }

    // The line shown under an exercise during a workout.
    static func note(for sets: [LoggedSet], unit: WeightUnit) -> String? {
        if let kg = sets.map(\.genieIncreaseKg).max(), kg > 0 {
            return "Genie added \(unit.text(fromKg: kg)): you hit every rep last time."
        }
        if sets.contains(where: { $0.genieExtraReps > 0 }) {
            return "Genie added 1 rep per set: you hit every rep last time."
        }
        return nil
    }
}
