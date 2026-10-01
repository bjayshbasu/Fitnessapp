import SwiftUI
import SwiftData
import UIKit
import UserNotifications

// Creates workouts and their starting sets, pre-filled from last time.
enum WorkoutBuilder {
    static func start(routine: Routine, in context: ModelContext) {
        // Only one workout at a time.
        let active = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.inProgress == true })
        if let count = try? context.fetchCount(active), count > 0 { return }

        let history = finishedSessions(in: context)
        let session = WorkoutSession(routineName: routine.name, inProgress: true)
        context.insert(session)

        let groups = routine.supersetGroups
        for (index, item) in routine.sortedItems.enumerated() {
            guard let name = item.exercise?.name else { continue }
            let sets = makeSets(for: name,
                                count: item.targetSets,
                                targetReps: item.targetReps,
                                exerciseOrder: index,
                                history: history,
                                suggest: true)
            sets.forEach { $0.supersetGroup = groups[item.persistentModelID] ?? 0 }
            session.sets.append(contentsOf: sets)
        }
        try? context.save()
    }

    // Starting sets for one exercise. Each set copies the weight and reps you did
    // for that set last time; extra sets copy your last set.
    // With `suggest`, Genie may add a little on top (see Genie.swift).
    static func makeSets(for name: String, count: Int, targetReps: Int,
                         exerciseOrder: Int, history: [WorkoutSession],
                         suggest: Bool = false) -> [LoggedSet] {
        // Drop sets aren't pre-filled; add them during the workout.
        let previous = lastPerformance(of: name, in: history).filter { !$0.isDropSet }
        let suggestion = suggest
            ? Genie.suggestion(previous: previous, targetSets: count, targetReps: targetReps)
            : nil
        return (1...max(count, 1)).map { number in
            let match = previous.first { $0.setNumber == number } ?? previous.last
            let set = LoggedSet(exerciseName: name,
                                setNumber: number,
                                reps: match?.reps ?? targetReps,
                                weight: match?.weight ?? 0,
                                exerciseOrder: exerciseOrder,
                                isDone: false)
            if let suggestion { Genie.apply(suggestion, to: set, targetReps: targetReps) }
            return set
        }
    }

    // The sets from the most recent finished workout that included this exercise.
    static func lastPerformance(of name: String, in history: [WorkoutSession]) -> [LoggedSet] {
        for session in history {
            let sets = session.sets(for: name).filter(\.isDone)
            if !sets.isEmpty { return sets }
        }
        return []
    }

    // Finished workouts, newest first.
    static func finishedSessions(in context: ModelContext) -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.inProgress == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

// Screen 3: log weight and reps for each set. Everything is saved as you go.
struct ActiveWorkoutView: View {
    let session: WorkoutSession
    let onClose: (WorkoutOutcome) -> Void

    init(session: WorkoutSession, onClose: @escaping (WorkoutOutcome) -> Void) {
        self.session = session
        self.onClose = onClose
    }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("restSeconds") private var restSeconds = 90
    @AppStorage("restEndTime") private var restEndTime: Double = 0
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage("healthSyncEnabled") private var healthSync = true

    @State private var showingFinishConfirm = false
    @State private var showingDiscardConfirm = false
    @State private var showingNothingDone = false
    @State private var showingAddExercise = false
    @State private var historyExercise: String?
    // Best estimated 1RM per exercise before this workout, for live PRs.
    @State private var previousBests: [String: Double] = [:]
    @State private var lastTime: [String: String] = [:]

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var restEnd: Date? {
        restEndTime > 0 ? Date(timeIntervalSince1970: restEndTime) : nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WorkoutStatsHeader(session: session, unit: unit)
                }

                ForEach(session.exerciseNames, id: \.self) { name in
                    let sets = session.sets(for: name)
                    Section {
                        ForEach(sets) { entry in
                            SetRow(entry: entry, unit: unit,
                                   isRecord: isRecord(entry),
                                   onDone: { startRest(after: entry) })
                        }
                        .onDelete { offsets in deleteSets(at: offsets, of: name) }

                        HStack {
                            Button("Add set", systemImage: "plus") {
                                addSet(to: name)
                            }
                            Spacer()
                            Button("Drop set", systemImage: "arrow.down.right") {
                                addDropSet(to: name)
                            }
                            .disabled(sets.isEmpty)
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                    } header: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if let label = SupersetLabel.text(for: sets.first?.supersetGroup ?? 0) {
                                    Label(label, systemImage: "link")
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.accentColor)
                                }
                                Text(name)
                            }
                            Spacer()
                            Button {
                                historyExercise = name
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.body)
                            }
                            .accessibilityLabel("\(name) history")
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let last = lastTime[name] {
                                Text("Last time: \(last)")
                            }
                            if let note = Genie.note(for: sets, unit: unit) {
                                Label(note, systemImage: "sparkles")
                            }
                        }
                    }
                }

                Section {
                    Button("Add exercise", systemImage: "plus.circle") {
                        showingAddExercise = true
                    }
                }

                Section {
                    Button {
                        requestFinish()
                    } label: {
                        Text("Finish Workout")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(session.routineName)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Rest time", selection: $restSeconds) {
                            ForEach(RestOptions.seconds, id: \.self) { seconds in
                                Text("Rest \(AppFormat.restTime(seconds))").tag(seconds)
                            }
                        }
                        Divider()
                        Button("Discard workout", systemImage: "trash", role: .destructive) {
                            showingDiscardConfirm = true
                        }
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { requestFinish() }
                        .bold()
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let end = restEnd {
                    RestTimerBar(endDate: end, onAdd: { addRest(15) }, onSkip: stopRest)
                }
            }
            .sheet(item: Binding(get: { historyExercise.map(HistoryItem.init) },
                                 set: { historyExercise = $0?.name })) { item in
                ExerciseHistorySheet(exerciseName: item.name)
            }
            .sheet(isPresented: $showingAddExercise) {
                ExercisePickerView { exercise in
                    addExercise(named: exercise.name)
                }
            }
            .confirmationDialog("Finish workout?", isPresented: $showingFinishConfirm,
                                titleVisibility: .visible) {
                Button("Finish and save") { finish() }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Sets you haven't ticked off won't be saved.")
            }
            .confirmationDialog("Discard this workout?", isPresented: $showingDiscardConfirm,
                                titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) { discard() }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Nothing from this session will be saved.")
            }
            .alert("No sets completed", isPresented: $showingNothingDone) {
                Button("Discard workout", role: .destructive) { discard() }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Tick off at least one set to save this workout.")
            }
            .onAppear {
                loadHistory()
                RestNotifier.requestPermission()
                // Clear a rest timer that ran out while the app was closed.
                if let end = restEnd, end < Date.now.addingTimeInterval(-60) { stopRest() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { try? context.save() }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Editing sets

    private func addSet(to name: String) {
        let existing = session.sets(for: name)
        let last = existing.last
        let template = existing.last(where: { !$0.isDropSet }) ?? last
        let set = LoggedSet(exerciseName: name,
                            setNumber: (last?.setNumber ?? 0) + 1,
                            reps: template?.reps ?? 10,
                            weight: template?.weight ?? 0,
                            exerciseOrder: last?.exerciseOrder ?? nextExerciseOrder,
                            isDone: false)
        set.supersetGroup = last?.supersetGroup ?? 0
        session.sets.append(set)
        try? context.save()
    }

    // A drop set: about 20% lighter than the last set, straight after it.
    private func addDropSet(to name: String) {
        let existing = session.sets(for: name)
        guard let last = existing.last else { return }
        let step = unit == .kg ? 2.5 : unit.kg(fromDisplay: 5)
        let lighter = max(0, ((last.weight * 0.8) / step).rounded() * step)
        let set = LoggedSet(exerciseName: name,
                            setNumber: last.setNumber + 1,
                            reps: last.reps,
                            weight: lighter,
                            exerciseOrder: last.exerciseOrder,
                            isDone: false)
        set.kind = SetKind.drop.rawValue
        set.supersetGroup = last.supersetGroup
        session.sets.append(set)
        try? context.save()
    }

    private func loadHistory() {
        let history = WorkoutBuilder.finishedSessions(in: context)
        previousBests = PersonalRecords.bestOneRepMax(in: history)
        var summaries: [String: String] = [:]
        for name in session.exerciseNames {
            let previous = WorkoutBuilder.lastPerformance(of: name, in: history)
            if !previous.isEmpty { summaries[name] = SetSummary.text(previous, unit: unit) }
        }
        lastTime = summaries
    }

    // A ticked set that beats your best estimated 1RM from earlier workouts.
    private func isRecord(_ entry: LoggedSet) -> Bool {
        guard entry.isDone, entry.weight > 0, entry.reps > 0,
              let best = previousBests[entry.exerciseName] else { return false }
        let beaten = entry.estimatedOneRepMaxKg > best + 0.01
        // Only the best set of the exercise gets the trophy.
        let topSet = session.sets(for: entry.exerciseName)
            .filter { $0.isDone && $0.weight > 0 }
            .max { $0.estimatedOneRepMaxKg < $1.estimatedOneRepMaxKg }
        return beaten && topSet?.persistentModelID == entry.persistentModelID
    }

    private func deleteSets(at offsets: IndexSet, of name: String) {
        let list = session.sets(for: name)
        let doomed = offsets.map { list[$0] }
        let doomedIDs = Set(doomed.map(\.persistentModelID))
        session.sets.removeAll { doomedIDs.contains($0.persistentModelID) }
        doomed.forEach { context.delete($0) }
        renumberSets(of: name)
        try? context.save()
    }

    private func addExercise(named name: String) {
        if session.exerciseNames.contains(name) {
            addSet(to: name)
            return
        }
        let history = WorkoutBuilder.finishedSessions(in: context)
        let sets = WorkoutBuilder.makeSets(for: name, count: 3, targetReps: 10,
                                           exerciseOrder: nextExerciseOrder,
                                           history: history)
        session.sets.append(contentsOf: sets)
        try? context.save()
        let previous = WorkoutBuilder.lastPerformance(of: name, in: history)
        if !previous.isEmpty { lastTime[name] = SetSummary.text(previous, unit: unit) }
    }

    private var nextExerciseOrder: Int {
        (session.sets.map(\.exerciseOrder).max() ?? -1) + 1
    }

    private func renumberSets(of name: String) {
        for (index, set) in session.sets(for: name).enumerated() {
            set.setNumber = index + 1
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    // MARK: Rest timer

    // In a superset, rest only after the last exercise of the round.
    private func startRest(after entry: LoggedSet) {
        if entry.supersetGroup > 0 {
            let order = session.sets
                .filter { $0.supersetGroup == entry.supersetGroup }
                .map(\.exerciseOrder)
            if let lastOrder = order.max(), entry.exerciseOrder != lastOrder { return }
        }
        startRest()
    }

    private func startRest() {
        let end = Date().addingTimeInterval(TimeInterval(restSeconds))
        restEndTime = end.timeIntervalSince1970
        RestNotifier.schedule(at: end)
        try? context.save()
    }

    private func addRest(_ seconds: Int) {
        guard let end = restEnd else { return }
        let newEnd = max(end, Date()).addingTimeInterval(TimeInterval(seconds))
        restEndTime = newEnd.timeIntervalSince1970
        RestNotifier.schedule(at: newEnd)
    }

    private func stopRest() {
        restEndTime = 0
        RestNotifier.cancel()
    }

    // MARK: Finishing

    private func requestFinish() {
        hideKeyboard()
        let sets = session.sets
        if !sets.contains(where: \.isDone) {
            showingNothingDone = true
        } else if sets.contains(where: { !$0.isDone }) {
            showingFinishConfirm = true
        } else {
            finish()
        }
    }

    // Keep only ticked-off sets, save, and send to Health.
    private func finish() {
        stopRest()
        let unfinished = session.sets.filter { !$0.isDone }
        session.sets.removeAll { !$0.isDone }
        unfinished.forEach { context.delete($0) }
        for name in session.exerciseNames { renumberSets(of: name) }

        let end = Date.now
        session.endDate = end
        session.inProgress = false
        try? context.save()

        if healthSync {
            let start = session.date
            Task { await HealthManager.saveWorkout(start: start, end: end) }
        }
        onClose(.finished(session))
    }

    private func discard() {
        stopRest()
        onClose(.discarded(session))
    }
}

// Elapsed time, sets done and volume at the top of the workout.
struct WorkoutStatsHeader: View {
    let session: WorkoutSession
    let unit: WeightUnit

    var body: some View {
        HStack {
            stat("Time") {
                Text(session.date, style: .timer)
            }
            Spacer()
            stat("Sets") {
                Text("\(session.completedSets.count)/\(session.sets.count)")
            }
            Spacer()
            stat("Volume") {
                Text(unit.wholeText(fromKg: session.volumeKg))
            }
        }
        .padding(.vertical, 4)
    }

    private func stat<Content: View>(_ title: String, @ViewBuilder value: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            value()
                .font(.headline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

// One row: set number, weight, reps, and a done checkbox.
struct SetRow: View {
    @Bindable var entry: LoggedSet
    let unit: WeightUnit
    var isRecord = false
    var onDone: () -> Void = {}

    // Shows and edits the weight in the chosen unit while storing kilograms.
    private var weightBinding: Binding<Double> {
        Binding(
            get: { unit.display(fromKg: entry.weight) },
            set: { entry.weight = max(0, unit.kg(fromDisplay: $0)) }
        )
    }

    private var repsBinding: Binding<Int> {
        Binding(
            get: { entry.reps },
            set: { entry.reps = max(0, $0) }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if entry.isDropSet {
                    Text("D")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Drop set")
                } else {
                    Text("\(entry.setNumber)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Set \(entry.setNumber)")
                }
            }
            .frame(width: 24, alignment: .leading)

            TextField(unit.rawValue, value: weightBinding, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
                .accessibilityLabel("Weight in \(unit.rawValue)")

            Text(unit.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("×")
                .foregroundStyle(.secondary)

            TextField("reps", value: repsBinding, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .accessibilityLabel("Reps")

            Spacer()

            if isRecord {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("New personal record")
                    .transition(.scale.combined(with: .opacity))
            }

            Button {
                entry.isDone.toggle()
                if entry.isDone { onDone() }
            } label: {
                Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(entry.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(entry.reps <= 0 && !entry.isDone)
            .accessibilityLabel(entry.isDone ? "Set \(entry.setNumber) done" : "Mark set \(entry.setNumber) done")
            .sensoryFeedback(.success, trigger: entry.isDone) { _, isDone in isDone }
        }
        .opacity(entry.isDone ? 0.75 : 1)
        .animation(.spring(duration: 0.3), value: isRecord)
        .contextMenu {
            Button(entry.isDropSet ? "Make normal set" : "Make drop set",
                   systemImage: entry.isDropSet ? "arrow.uturn.backward" : "arrow.down.right") {
                entry.kind = entry.isDropSet ? SetKind.normal.rawValue : SetKind.drop.rawValue
            }
        }
    }
}

private struct HistoryItem: Identifiable {
    let name: String
    var id: String { name }
}

// The countdown bar shown at the bottom while you rest.
struct RestTimerBar: View {
    let endDate: Date
    let onAdd: () -> Void
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let remaining = max(0, Int(endDate.timeIntervalSince(timeline.date).rounded(.up)))
            HStack(spacing: 12) {
                Text(remaining == 0 ? "Rest over" : "Rest")
                    .font(.headline)
                Text(AppFormat.restTime(remaining))
                    .font(.title2.monospacedDigit().bold())
                    .contentTransition(.numericText(countsDown: true))
                Spacer()
                Button("+15s", action: onAdd)
                    .buttonStyle(.bordered)
                Button(remaining == 0 ? "Done" : "Skip", action: onSkip)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.regularMaterial)
            .accessibilityElement(children: .contain)
        }
    }
}

// Handles the "rest is over" notification, including when the screen is locked.
enum RestNotifier {
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        // Show the banner and sound even if the app is open.
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async
            -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }
    private static let delegate = Delegate()

    static func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(at date: Date) {
        cancel()
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Time for your next set."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let seconds = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "restTimer", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["restTimer"])
    }
}

// Shown after you finish: time, sets, volume and any new personal records.
struct WorkoutSummaryView: View {
    let session: WorkoutSession

    init(session: WorkoutSession) {
        self.session = session
    }

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<WorkoutSession> { $0.inProgress == false })
    private var finished: [WorkoutSession]
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(WeeklyGoal.key) private var weeklyGoal = 3
    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    // PRs set in this workout, using the same rules as the Personal Records screen.
    private var records: [PersonalRecords.Event] {
        PersonalRecords.compute(finished).events.filter { $0.date == session.date }
    }

    var body: some View {
        let before = Rewards.Stats(sessions: finished.filter { $0.persistentModelID != session.persistentModelID },
                                   weeklyGoal: weeklyGoal)
        let after = Rewards.Stats(sessions: finished, weeklyGoal: weeklyGoal)
        let unlocked = Rewards.newlyUnlocked(before: before, after: after)
        let levelBefore = Rewards.level(for: before.xp).level
        let levelAfter = Rewards.level(for: after.xp)
        NavigationStack {
            List {
                Section {
                    RewardBanner(xpEarned: after.xp - before.xp,
                                 leveledUp: levelAfter.level > levelBefore,
                                 level: levelAfter.level, title: levelAfter.title)
                }

                if !unlocked.isEmpty {
                    Section(unlocked.count == 1 ? "Achievement unlocked" : "Achievements unlocked") {
                        ForEach(unlocked) { achievement in
                            HStack(spacing: 14) {
                                BadgeView(achievement: achievement, stats: after)
                                    .frame(width: 88)
                                Text(achievement.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Duration", value: AppFormat.duration(session.duration ?? 0))
                    LabeledContent("Sets", value: "\(session.completedSets.count)")
                    LabeledContent("Volume", value: unit.wholeText(fromKg: session.volumeKg))
                    let week = WeeklyGoal.status(sessions: finished, goal: weeklyGoal)
                    LabeledContent("This week", value: week.isMet
                                   ? "\(week.done) of \(week.goal), goal hit"
                                   : "\(week.done) of \(week.goal) workouts")
                }

                let newRecords = records
                if !newRecords.isEmpty {
                    Section("New personal records") {
                        ForEach(newRecords) { record in
                            Label {
                                LabeledContent(record.exercise,
                                               value: "\(unit.text(fromKg: record.weight)) × \(record.reps)")
                            } icon: {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }

                Section("Exercises") {
                    ForEach(session.exerciseNames, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                            Text(SetSummary.text(session.sets(for: name), unit: unit))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Workout complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.success, trigger: unlocked.count)
    }
}

// "+340 XP" and any level-up, at the top of the summary.
struct RewardBanner: View {
    let xpEarned: Int
    let leveledUp: Bool
    let level: Int
    let title: String

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: leveledUp ? "star.circle.fill" : "sparkles")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor.gradient)
                .symbolEffect(.bounce, value: appeared)
            VStack(alignment: .leading, spacing: 2) {
                Text("+\(xpEarned) XP")
                    .font(.title2.bold().monospacedDigit())
                Text(leveledUp ? "Level up! You're now level \(level), \(title)." : "Level \(level) · \(title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .onAppear { appeared = true }
    }
}
