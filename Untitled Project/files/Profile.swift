import SwiftUI
import SwiftData
import PhotosUI

// Body details and goals for one account, kept on this device.
@Model
final class UserProfile {
    var uid: String
    var birthYear: Int = 0       // 0 = not set
    var heightCm: Double = 0     // 0 = not set
    var weightKg: Double = 0     // 0 = not set
    var sex: String = ""         // "male", "female" or "" (not set)
    var goal: String = FitnessGoal.buildMuscle.rawValue
    var experience: String = Experience.beginner.rawValue
    // False until the person finishes (or skips) the "About You" step after signing up.
    var setupDone: Bool = false
    @Attribute(.externalStorage) var photoData: Data?

    init(uid: String) {
        self.uid = uid
    }

    var age: Int? {
        guard birthYear > 0 else { return nil }
        return Calendar.current.component(.year, from: .now) - birthYear
    }
}

enum FitnessGoal: String, CaseIterable, Identifiable {
    case loseFat = "Lose fat"
    case buildMuscle = "Build muscle"
    case getStronger = "Get stronger"
    case stayHealthy = "Stay healthy"
    var id: String { rawValue }

    var calorieAdjustment: Double {
        switch self {
        case .loseFat: -400
        case .buildMuscle: 250
        case .getStronger: 150
        case .stayHealthy: 0
        }
    }
}

enum Experience: String, CaseIterable, Identifiable {
    case beginner = "Beginner", intermediate = "Intermediate", advanced = "Advanced"
    var id: String { rawValue }
}

// Daily targets worked out from a profile.
enum NutritionSuggestion {
    struct Targets {
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    // Mifflin-St Jeor resting energy × 1.55 for training 3–5 days a week,
    // adjusted for the goal. Protein 1.8 g per kg, fat 25% of calories, carbs the rest.
    static func targets(for profile: UserProfile) -> Targets? {
        guard let age = profile.age, profile.heightCm > 0, profile.weightKg > 0,
              profile.sex == "male" || profile.sex == "female" else { return nil }
        let base = 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * Double(age)
        let resting = base + (profile.sex == "male" ? 5 : -161)
        let goal = FitnessGoal(rawValue: profile.goal) ?? .stayHealthy
        let calories = ((resting * 1.55 + goal.calorieAdjustment) / 50).rounded() * 50
        let protein = (profile.weightKg * 1.8 / 5).rounded() * 5
        let fat = (calories * 0.25 / 9 / 5).rounded() * 5
        let carbs = max(0, ((calories - protein * 4 - fat * 9) / 4 / 5).rounded() * 5)
        return Targets(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
}

// Shows a profile photo, or the person's initial when there isn't one.
struct ProfileAvatar: View {
    let photoData: Data?
    let name: String
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.accentColor.gradient)
                    Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// The profile for the signed-in account, opened from Settings
// (or shown once after sign-up with `isSetup`).
struct ProfileView: View {
    var isSetup = false
    var onFinish: () -> Void = {}

    @Environment(AccountManager.self) private var account
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(NutritionGoals.caloriesKey) private var calorieGoal = 2200.0
    @AppStorage(NutritionGoals.proteinKey) private var proteinGoal = 150.0
    @AppStorage(NutritionGoals.carbsKey) private var carbsGoal = 250.0
    @AppStorage(NutritionGoals.fatKey) private var fatGoal = 70.0

    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showingDeleteAccount = false
    @State private var showingSignOutConfirm = false
    @State private var errorMessage: String?
    @State private var suggestion: NutritionSuggestion.Targets?

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var profile: UserProfile? {
        profiles.first { $0.uid == account.uid }
    }

    var body: some View {
        Form {
            if let profile {
                content(for: profile)
            }
        }
        .navigationTitle(isSetup ? "About You" : "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if isSetup {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                }
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: saveName)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    profile?.photoData = Self.thumbnail(from: data)
                    try? context.save()
                }
                photoItem = nil
            }
        }
        .sheet(isPresented: $showingDeleteAccount) {
            // Captured now: once the account is gone, `profile` can no longer find it.
            let current = profile
            DeleteAccountView {
                if let current { context.delete(current) }
                try? context.save()
            }
        }
        .confirmationDialog("Log out of \(account.email)?", isPresented: $showingSignOutConfirm,
                            titleVisibility: .visible) {
            Button("Log out", role: .destructive) { account.signOut() }
        } message: {
            Text("Your workouts stay on this iPhone.")
        }
        .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil },
                                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Suggested daily goals",
               isPresented: Binding(get: { suggestion != nil }, set: { if !$0 { suggestion = nil } })) {
            Button("Use these") { applySuggestion() }
            Button("Not now", role: .cancel) {}
        } message: {
            if let suggestion {
                Text("\(NutritionGoals.kcal(suggestion.calories)) kcal · protein \(NutritionGoals.grams(suggestion.protein)) g · carbs \(NutritionGoals.grams(suggestion.carbs)) g · fat \(NutritionGoals.grams(suggestion.fat)) g\n\nAn estimate for training 3–5 days a week. Adjust it if your weight isn't moving the way you want.")
            }
        }
    }

    @ViewBuilder
    private func content(for profile: UserProfile) -> some View {
        @Bindable var profile = profile

        Section {
            HStack(spacing: 16) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ProfileAvatar(photoData: profile.photoData, name: name, size: 72)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.multicolor)
                                .background(Circle().fill(Color(.systemBackground)))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change profile photo")

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Your name", text: $name)
                        .font(.title3.bold())
                        .textContentType(.name)
                        .submitLabel(.done)
                        .onSubmit(saveName)
                    Text(account.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            if isSetup {
                Text("All optional. Your details help Genie suggest calorie and protein goals, and they stay on this iPhone.")
            }
        }

        Section("Body") {
            Picker("Sex", selection: $profile.sex) {
                Text("Not set").tag("")
                Text("Male").tag("male")
                Text("Female").tag("female")
            }
            Picker("Birth year", selection: $profile.birthYear) {
                Text("Not set").tag(0)
                let year = Calendar.current.component(.year, from: .now)
                ForEach((year - 90...year - 13).reversed(), id: \.self) { value in
                    Text(String(value)).tag(value)
                }
            }
            heightRow(profile)
            LabeledContent("Body weight") {
                HStack(spacing: 6) {
                    TextField("0", value: Binding(
                        get: { profile.weightKg > 0 ? unit.display(fromKg: profile.weightKg) : nil },
                        set: { profile.weightKg = max(0, unit.kg(fromDisplay: $0 ?? 0)) }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    .accessibilityLabel("Body weight in \(unit.rawValue)")
                    Text(unit.rawValue)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section("Training") {
            Picker("Main goal", selection: $profile.goal) {
                ForEach(FitnessGoal.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            Picker("Experience", selection: $profile.experience) {
                ForEach(Experience.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
        }

        Section {
            Button("Suggest nutrition goals", systemImage: "sparkles") {
                suggestion = NutritionSuggestion.targets(for: profile)
            }
            .disabled(NutritionSuggestion.targets(for: profile) == nil)
        } footer: {
            if NutritionSuggestion.targets(for: profile) == nil {
                Text("Fill in sex, birth year, height and weight to get suggested calories and macros.")
            }
        }

        if isSetup {
            Section {
                Button {
                    finish()
                } label: {
                    Text("Continue")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                Button("Log out") { showingSignOutConfirm = true }
                Button("Delete account", role: .destructive) { showingDeleteAccount = true }
            } footer: {
                Text("Deleting your account removes your login and profile. Workouts already on this iPhone are kept.")
            }
        }
    }

    // Height in cm, or feet and inches when using pounds.
    @ViewBuilder
    private func heightRow(_ profile: UserProfile) -> some View {
        if unit == .kg {
            LabeledContent("Height") {
                HStack(spacing: 6) {
                    TextField("0", value: Binding(
                        get: { profile.heightCm > 0 ? profile.heightCm.rounded() : nil },
                        set: { profile.heightCm = max(0, $0 ?? 0) }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    .accessibilityLabel("Height in centimetres")
                    Text("cm")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            let totalInches = Int((profile.heightCm / 2.54).rounded())
            Picker("Height", selection: Binding(
                get: { profile.heightCm > 0 ? totalInches : 0 },
                set: { profile.heightCm = $0 > 0 ? Double($0) * 2.54 : 0 }
            )) {
                Text("Not set").tag(0)
                ForEach(48...90, id: \.self) { inches in
                    Text("\(inches / 12)′ \(inches % 12)″").tag(inches)
                }
            }
        }
    }

    private func load() {
        name = account.displayName
        guard let uid = account.uid, profile == nil else { return }
        context.insert(UserProfile(uid: uid))
        try? context.save()
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        guard !trimmed.isEmpty, trimmed != account.displayName else { return }
        Task {
            do {
                try await account.updateName(trimmed)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func finish() {
        saveName()
        profile?.setupDone = true
        try? context.save()
        onFinish()
    }

    private func applySuggestion() {
        guard let suggestion else { return }
        calorieGoal = suggestion.calories
        proteinGoal = suggestion.protein
        carbsGoal = suggestion.carbs
        fatGoal = suggestion.fat
    }

    // Keeps profile photos small: 400 px is plenty for an avatar.
    private static func thumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 400
        let scale = side / min(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.jpegData(withCompressionQuality: 0.8) { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
    }
}

// Confirms the password, then deletes the account.
struct DeleteAccountView: View {
    var onDeleted: () -> Void

    @Environment(AccountManager.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Enter your password to confirm")
                } footer: {
                    Text("This permanently deletes the account for \(account.email). It can't be undone.")
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        HStack {
                            Text("Delete my account")
                            Spacer()
                            if isWorking { ProgressView() }
                        }
                    }
                    .disabled(password.isEmpty || isWorking)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func delete() {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await account.deleteAccount(password: password)
                onDeleted()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
