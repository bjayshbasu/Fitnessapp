import SwiftUI
import SwiftData

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Exercise.self, Routine.self,
                              RoutineItem.self, WorkoutSession.self,
                              LoggedSet.self])
    }
}
