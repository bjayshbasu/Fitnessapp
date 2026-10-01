import SwiftUI
import SwiftData

// The root of the app: four tabs.
struct MainTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Routines", systemImage: "list.bullet") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

// Screen 4: every workout you've saved, newest first.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.routineName)
                                .font(.headline)
                            Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(session.sets.count) sets")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        context.delete(sessions[index])
                    }
                }
            }
            .navigationTitle("History")
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "clock",
                        description: Text("Finish a workout and it will show up here.")
                    )
                }
            }
        }
    }
}

// The sets you did in one saved workout, grouped by exercise.
struct SessionDetailView: View {
    let session: WorkoutSession
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var exerciseNames: [String] {
        var seen = Set<String>()
        return session.sets.map(\.exerciseName).filter { seen.insert($0).inserted }
    }

    private func sets(for name: String) -> [LoggedSet] {
        session.sets
            .filter { $0.exerciseName == name }
            .sorted { $0.setNumber < $1.setNumber }
    }

    var body: some View {
        List {
            ForEach(exerciseNames, id: \.self) { name in
                Section(name) {
                    ForEach(sets(for: name)) { set in
                        HStack {
                            Text("Set \(set.setNumber)")
                            Spacer()
                            Text("\(unit.text(fromKg: set.weight)) × \(set.reps)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(session.routineName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
