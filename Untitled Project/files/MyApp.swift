import SwiftUI
import SwiftData

// The app's entry point. If you rename your app, keep the name after "struct".
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: [Exercise.self, Routine.self,
                              RoutineItem.self, WorkoutSession.self,
                              LoggedSet.self])
    }
}
