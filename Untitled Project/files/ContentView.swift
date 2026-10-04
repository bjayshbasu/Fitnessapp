import SwiftUI
import SwiftData

// Screen 1: the list of all your routines.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.name) private var routines: [Routine]
    @Query(filter: #Predicate<WorkoutSession> { $0.inProgress == false })
    private var finished: [WorkoutSession]
    @AppStorage(WeeklyGoal.key) private var weeklyGoal = 3
    @Query private var exercises: [Exercise]

    @State private var path: [Routine] = []
    @State private var showingPlans = false
    @State private var showingNew = false
    @State private var newName = ""
    @State private var routineToDelete: Routine?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !routines.isEmpty {
                    Section {
                        WeeklyGoalCard(status: WeeklyGoal.status(sessions: finished, goal: weeklyGoal))
                    }
                    if let pick = GeniePick.today(routines: routines, sessions: finished, exercises: exercises) {
                        Section {
                            GeniePickCard(pick: pick) {
                                WorkoutBuilder.start(routine: pick.routine, in: context)
                            }
                        }
                    }
                }

                Section {
                    ForEach(routines) { routine in
                        NavigationLink(value: routine) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(routine.name)
                                    .font(.headline)
                                Text(summary(of: routine))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Start", systemImage: "play.fill") {
                                WorkoutBuilder.start(routine: routine, in: context)
                            }
                            .tint(.green)
                            .disabled(routine.items.isEmpty)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                routineToDelete = routine
                            }
                        }
                        .contextMenu {
                            Button("Start workout", systemImage: "play.fill") {
                                WorkoutBuilder.start(routine: routine, in: context)
                            }
                            .disabled(routine.items.isEmpty)
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                duplicate(routine)
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                routineToDelete = routine
                            }
                        }
                    }
                }

                if !routines.isEmpty {
                    Section {
                        NavigationLink {
                            PlansView()
                        } label: {
                            Label("Browse workout plans", systemImage: "list.bullet.rectangle.portrait")
                        }
                    } footer: {
                        Text("Ready-made plans like Push / Pull / Legs, added in one tap.")
                    }
                }
            }
            .navigationTitle("Routines")
            .navigationDestination(isPresented: $showingPlans) {
                PlansView()
            }
            .navigationDestination(for: Routine.self) { routine in
                RoutineEditorView(routine: routine)
            }
            .overlay {
                if routines.isEmpty {
                    ContentUnavailableView {
                        VStack(spacing: 12) {
                            Image("Logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 88, height: 88)
                                .accessibilityHidden(true)
                            Text("Welcome to \(AppInfo.name)")
                        }
                    } description: {
                        Text("Start with a ready-made plan, or create your own routine.")
                    } actions: {
                        Button("Browse Workout Plans") { showingPlans = true }
                            .buttonStyle(.borderedProminent)
                        Button("Create My Own Routine") { showingNew = true }
                    }
                }
            }
            .toolbar {
                Button("Add routine", systemImage: "plus") { showingNew = true }
            }
            .alert("New Routine", isPresented: $showingNew) {
                TextField("e.g. Push Day", text: $newName)
                Button("Create") { createRoutine() }
                Button("Cancel", role: .cancel) { newName = "" }
            }
            .confirmationDialog("Delete “\(routineToDelete?.name ?? "")”?",
                                isPresented: Binding(get: { routineToDelete != nil },
                                                     set: { if !$0 { routineToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete routine", role: .destructive) {
                    if let routine = routineToDelete {
                        context.delete(routine)
                        try? context.save()
                    }
                    routineToDelete = nil
                }
            } message: {
                Text("Your workout history is kept.")
            }
        }
    }

    private func summary(of routine: Routine) -> String {
        let names = routine.sortedItems.compactMap { $0.exercise?.name }
        return names.isEmpty ? "No exercises yet" : names.joined(separator: ", ")
    }

    // Creates the routine and opens it straight away so you can add exercises.
    private func createRoutine() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        guard !name.isEmpty else { return }
        let routine = Routine(name: name)
        context.insert(routine)
        try? context.save()
        path.append(routine)
    }

    private func duplicate(_ routine: Routine) {
        let copy = Routine(name: "\(routine.name) Copy")
        context.insert(copy)
        for item in routine.sortedItems {
            let newItem = RoutineItem(order: item.order, exercise: item.exercise,
                                      targetSets: item.targetSets, targetReps: item.targetReps)
            newItem.supersetWithNext = item.supersetWithNext
            copy.items.append(newItem)
        }
        try? context.save()
    }
}

// Screen 2: edit a routine's name and its exercises.
struct RoutineEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var routine: Routine
    @State private var showingAdd = false

    var body: some View {
        List {
            Section {
                Button {
                    WorkoutBuilder.start(routine: routine, in: context)
                } label: {
                    Label("Start Workout", systemImage: "play.fill")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(routine.items.isEmpty)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Name") {
                TextField("Routine name", text: $routine.name)
            }

            Section {
                let items = routine.sortedItems
                let groups = routine.supersetGroups
                ForEach(items) { item in
                    RoutineItemRow(item: item,
                                   isLast: item.persistentModelID == items.last?.persistentModelID,
                                   supersetGroup: groups[item.persistentModelID] ?? 0)
                }
                .onDelete(perform: deleteItems)
                .onMove(perform: moveItems)

                Button("Add exercise", systemImage: "plus") {
                    showingAdd = true
                }
            } header: {
                Text("Exercises")
            } footer: {
                if routine.items.count > 1 {
                    Text("Tap Edit to reorder exercises. Turn on “Superset with next” to do two or more exercises back to back, resting after the round.")
                }
            }
        }
        .navigationTitle(routine.name.isEmpty ? "Routine" : routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !routine.items.isEmpty {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAdd) {
            ExercisePickerView { exercise in
                let nextOrder = (routine.items.map(\.order).max() ?? -1) + 1
                routine.items.append(RoutineItem(order: nextOrder, exercise: exercise))
                try? context.save()
            }
        }
        .onDisappear {
            let trimmed = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
            routine.name = trimmed.isEmpty ? "Untitled Routine" : trimmed
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        let items = routine.sortedItems
        let doomed = offsets.map { items[$0] }
        let doomedIDs = Set(doomed.map(\.persistentModelID))
        routine.items.removeAll { doomedIDs.contains($0.persistentModelID) }
        doomed.forEach { context.delete($0) }
        renumber(routine.sortedItems)
        try? context.save()
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var items = routine.sortedItems
        items.move(fromOffsets: source, toOffset: destination)
        renumber(items)
        try? context.save()
    }

    private func renumber(_ items: [RoutineItem]) {
        for (index, item) in items.enumerated() {
            item.order = index
        }
    }
}

// One exercise row with steppers for target sets and reps.
struct RoutineItemRow: View {
    @Bindable var item: RoutineItem
    var isLast = false
    var supersetGroup = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = SupersetLabel.text(for: supersetGroup) {
                Label(label, systemImage: "link")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(item.exercise?.name ?? "Deleted exercise")
                    .font(.headline)
                Spacer()
                if let group = item.exercise?.groupName {
                    Text(group)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Stepper("Sets: \(item.targetSets)", value: $item.targetSets, in: 1...10)
            Stepper("Reps: \(item.targetReps)", value: $item.targetReps, in: 1...50)
            if !isLast {
                Toggle("Superset with next", isOn: $item.supersetWithNext)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Exercise library

// Search your exercises and pick one, or create a new one.
struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void

    init(onPick: @escaping (Exercise) -> Void) {
        self.onPick = onPick
    }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var showingNew = false

    private var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [Exercise] {
        guard !trimmedSearch.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    private var hasExactMatch: Bool {
        exercises.contains { $0.name.caseInsensitiveCompare(trimmedSearch) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if !trimmedSearch.isEmpty && !hasExactMatch {
                    Section {
                        Button {
                            showingNew = true
                        } label: {
                            Label("Create “\(trimmedSearch)”", systemImage: "plus.circle.fill")
                        }
                    }
                }

                ForEach(ExerciseGroups.make(from: filtered)) { group in
                    Section(group.name) {
                        ForEach(group.exercises) { exercise in
                            Button {
                                onPick(exercise)
                                dismiss()
                            } label: {
                                Text(exercise.name)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .searchable(text: $search,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New exercise", systemImage: "plus") { showingNew = true }
                }
            }
            .navigationDestination(isPresented: $showingNew) {
                ExerciseFormView(exercise: nil, initialName: trimmedSearch) { exercise in
                    onPick(exercise)
                    dismiss()
                }
            }
        }
    }
}

// Exercises grouped by muscle group, in a sensible order.
struct ExerciseGroups: Identifiable {
    let name: String
    let exercises: [Exercise]
    var id: String { name }

    static func make(from exercises: [Exercise]) -> [ExerciseGroups] {
        Dictionary(grouping: exercises, by: \.groupName)
            .map { ExerciseGroups(name: $0.key, exercises: $0.value.sorted { $0.name < $1.name }) }
            .sorted { (MuscleGroup.rank(of: $0.name), $0.name) < (MuscleGroup.rank(of: $1.name), $1.name) }
    }
}

// Create a new exercise, or rename / regroup an existing one.
struct ExerciseFormView: View {
    let exercise: Exercise?
    var initialName: String = ""
    var onSave: (Exercise) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allExercises: [Exercise]

    @State private var name = ""
    @State private var group = MuscleGroup.other
    @State private var didLoad = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        allExercises.contains {
            $0.persistentModelID != exercise?.persistentModelID &&
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Exercise name", text: $name)
                    .textInputAutocapitalization(.words)
            } footer: {
                if isDuplicate {
                    Text("You already have an exercise with this name.")
                        .foregroundStyle(.red)
                } else if exercise != nil {
                    Text("Renaming also updates your past workouts, so your progress stays together.")
                }
            }

            Section("Muscle group") {
                Picker("Muscle group", selection: $group) {
                    ForEach(MuscleGroup.all, id: \.self) { group in
                        Text(group).tag(group)
                    }
                }
                .pickerStyle(.navigationLink)
            }
        }
        .navigationTitle(exercise == nil ? "New Exercise" : "Edit Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(trimmedName.isEmpty || isDuplicate)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            name = exercise?.name ?? initialName
            group = exercise?.groupName ?? MuscleGroup.other
        }
    }

    private func save() {
        let newName = trimmedName
        let savedGroup = group == MuscleGroup.other ? "" : group
        let saved: Exercise
        if let exercise {
            let oldName = exercise.name
            exercise.name = newName
            exercise.muscleGroup = savedGroup
            if oldName != newName { ExerciseRenamer.renameSets(from: oldName, to: newName, in: context) }
            saved = exercise
        } else {
            saved = Exercise(name: newName, muscleGroup: savedGroup)
            context.insert(saved)
        }
        try? context.save()
        onSave(saved)
        dismiss()
    }

}

// Renames an exercise everywhere: the library, past workouts and any workout in progress,
// so charts, records and "last time" stay together.
enum ExerciseRenamer {
    enum Problem: Error { case empty, duplicate }

    static func rename(_ oldName: String, to newName: String, in context: ModelContext) throws(Problem) {
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { throw .empty }
        guard newName != oldName else { return }
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let old = DataMaintenance.normalized(oldName), new = DataMaintenance.normalized(newName)
        // A different exercise already has this name (a change of capitals is fine).
        if old != new, exercises.contains(where: { DataMaintenance.normalized($0.name) == new }) {
            throw .duplicate
        }
        exercises.first { DataMaintenance.normalized($0.name) == old }?.name = newName
        renameSets(from: oldName, to: newName, in: context)
        try? context.save()
    }

    // Keeps charts and "last time" pre-fill working after a rename.
    static func renameSets(from oldName: String, to newName: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<LoggedSet>(predicate: #Predicate { $0.exerciseName == oldName })
        for set in (try? context.fetch(descriptor)) ?? [] {
            set.exerciseName = newName
        }
    }
}

// Exercise name in a section header, with a pencil; tap to rename.
struct ExerciseNameButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(name)
                    .foregroundStyle(Color(.secondaryLabel))
                Image(systemName: "pencil")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(name). Rename exercise")
    }
}

private struct RenameExerciseModifier: ViewModifier {
    @Binding var exerciseName: String?
    var onRenamed: () -> Void

    @Environment(\.modelContext) private var context
    @State private var draft = ""
    @State private var problem: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: exerciseName) { _, name in
                if let name { draft = name }
            }
            .alert("Rename exercise",
                   isPresented: Binding(get: { exerciseName != nil }, set: { if !$0 { exerciseName = nil } })) {
                TextField("Exercise name", text: $draft)
                    .textInputAutocapitalization(.words)
                Button("Save") { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This renames the exercise everywhere, including past workouts, so your progress stays together.")
            }
            .alert("Couldn't rename", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
    }

    private func save() {
        guard let oldName = exerciseName else { return }
        do {
            try ExerciseRenamer.rename(oldName, to: draft, in: context)
            onRenamed()
        } catch .duplicate {
            problem = "You already have an exercise called “\(draft.trimmingCharacters(in: .whitespaces))”."
        } catch {
            // Empty name: keep the old one.
        }
    }
}

extension View {
    func renameExercise(_ exerciseName: Binding<String?>, onRenamed: @escaping () -> Void = {}) -> some View {
        modifier(RenameExerciseModifier(exerciseName: exerciseName, onRenamed: onRenamed))
    }
}

// Settings > Exercise library: browse, edit, add and delete exercises.
struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var exerciseToDelete: Exercise?

    private var filtered: [Exercise] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        List {
            ForEach(ExerciseGroups.make(from: filtered)) { group in
                Section(group.name) {
                    ForEach(group.exercises) { exercise in
                        NavigationLink(exercise.name) {
                            ExerciseFormView(exercise: exercise)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                exerciseToDelete = exercise
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search exercises")
        .navigationTitle("Exercise Library")
        .toolbar {
            NavigationLink {
                ExerciseFormView(exercise: nil)
            } label: {
                Label("New exercise", systemImage: "plus")
            }
        }
        .overlay {
            if exercises.isEmpty {
                ContentUnavailableView("No exercises", systemImage: "dumbbell",
                                       description: Text("Tap + to add your first exercise."))
            }
        }
        .confirmationDialog("Delete “\(exerciseToDelete?.name ?? "")”?",
                            isPresented: Binding(get: { exerciseToDelete != nil },
                                                 set: { if !$0 { exerciseToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete exercise", role: .destructive) {
                if let exercise = exerciseToDelete { delete(exercise) }
                exerciseToDelete = nil
            }
        } message: {
            Text("It will be removed from any routines that use it. Your workout history is kept.")
        }
    }

    private func delete(_ exercise: Exercise) {
        let id = exercise.persistentModelID
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        for routine in routines {
            let doomed = routine.items.filter { $0.exercise?.persistentModelID == id }
            guard !doomed.isEmpty else { continue }
            routine.items.removeAll { $0.exercise?.persistentModelID == id }
            doomed.forEach { context.delete($0) }
            for (index, item) in routine.sortedItems.enumerated() { item.order = index }
        }
        context.delete(exercise)
        try? context.save()
    }
}
