import Foundation
import HealthKit

// Saves a finished gym session to the Health app as a strength-training workout.
//
// Xcode setup required (or the app will crash / be rejected):
//   1. Target > Signing & Capabilities > + Capability > HealthKit
//   2. Info.plist keys:
//      NSHealthUpdateUsageDescription = "Saves your finished workouts to Apple Health."
//      NSHealthShareUsageDescription  = "Lets the app save workouts to Apple Health."
enum HealthManager {
    private static let store = HKHealthStore()

    static func saveWorkout(start: Date, end: Date) async {
        // Health isn't available on every device (e.g. some iPads).
        guard HKHealthStore.isHealthDataAvailable(), end > start else { return }

        // Ask permission to write workouts. iOS only shows the prompt the first time.
        let workoutType = HKObjectType.workoutType()
        do {
            try await store.requestAuthorization(toShare: [workoutType], read: [])
        } catch {
            return
        }

        // If the person said no, quietly do nothing.
        guard store.authorizationStatus(for: workoutType) == .sharingAuthorized else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store,
                                       configuration: configuration,
                                       device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            print("Could not save workout to Health: \(error)")
        }
    }
}
