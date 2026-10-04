import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Weights are always stored in kilograms. This converts to and from
// whatever unit the person has chosen, so switching never corrupts data.
enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, lb

    var id: String { rawValue }

    private static let kgPerLb = 0.45359237

    // Kilograms (stored) -> the number to show. Kilograms keep 2 decimals so small plates
    // (61.25 kg) survive; pounds round to 1 decimal to hide conversion noise.
    func display(fromKg kg: Double) -> Double {
        self == .kg ? (kg * 100).rounded() / 100 : ((kg / Self.kgPerLb) * 10).rounded() / 10
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

// A number box that saves on every keystroke, so a value is never lost when you tap
// ✓ or Save without closing the keyboard first. Accepts "." or "," as the decimal point.
struct NumberField: View {
    let placeholder: String
    @Binding var value: Double?
    var allowsDecimal = true

    @State private var text = ""
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text, selection: $selection)
            .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
            .focused($isFocused)
            .onAppear { text = Self.format(value) }
            // Changes made elsewhere (e.g. a scan filling the form) show up, but never while typing.
            .onChange(of: value) { _, newValue in
                if !isFocused { text = Self.format(newValue) }
            }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    // Select the whole number, so typing replaces it instead of adding to it.
                    DispatchQueue.main.async {
                        selection = TextSelection(range: text.startIndex..<text.endIndex)
                    }
                } else {
                    text = Self.format(value)
                }
            }
            // Saves what you type straight away. The text itself is only tidied up when you
            // leave the box: rewriting it mid-typing confuses the iPhone's text cursor.
            .onChange(of: text) { _, newText in
                value = Self.parse(Self.clean(newText, allowsDecimal: allowsDecimal))
            }
    }

    // Digits plus at most one decimal point, with at most 2 decimal places.
    static func clean(_ text: String, allowsDecimal: Bool) -> String {
        var result = ""
        var seenSeparator = false
        var decimals = 0
        for character in text {
            if character.isASCII && character.isNumber {
                if seenSeparator {
                    guard decimals < 2 else { continue }
                    decimals += 1
                }
                result.append(character)
            } else if character == "." || character == "," {
                // Whole-number boxes stop at a decimal point ("10.5" reps -> 10).
                guard allowsDecimal else { break }
                if !seenSeparator {
                    seenSeparator = true
                    result.append(character)
                }
            }
        }
        return result
    }

    static func parse(_ text: String) -> Double? {
        guard !text.isEmpty else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
}

extension NumberField {
    // For values that are never empty: clearing the box counts as 0 until you type.
    init(_ placeholder: String, value: Binding<Double>, allowsDecimal: Bool = true) {
        self.init(placeholder: placeholder,
                  value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0 ?? 0 }),
                  allowsDecimal: allowsDecimal)
    }

    init(_ placeholder: String, value: Binding<Int>) {
        self.init(placeholder: placeholder,
                  value: Binding(get: { Double(value.wrappedValue) },
                                 set: { value.wrappedValue = Int($0 ?? 0) }),
                  allowsDecimal: false)
    }
}
