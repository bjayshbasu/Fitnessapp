import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Weights are always stored in kilograms. This converts to and from
// whatever unit the person has chosen, so switching never corrupts data.
enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, lb

    var id: String { rawValue }

    private static let kgPerLb = 0.45359237

    // Kilograms (stored) -> the number to show, rounded to 1 decimal.
    func display(fromKg kg: Double) -> Double {
        let value = self == .kg ? kg : kg / Self.kgPerLb
        return (value * 10).rounded() / 10
    }

    // The number the person typed -> kilograms (to store).
    func kg(fromDisplay value: Double) -> Double {
        self == .kg ? value : value * Self.kgPerLb
    }

    // Ready-to-show text like "62.5 kg" or "135 lb".
    func text(fromKg kg: Double) -> String {
        "\(display(fromKg: kg).formatted()) \(rawValue)"
    }

    // Whole-number text for big totals like volume: "5,230 kg".
    func wholeText(fromKg kg: Double) -> String {
        "\(Int(display(fromKg: kg).rounded()).formatted()) \(rawValue)"
    }
}

// Shared text formatting.
enum AppFormat {
    // 3725 seconds -> "1h 2m", 95 -> "1m 35s".
    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: max(interval, 0)) ?? "0m"
    }

    // 90 -> "1:30", 45 -> "0:45".
    static func restTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// Rest timer lengths offered everywhere in the app.
enum RestOptions {
    static let seconds = [30, 45, 60, 90, 120, 150, 180, 240, 300]
}

// The Settings tab.
struct SettingsView: View {
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage("restSeconds") private var restSeconds = 90
    @AppStorage("healthSyncEnabled") private var healthSync = true
    @AppStorage(Genie.enabledKey) private var genieEnabled = true
    @AppStorage(WeeklyGoal.key) private var weeklyGoal = 3

    @Query(filter: #Predicate<WorkoutSession> { $0.inProgress == false },
           sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query private var profiles: [UserProfile]
    @Environment(AccountManager.self) private var account
    @Environment(SyncManager.self) private var sync

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                if account.uid != nil {
                    Section {
                        NavigationLink {
                            ProfileView()
                        } label: {
                            HStack(spacing: 14) {
                                ProfileAvatar(photoData: profiles.first { $0.uid == account.uid }?.photoData,
                                              name: account.displayName.isEmpty ? account.email : account.displayName)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName.isEmpty ? "Your profile" : account.displayName)
                                        .font(.headline)
                                    Text(account.email)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } footer: {
                        SyncStatusText(status: sync.status) { sync.retryIfNeeded() }
                    }
                }

                Section {
                    Picker("Weight unit", selection: $unitRaw) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Units")
                } footer: {
                    Text("Workouts are stored in kilograms, so you can switch any time and your history converts automatically.")
                }

                Section("Workout") {
                    Picker("Default rest time", selection: $restSeconds) {
                        ForEach(RestOptions.seconds, id: \.self) { seconds in
                            Text(AppFormat.restTime(seconds)).tag(seconds)
                        }
                    }
                    Stepper(value: $weeklyGoal, in: 1...7) {
                        LabeledContent("Weekly goal", value: "\(weeklyGoal) workout\(weeklyGoal == 1 ? "" : "s")")
                    }
                    NavigationLink("Exercise library") {
                        ExerciseLibraryView()
                    }
                }

                Section {
                    Toggle("Genie suggestions", isOn: $genieEnabled)
                } footer: {
                    Text("When you hit every target rep, your next workout starts \(unit == .kg ? "2.5 kg" : "5 lb") heavier, or with one more rep for bodyweight exercises. You can always change the numbers.")
                }

                if FoodPhotoAnalyzer.isOffered {
                    Section("Nutrition") {
                        NavigationLink("Food photo scanning") {
                            PhotoScanSettingsView()
                        }
                    }
                }

                Section {
                    Toggle("Save workouts to Apple Health", isOn: $healthSync)
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Finished workouts are added to Health as strength training. Nothing is read from Health.")
                }

                Section {
                    ShareLink(item: WorkoutCSV(text: csvText),
                              preview: SharePreview("\(AppInfo.name) history")) {
                        Label("Export history (CSV)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(sessions.isEmpty)
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Your workouts stay on this device. Export them any time to use in a spreadsheet.")
                }

                Section("About") {
                    HStack(spacing: 14) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppInfo.name)
                                .font(.headline)
                            Text("Version \(appVersion)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("Settings")
        }
    }

    // One row per set, ready for Numbers, Excel or Google Sheets.
    private var csvText: String {
        var lines = ["Date,Routine,Exercise,Set,Weight (\(unit.rawValue)),Reps,Duration (min)"]
        for session in sessions {
            let date = session.date.formatted(.iso8601)
            let minutes = session.duration.map { String(Int(($0 / 60).rounded())) } ?? ""
            for name in session.exerciseNames {
                for set in session.sets(for: name) where set.isDone {
                    let fields = [date, session.routineName, name, String(set.setNumber),
                                  unit.display(fromKg: set.weight).formatted(.number.grouping(.never)),
                                  String(set.reps), minutes]
                    lines.append(fields.map(Self.csvEscape).joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    // Pure text formatting, so it can run anywhere (not tied to the main actor).
    nonisolated private static func csvEscape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// Lets the share sheet hand a .csv file to other apps.
struct WorkoutCSV: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { csv in
            Data(csv.text.utf8)
        }
        .suggestedFileName("workout-genie-history.csv")
    }
}
