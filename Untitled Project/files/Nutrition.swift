import SwiftUI
import SwiftData
import PhotosUI

// One thing you ate. Calories are kcal; macros are grams.
@Model
final class FoodEntry {
    var name: String
    var date: Date
    var meal: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    init(name: String, date: Date = .now, meal: String, calories: Double,
         proteinG: Double, carbsG: Double, fatG: Double) {
        self.name = name
        self.date = date
        self.meal = meal
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}

enum Meal: String, CaseIterable, Identifiable {
    case breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", snacks = "Snacks"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snacks: "carrot"
        }
    }

    // A sensible default for the time of day.
    static func suggested(for date: Date = .now) -> Meal {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snacks
        }
    }
}

// Daily targets, changed in the Goals sheet.
enum NutritionGoals {
    static let caloriesKey = "goalCalories"
    static let proteinKey = "goalProtein"
    static let carbsKey = "goalCarbs"
    static let fatKey = "goalFat"

    // 4 kcal per gram of protein or carbs, 9 per gram of fat.
    static func calories(protein: Double, carbs: Double, fat: Double) -> Double {
        4 * protein + 4 * carbs + 9 * fat
    }

    // 152.5 -> "152.5", 30 -> "30".
    static func grams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func kcal(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }
}

// The Nutrition tab: one day of food against your goals.
struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]

    @AppStorage(NutritionGoals.caloriesKey) private var calorieGoal = 2200.0
    @AppStorage(NutritionGoals.proteinKey) private var proteinGoal = 150.0
    @AppStorage(NutritionGoals.carbsKey) private var carbsGoal = 250.0
    @AppStorage(NutritionGoals.fatKey) private var fatGoal = 70.0

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var showingAdd = false
    @State private var showingGoals = false
    @State private var editing: FoodEntry?

    private var dayEntries: [FoodEntry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var dayTitle: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }

    var body: some View {
        let items = dayEntries
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Previous day", systemImage: "chevron.left") { shiftDay(by: -1) }
                        Spacer()
                        Text(dayTitle)
                            .font(.headline)
                        Spacer()
                        Button("Next day", systemImage: "chevron.right") { shiftDay(by: 1) }
                            .disabled(isToday)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)

                    CalorieSummary(eaten: items.reduce(0) { $0 + $1.calories }, goal: calorieGoal)
                    MacroRow(title: "Protein", grams: items.reduce(0) { $0 + $1.proteinG },
                             goal: proteinGoal, color: .blue)
                    MacroRow(title: "Carbs", grams: items.reduce(0) { $0 + $1.carbsG },
                             goal: carbsGoal, color: .orange)
                    MacroRow(title: "Fat", grams: items.reduce(0) { $0 + $1.fatG },
                             goal: fatGoal, color: .purple)
                }

                if items.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("Nothing logged", systemImage: "fork.knife")
                        } description: {
                            Text("Add what you eat to track calories, protein, carbs and fat.")
                        } actions: {
                            Button("Add Food") { showingAdd = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }

                ForEach(Meal.allCases) { meal in
                    let mealItems = items.filter { $0.meal == meal.rawValue }
                    if !mealItems.isEmpty {
                        Section {
                            ForEach(mealItems) { entry in
                                Button { editing = entry } label: { FoodRow(entry: entry) }
                                    .tint(.primary)
                            }
                            .onDelete { offsets in delete(offsets.map { mealItems[$0] }) }
                        } header: {
                            HStack {
                                Label(meal.rawValue, systemImage: meal.symbol)
                                Spacer()
                                Text("\(NutritionGoals.kcal(mealItems.reduce(0) { $0 + $1.calories })) kcal")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nutrition")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Goals", systemImage: "target") { showingGoals = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add food", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) {
                FoodFormView(entry: nil, day: day)
            }
            .sheet(item: $editing) { entry in
                FoodFormView(entry: entry, day: day)
            }
            .sheet(isPresented: $showingGoals) {
                NutritionGoalsView()
            }
        }
    }

    private func shiftDay(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        day = min(next, Calendar.current.startOfDay(for: .now))
    }

    private func delete(_ doomed: [FoodEntry]) {
        doomed.forEach { context.delete($0) }
        try? context.save()
    }
}

// Calories eaten against the daily goal.
struct CalorieSummary: View {
    let eaten: Double
    let goal: Double

    var body: some View {
        let left = goal - eaten
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(NutritionGoals.kcal(eaten))
                    .font(.largeTitle.bold().monospacedDigit())
                Text("/ \(NutritionGoals.kcal(goal)) kcal")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(left >= 0 ? "\(NutritionGoals.kcal(left)) left" : "\(NutritionGoals.kcal(-left)) over")
                    .font(.subheadline.bold())
                    .foregroundStyle(left >= 0 ? Color.secondary : Color.orange)
            }
            ProgressView(value: min(eaten, goal), total: max(goal, 1))
                .tint(left >= 0 ? Color.accentColor : Color.orange)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// One macro's grams against its goal.
struct MacroRow: View {
    let title: String
    let grams: Double
    let goal: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Text("\(NutritionGoals.grams(grams)) / \(NutritionGoals.grams(goal)) g")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(grams, goal), total: max(goal, 1))
                .tint(color)
        }
        .accessibilityElement(children: .combine)
    }
}

struct FoodRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text("P \(NutritionGoals.grams(entry.proteinG))g · C \(NutritionGoals.grams(entry.carbsG))g · F \(NutritionGoals.grams(entry.fatG))g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(NutritionGoals.kcal(entry.calories)) kcal")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// Add a new food, or edit one you've logged.
struct FoodFormView: View {
    let entry: FoodEntry?
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodEntry.date, order: .reverse) private var history: [FoodEntry]

    @State private var name = ""
    @State private var meal = Meal.suggested()
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var didLoad = false

    // Scanning: barcodes and labels are free; meal photos need an API key.
    private enum ScanMode { case barcode, label, meal }
    @State private var scanMode = ScanMode.label
    @State private var hasMealKey = FoodPhotoAnalyzer.hasKey
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingPhotoSource = false
    @State private var showingBarcodeScanner = false
    @State private var showingBarcodeOptions = false
    @State private var showingBarcodeEntry = false
    @State private var typedBarcode = ""
    @State private var scanningText: String?
    @State private var scanNote: String?
    @State private var scanError: String?

    // Values per 100 g/ml from a scan, scaled by the amount eaten.
    @State private var per100: Macros?
    @State private var amount: Double?
    @State private var amountUnit = "g"

    private var macroCalories: Double {
        NutritionGoals.calories(protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && (calories ?? macroCalories) > 0
    }

    // Different foods you've logged before, most recent first.
    private var recentFoods: [FoodEntry] {
        var seen = Set<String>()
        return Array(history.filter { seen.insert($0.name.lowercased()).inserted }.prefix(15))
    }

    var body: some View {
        NavigationStack {
            Form {
                if entry == nil {
                    scanSection
                }

                Section {
                    TextField("Food, e.g. Chicken and rice", text: $name)
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { meal in
                            Text(meal.rawValue).tag(meal)
                        }
                    }
                }

                Section {
                    if per100 != nil {
                        numberField("Amount", value: $amount, unit: amountUnit)
                    }
                    numberField("Calories", value: $calories, unit: "kcal",
                                placeholder: macroCalories > 0 ? NutritionGoals.kcal(macroCalories) : "0")
                    numberField("Protein", value: $protein, unit: "g")
                    numberField("Carbs", value: $carbs, unit: "g")
                    numberField("Fat", value: $fat, unit: "g")
                } header: {
                    Text("Nutrition")
                } footer: {
                    Text("Leave calories blank to work them out from the macros.")
                }

                if entry == nil && !recentFoods.isEmpty {
                    Section("Recent foods") {
                        ForEach(recentFoods) { food in
                            Button { fill(from: food) } label: { FoodRow(entry: food) }
                                .tint(.primary)
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Add Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                load()
                hasMealKey = FoodPhotoAnalyzer.hasKey
            }
            .onChange(of: amount) { applyAmount() }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        handle(image)
                    } else {
                        scanError = FoodScanError.unreadableImage.localizedDescription
                    }
                    photoItem = nil
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in handle(image) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showingBarcodeScanner) {
                BarcodeScannerSheet { code in lookUp(barcode: code) }
            }
            .confirmationDialog("Add a photo", isPresented: $showingPhotoSource) {
                Button("Take photo") { showingCamera = true }
                Button("Choose from photos") { showingPhotoPicker = true }
            }
            .confirmationDialog("Scan barcode", isPresented: $showingBarcodeOptions) {
                if CameraPicker.isAvailable {
                    Button("Take photo of barcode") {
                        scanMode = .barcode
                        showingCamera = true
                    }
                }
                Button("Choose photo of barcode") {
                    scanMode = .barcode
                    showingPhotoPicker = true
                }
                Button("Type barcode number") { showingBarcodeEntry = true }
            }
            .alert("Barcode number", isPresented: $showingBarcodeEntry) {
                TextField("e.g. 5449000000996", text: $typedBarcode)
                    .keyboardType(.numberPad)
                Button("Look up") {
                    lookUp(barcode: typedBarcode)
                    typedBarcode = ""
                }
                Button("Cancel", role: .cancel) { typedBarcode = "" }
            }
            .alert("Couldn't fill this in",
                   isPresented: Binding(get: { scanError != nil }, set: { if !$0 { scanError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanError ?? "")
            }
        }
    }

    @ViewBuilder
    private var scanSection: some View {
        Section {
            if let scanningText {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(scanningText)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Scan barcode", systemImage: "barcode.viewfinder") {
                    if BarcodeScannerSheet.isLiveScanningAvailable {
                        showingBarcodeScanner = true
                    } else {
                        showingBarcodeOptions = true
                    }
                }
                Button("Read nutrition label", systemImage: "text.viewfinder") { startPhoto(.label) }
                if hasMealKey {
                    Button("Snap a meal (AI)", systemImage: "sparkles") { startPhoto(.meal) }
                } else {
                    NavigationLink {
                        PhotoScanSettingsView()
                    } label: {
                        Label("Snap a meal (AI, needs API key)", systemImage: "sparkles")
                    }
                }
            }
            if let scanNote {
                Label(scanNote, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Quick add")
        } footer: {
            Text("Barcodes and labels are free and use the real numbers. Check everything before saving.")
        }
    }

    // Asks camera or library; goes straight to the library where there's no camera.
    private func startPhoto(_ mode: ScanMode) {
        scanMode = mode
        if CameraPicker.isAvailable {
            showingPhotoSource = true
        } else {
            showingPhotoPicker = true
        }
    }

    private func handle(_ image: UIImage) {
        switch scanMode {
        case .label:
            run("Reading the label…") { try await NutritionLabelReader.read(image) }
        case .barcode:
            run("Looking up the product…") {
                let code = try await BarcodeReader.detect(in: image)
                return try await OpenFoodFacts.lookup(barcode: code)
            }
        case .meal:
            run("Genie is reading your meal…") { ScannedFood(estimate: try await FoodPhotoAnalyzer.analyze(image)) }
        }
    }

    private func lookUp(barcode: String) {
        run("Looking up the product…") { try await OpenFoodFacts.lookup(barcode: barcode) }
    }

    private func run(_ message: String, _ work: @escaping () async throws -> ScannedFood) {
        scanningText = message
        scanNote = nil
        Task {
            defer { scanningText = nil }
            do {
                apply(try await work())
            } catch {
                scanError = error.localizedDescription
            }
        }
    }

    private func apply(_ food: ScannedFood) {
        if let foodName = food.name, !foodName.isEmpty { name = foodName }
        per100 = food.per100
        amountUnit = food.amountUnit
        if food.per100 != nil {
            amount = food.defaultAmount
            applyAmount()
        } else if let macros = food.macros {
            amount = nil
            setMacros(macros)
        }
        scanNote = food.note
    }

    private func applyAmount() {
        guard let per100, let amount else { return }
        let factor = amount / 100
        setMacros(Macros(calories: per100.calories * factor, protein: per100.protein * factor,
                         carbs: per100.carbs * factor, fat: per100.fat * factor))
    }

    private func setMacros(_ macros: Macros) {
        calories = macros.calories.rounded()
        protein = (macros.protein * 10).rounded() / 10
        carbs = (macros.carbs * 10).rounded() / 10
        fat = (macros.fat * 10).rounded() / 10
    }

    private func numberField(_ title: String, value: Binding<Double?>, unit: String,
                             placeholder: String = "0") -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(placeholder, value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                    .accessibilityLabel("\(title) in \(unit)")
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
            }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let entry {
            fill(from: entry)
            meal = Meal(rawValue: entry.meal) ?? .snacks
        } else if !Calendar.current.isDateInToday(day) {
            meal = .dinner
        }
    }

    private func fill(from food: FoodEntry) {
        per100 = nil
        amount = nil
        scanNote = nil
        name = food.name
        protein = food.proteinG
        carbs = food.carbsG
        fat = food.fatG
        // Calories that were worked out from the macros stay automatic,
        // so changing a macro later updates them too.
        let fromMacros = NutritionGoals.calories(protein: food.proteinG, carbs: food.carbsG, fat: food.fatG)
        calories = abs(food.calories - fromMacros) < 0.5 ? nil : food.calories
    }

    private func save() {
        let kcal = calories ?? macroCalories
        if let entry {
            entry.name = trimmedName
            entry.meal = meal.rawValue
            entry.calories = kcal
            entry.proteinG = protein ?? 0
            entry.carbsG = carbs ?? 0
            entry.fatG = fat ?? 0
        } else {
            // Past days get a midday time so the entry stays on that day.
            let calendar = Calendar.current
            let date = calendar.isDateInToday(day)
                ? Date.now
                : calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            context.insert(FoodEntry(name: trimmedName, date: date, meal: meal.rawValue,
                                     calories: kcal, proteinG: protein ?? 0,
                                     carbsG: carbs ?? 0, fatG: fat ?? 0))
        }
        try? context.save()
        dismiss()
    }
}

// Daily calorie and macro targets.
struct NutritionGoalsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(NutritionGoals.caloriesKey) private var calorieGoal = 2200.0
    @AppStorage(NutritionGoals.proteinKey) private var proteinGoal = 150.0
    @AppStorage(NutritionGoals.carbsKey) private var carbsGoal = 250.0
    @AppStorage(NutritionGoals.fatKey) private var fatGoal = 70.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Calories") {
                    Stepper(value: $calorieGoal, in: 1000...6000, step: 50) {
                        LabeledContent("Daily calories", value: "\(NutritionGoals.kcal(calorieGoal)) kcal")
                    }
                }

                Section {
                    Stepper(value: $proteinGoal, in: 0...400, step: 5) {
                        LabeledContent("Protein", value: "\(NutritionGoals.grams(proteinGoal)) g")
                    }
                    Stepper(value: $carbsGoal, in: 0...800, step: 5) {
                        LabeledContent("Carbs", value: "\(NutritionGoals.grams(carbsGoal)) g")
                    }
                    Stepper(value: $fatGoal, in: 0...300, step: 5) {
                        LabeledContent("Fat", value: "\(NutritionGoals.grams(fatGoal)) g")
                    }
                } header: {
                    Text("Macros")
                } footer: {
                    let macroTotal = NutritionGoals.calories(protein: proteinGoal, carbs: carbsGoal, fat: fatGoal)
                    Text("Your macros add up to \(NutritionGoals.kcal(macroTotal)) kcal.")
                }
            }
            .navigationTitle("Daily Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
