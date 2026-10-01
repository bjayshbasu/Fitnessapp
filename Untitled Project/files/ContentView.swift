import SwiftUI
import SwiftData

// Screen 1: the list of all your routines.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.name) private var routines: [Routine]

    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(routines) { routine in
                    NavigationLink(routine.name) {
                        RoutineEditorView(routine: routine)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        context.delete(routines[index])
                    }
                }
            }
            .navigationTitle("Routines")
            .overlay {
                if routines.isEmpty {
                    ContentUnavailableView(
                        "No routines yet",
                        systemImage: "dumbbell",
                        description: Text("Tap + to create your first routine.")
                    )
                }
            }
            .toolbar {
                Button("Add", systemImage: "plus") { showingNew = true }
            }
            .alert("New Routine", isPresented: $showingNew) {
                TextField("e.g. Push Day", text: $newName)
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        context.insert(Routine(name: name))
                    }
                    newName = ""
                }
                Button("Cancel", role: .cancel) { newName = "" }
            }
        }
    }
}

// Screen 2: edit a routine's name and its exercises.
struct RoutineEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var routine: Routine
    @State private var showingAdd = false
    @State private var exerciseName = ""

    private var sortedItems: [RoutineItem] {
        routine.items.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            Section("Name") {
                TextField("Routine name", text: $routine.name)
            }

            Section("Exercises") {
                ForEach(sortedItems) { item in
                    RoutineItemRow(item: item)
                }
                .onDelete { offsets in
                    let items = sortedItems
                    for index in offsets {
                        context.delete(items[index])
                    }
                }

                Button("Add exercise", systemImage: "plus") {
                    showingAdd = true
                }
            }
        }
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink("Start") {
                ActiveWorkoutView(routine: routine)
            }
            .disabled(routine.items.isEmpty)
        }
        .alert("Add Exercise", isPresented: $showingAdd) {
            TextField("e.g. Bench Press", text: $exerciseName)
            Button("Add") {
                let name = exerciseName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let nextOrder = (routine.items.map(\.order).max() ?? -1) + 1
                    let item = RoutineItem(order: nextOrder, exercise: Exercise(name: name))
                    routine.items.append(item)
                }
                exerciseName = ""
            }
            Button("Cancel", role: .cancel) { exerciseName = "" }
        }
    }
}

// One exercise row with steppers for target sets and reps.
struct RoutineItemRow: View {
    @Bindable var item: RoutineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.exercise?.name ?? "Exercise")
                .font(.headline)
            Stepper("Sets: \(item.targetSets)", value: $item.targetSets, in: 1...10)
            Stepper("Reps: \(item.targetReps)", value: $item.targetReps, in: 1...50)
        }
        .padding(.vertical, 4)
    }
}
