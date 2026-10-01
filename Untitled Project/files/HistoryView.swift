import SwiftUI
import SwiftData

// Screen 4: every finished workout, newest first, grouped by month.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutSession> { $0.inProgress == false },
           sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    @State private var sessionToDelete: WorkoutSession?

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private struct MonthGroup: Identifiable {
        let month: Date
        let sessions: [WorkoutSession]
        var id: Date { month }
    }

    private var months: [MonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.dateInterval(of: .month, for: session.date)?.start ?? session.date
        }
        return grouped
            .map { MonthGroup(month: $0.key, sessions: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(months) { group in
                    Section(group.month.formatted(.dateTime.month(.wide).year())) {
                        ForEach(group.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session, unit: unit)
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    sessionToDelete = session
                                }
                            }
                        }
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
            .confirmationDialog("Delete this workout?",
                                isPresented: Binding(get: { sessionToDelete != nil },
                                                     set: { if !$0 { sessionToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete workout", role: .destructive) {
                    if let session = sessionToDelete {
                        context.delete(session)
                        try? context.save()
                    }
                    sessionToDelete = nil
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}

// One workout in the history list.
struct SessionRow: View {
    let session: WorkoutSession
    let unit: WeightUnit

    private var details: String {
        var parts = [session.date.formatted(.dateTime.weekday(.abbreviated).day().hour().minute())]
        if let duration = session.duration { parts.append(AppFormat.duration(duration)) }
        parts.append("\(session.completedSets.count) sets")
        parts.append(unit.wholeText(fromKg: session.volumeKg))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.routineName)
                .font(.headline)
            Text(details)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// The sets you did in one saved workout, grouped by exercise.
struct SessionDetailView: View {
    let session: WorkoutSession
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: session.date.formatted(date: .complete, time: .shortened))
                if let duration = session.duration {
                    LabeledContent("Duration", value: AppFormat.duration(duration))
                }
                LabeledContent("Sets", value: "\(session.completedSets.count)")
                LabeledContent("Volume", value: unit.wholeText(fromKg: session.volumeKg))
            }

            ForEach(session.exerciseNames, id: \.self) { name in
                Section {
                    ForEach(session.sets(for: name)) { set in
                        HStack {
                            Text(set.isDropSet ? "Drop set" : "Set \(set.setNumber)")
                                .foregroundStyle(set.isDropSet ? Color.orange : Color.primary)
                            Spacer()
                            Text("\(unit.text(fromKg: set.weight)) × \(set.reps)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    if let label = SupersetLabel.text(for: session.sets(for: name).first?.supersetGroup ?? 0) {
                        Text("\(name) · \(label)")
                    } else {
                        Text(name)
                    }
                }
            }
        }
        .navigationTitle(session.routineName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
