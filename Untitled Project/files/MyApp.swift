import SwiftUI
import SwiftData

// The app's name, used on screens inside the app.
// The name under the icon on the home screen is set in Xcode:
// Target > General > Display Name.
enum AppInfo {
    static let name = "Workout Genie"
}

// The app's entry point.
@main
struct WorkoutGenieApp: App {
    @State private var account = AccountManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(account)
        }
        .modelContainer(for: [Exercise.self, Routine.self,
                              RoutineItem.self, WorkoutSession.self,
                              LoggedSet.self, FoodEntry.self, UserProfile.self])
    }
}

// Login when accounts are set up; straight into the app when they aren't.
struct RootView: View {
    @Environment(AccountManager.self) private var account
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            switch account.state {
            case .loading:
                ProgressView()
            case .unavailable:
                MainTabView()
            case .signedOut:
                AuthFlowView()
            case .signedIn(let uid, _, _):
                if profiles.first(where: { $0.uid == uid })?.setupDone == true {
                    MainTabView()
                } else {
                    NavigationStack {
                        ProfileView(isSetup: true)
                    }
                }
            }
        }
        .animation(.default, value: account.state)
    }
}

// What happened when the workout screen closed.
enum WorkoutOutcome {
    case finished(WorkoutSession)
    case discarded(WorkoutSession)
}

// The root of the app: five tabs, plus the workout screen on top
// whenever a workout is in progress (including after a relaunch).
struct MainTabView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutSession> { $0.inProgress == true })
    private var activeSessions: [WorkoutSession]

    @State private var presentedSession: WorkoutSession?
    @State private var pendingOutcome: WorkoutOutcome?
    @State private var summarySession: WorkoutSession?
    @State private var didRunMaintenance = false

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Routines", systemImage: "list.bullet") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            NutritionView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear {
            if !didRunMaintenance {
                didRunMaintenance = true
                DataMaintenance.run(in: context)
                #if DEBUG
                DebugSampleData.seedIfRequested(in: context)
                #endif
            }
            presentActiveWorkoutIfNeeded()
        }
        .onChange(of: activeSessions.map(\.persistentModelID)) {
            presentActiveWorkoutIfNeeded()
        }
        .fullScreenCover(item: $presentedSession, onDismiss: handleWorkoutClosed) { session in
            ActiveWorkoutView(session: session) { outcome in
                pendingOutcome = outcome
                presentedSession = nil
            }
        }
        .sheet(item: $summarySession) { session in
            WorkoutSummaryView(session: session)
        }
    }

    private func presentActiveWorkoutIfNeeded() {
        guard presentedSession == nil, pendingOutcome == nil,
              let active = activeSessions.first else { return }
        presentedSession = active
    }

    // Runs after the workout screen has finished sliding away.
    private func handleWorkoutClosed() {
        guard let outcome = pendingOutcome else { return }
        pendingOutcome = nil
        switch outcome {
        case .finished(let session):
            summarySession = session
        case .discarded(let session):
            context.delete(session)
            try? context.save()
        }
        presentActiveWorkoutIfNeeded()
    }
}

// One-time housekeeping when the app launches.
enum DataMaintenance {
    static func run(in context: ModelContext) {
        seedExercisesIfNeeded(in: context)
        mergeDuplicateExercises(in: context)
        try? context.save()
    }

    // Adds the starter exercise library once, skipping names you already have.
    private static func seedExercisesIfNeeded(in context: ModelContext) {
        let key = "didSeedExerciseLibrary"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let names = Set(existing.map { normalized($0.name) })
        for starter in MuscleGroup.starterExercises where !names.contains(normalized(starter.name)) {
            context.insert(Exercise(name: starter.name, muscleGroup: starter.group))
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    // Older versions created a new exercise every time one was added to a routine.
    // This folds same-named duplicates into one so the library stays clean.
    private static func mergeDuplicateExercises(in context: ModelContext) {
        guard let exercises = try? context.fetch(FetchDescriptor<Exercise>()) else { return }
        let groups = Dictionary(grouping: exercises) { normalized($0.name) }
        let duplicateGroups = groups.values.filter { $0.count > 1 }
        guard !duplicateGroups.isEmpty else { return }

        let items = (try? context.fetch(FetchDescriptor<RoutineItem>())) ?? []
        for group in duplicateGroups {
            let keeper = group.first(where: { !$0.muscleGroup.isEmpty }) ?? group[0]
            let duplicateIDs = Set(group.filter { $0 !== keeper }.map(\.persistentModelID))
            for item in items {
                if let id = item.exercise?.persistentModelID, duplicateIDs.contains(id) {
                    item.exercise = keeper
                }
            }
            for exercise in group where exercise !== keeper {
                context.delete(exercise)
            }
        }
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
