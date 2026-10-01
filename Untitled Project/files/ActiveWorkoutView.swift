import SwiftUI
import SwiftData
import UserNotifications

// A set you're currently filling in. Lives in memory until you tap Finish.
struct SetDraft: Identifiable {
    let id = UUID()
    let exerciseName: String
    let setNumber: Int
    var reps: Int
    var weight: Double
    var done = false
}

// Screen 3: log your actual weight and reps for each set of a routine.
struct ActiveWorkoutView: View {
    let routine: Routine

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.date, order: .reverse) private var pastSessions: [WorkoutSession]

    @AppStorage("restSeconds") private var restSeconds = 90
    @State private var drafts: [SetDraft]
    @State private var didPrefill = false
    @State private var restEnd: Date?
    @State private var startedAt = Date()
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    init(routine: Routine) {
        self.routine = routine
        var list: [SetDraft] = []
        for item in routine.items.sorted(by: { $0.order < $1.order }) {
            let name = item.exercise?.name ?? "Exercise"
            for number in 1...max(item.targetSets, 1) {
                list.append(SetDraft(exerciseName: name,
                                     setNumber: number,
                                     reps: item.targetReps,
                                     weight: 0))
            }
        }
        _drafts = State(initialValue: list)
    }

    // Exercise names in routine order, without duplicates.
    private var exerciseNames: [String] {
        var seen = Set<String>()
        return drafts.map(\.exerciseName).filter { seen.insert($0).inserted }
    }

    var body: some View {
        List {
            ForEach(exerciseNames, id: \.self) { name in
                Section(name) {
                    ForEach($drafts) { $draft in
                        if draft.exerciseName == name {
                            SetRow(draft: $draft, unitLabel: unit.rawValue, onDone: startRest)
                        }
                    }
                }
            }

            Section {
                Button {
                    finish()
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
        .navigationTitle(routine.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Rest time", selection: $restSeconds) {
                        ForEach([30, 60, 90, 120, 180], id: \.self) { seconds in
                            Text("\(seconds) seconds").tag(seconds)
                        }
                    }
                } label: {
                    Label("Rest timer", systemImage: "timer")
                }
                Button("Finish") { finish() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let end = restEnd {
                RestTimerBar(endDate: end, onAdd: { addRest(15) }, onSkip: stopRest)
            }
        }
        .onAppear {
            prefillFromLastWorkout()
            RestNotifier.requestPermission()
        }
        .onDisappear { stopRest() }
    }

    // MARK: Rest timer

    private func startRest() {
        let end = Date().addingTimeInterval(TimeInterval(restSeconds))
        restEnd = end
        RestNotifier.schedule(at: end)
    }

    private func addRest(_ seconds: Int) {
        guard let end = restEnd else { return }
        let newEnd = max(end, Date()).addingTimeInterval(TimeInterval(seconds))
        restEnd = newEnd
        RestNotifier.schedule(at: newEnd)
    }

    private func stopRest() {
        restEnd = nil
        RestNotifier.cancel()
    }

    // MARK: Saving

    // Start each set with the weight and reps you used last time.
    private func prefillFromLastWorkout() {
        guard !didPrefill else { return }
        didPrefill = true
        for index in drafts.indices {
            let name = drafts[index].exerciseName
            let number = drafts[index].setNumber
            for session in pastSessions {
                if let match = session.sets.first(where: {
                    $0.exerciseName == name && $0.setNumber == number
                }) {
                    drafts[index].weight = unit.display(fromKg: match.weight)
                    drafts[index].reps = match.reps
                    break
                }
            }
        }
    }

    // Save only the sets you ticked off, then go back.
    private func finish() {
        let completed = drafts.filter(\.done)
        if !completed.isEmpty {
            let start = startedAt
            Task { await HealthManager.saveWorkout(start: start, end: Date()) }
            let session = WorkoutSession(routineName: routine.name)
            context.insert(session)
            for set in completed {
                session.sets.append(LoggedSet(exerciseName: set.exerciseName,
                                              setNumber: set.setNumber,
                                              reps: set.reps,
                                              weight: unit.kg(fromDisplay: set.weight)))
            }
        }
        dismiss()
    }
}

// One row: set number, weight, reps, and a done checkbox.
struct SetRow: View {
    @Binding var draft: SetDraft
    var unitLabel: String = "kg"
    var onDone: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Text("Set \(draft.setNumber)")
                .frame(width: 52, alignment: .leading)

            TextField(unitLabel, value: $draft.weight, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)

            Text("×")

            TextField("reps", value: $draft.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)

            Spacer()

            Button {
                draft.done.toggle()
                if draft.done { onDone() }
            } label: {
                Image(systemName: draft.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
        }
    }
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
                Text("Rest")
                    .font(.headline)
                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(.title2.monospacedDigit().bold())
                Spacer()
                Button("+15s", action: onAdd)
                    .buttonStyle(.bordered)
                Button(remaining == 0 ? "Done" : "Skip", action: onSkip)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.regularMaterial)
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
