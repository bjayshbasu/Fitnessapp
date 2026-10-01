import Foundation
import SwiftUI
import SwiftData
import Observation
import CryptoKit
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

// Backs up each account's data to Firestore and keeps every logged-in device in step.
//
// Layout: users/{uid}/records/{key}, one document per exercise, routine, finished
// workout and food, plus "profile" and "settings". Each document holds
// { type, data, deleted, updatedAt }.
//
// Local SwiftData stays the source the app reads from. On each pass the app turns every
// item into JSON and compares it with what it last synced (a hash per key), so it can
// upload only what changed, without tracking edits all over the app. Items removed
// locally are uploaded as `deleted: true` so other devices remove them too.
@Observable
@MainActor
final class SyncManager {
    enum Status: Equatable {
        case off
        case syncing
        case synced(Date)
        case offline
        case failed(String)
    }

    private(set) var status: Status = .off

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private var uid: String?
    private var syncedHashes: [String: String] = [:]
    private var pushTask: Task<Void, Never>?
    private var saveObserver: NSObjectProtocol?
    private var isApplyingRemote = false
    private var hasDownloaded = false
    #if canImport(FirebaseFirestore)
    private var listener: ListenerRegistration?
    #endif

    private static let ownerKey = "syncOwnerUID"

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Starting and stopping

    // Called when someone logs in (or the app opens already logged in).
    func start(uid: String) {
        guard self.uid != uid else { return }
        stopListening()
        self.uid = uid

        // Data on this phone belongs to whoever synced it last. A different account
        // logging in gets a clean slate; its own data then downloads.
        let owner = UserDefaults.standard.string(forKey: Self.ownerKey)
        if let owner, owner != uid {
            clearLocalData()
        }
        UserDefaults.standard.set(uid, forKey: Self.ownerKey)

        syncedHashes = loadHashes(uid: uid)
        DataMaintenance.ensureSyncIDs(in: context)
        try? context.save()

        status = .syncing
        hasDownloaded = false
        listen(uid: uid)
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePush() }
        }
    }

    // Uploads anything outstanding. Returns false if it didn't finish in time.
    @discardableResult
    func pushNow(timeout: Duration = .seconds(15)) async -> Bool {
        pushTask?.cancel()
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await self.push() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    // Starts over after a problem (e.g. once the database's rules are fixed).
    // Firestore drops a live listener after an error, so it has to be set up again.
    func retryIfNeeded() {
        guard let uid else { return }
        switch status {
        case .failed, .offline:
            stopListening()
            self.uid = nil
            start(uid: uid)
        default:
            break
        }
    }

    // Logged out some other way (e.g. the account was disabled): stop, keep local data.
    func stop() {
        stopListening()
        uid = nil
        status = .off
    }

    // Logging out: stop syncing and remove this account's data from the phone.
    // (Call `pushNow()` first so nothing is lost.)
    func stopAndClear() {
        stopListening()
        clearLocalData()
        UserDefaults.standard.removeObject(forKey: Self.ownerKey)
        uid = nil
        syncedHashes = [:]
        status = .off
    }

    // Deleting an account: remove the cloud copy too, then the local one.
    func deleteCloudData() async throws {
        #if canImport(FirebaseFirestore)
        guard let collection = recordsCollection else { return }
        stopListening()
        let snapshot = try await collection.getDocuments()
        for chunk in snapshot.documents.chunked(into: 400) {
            let batch = Firestore.firestore().batch()
            chunk.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
        }
        #endif
    }

    private func stopListening() {
        #if canImport(FirebaseFirestore)
        listener?.remove()
        listener = nil
        #endif
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        saveObserver = nil
        pushTask?.cancel()
    }

    // MARK: Uploading

    // Waits for edits to settle (typing a weight saves on every keystroke) before uploading.
    private func schedulePush() {
        guard uid != nil, !isApplyingRemote else { return }
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await push()
        }
    }

    @discardableResult
    private func push() async -> Bool {
        #if canImport(FirebaseFirestore)
        guard let uid, let collection = recordsCollection else { return false }
        let local = SyncSnapshot.records(in: context, uid: uid)

        var changes: [(key: String, payload: [String: Any], hash: String)] = []
        for (key, record) in local where syncedHashes[key] != record.hash {
            changes.append((key, ["type": record.type, "data": record.data, "deleted": false,
                                  "updatedAt": FieldValue.serverTimestamp()], record.hash))
        }
        for key in syncedHashes.keys where local[key] == nil && syncedHashes[key] != Self.deletedHash {
            changes.append((key, ["deleted": true, "updatedAt": FieldValue.serverTimestamp()], Self.deletedHash))
        }
        guard !changes.isEmpty else {
            status = .synced(.now)
            return true
        }

        status = .syncing
        do {
            for chunk in changes.chunked(into: 400) {
                let batch = Firestore.firestore().batch()
                for change in chunk {
                    batch.setData(change.payload, forDocument: collection.document(change.key))
                }
                try await batch.commit()
                guard self.uid == uid else { return false }
                for change in chunk { syncedHashes[change.key] = change.hash }
                saveHashes(uid: uid)
            }
            status = .synced(.now)
            return true
        } catch {
            status = Self.status(for: error)
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: Downloading

    #if canImport(FirebaseFirestore)
    private var recordsCollection: CollectionReference? {
        guard let uid else { return nil }
        return Firestore.firestore().collection("users").document(uid).collection("records")
    }

    // Live updates: the first snapshot downloads everything, later ones bring
    // changes from the account's other devices as they happen.
    private func listen(uid: String) {
        guard let collection = recordsCollection else { return }
        listener = collection.addSnapshotListener { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self, self.uid == uid else { return }
                if let error {
                    self.status = Self.status(for: error)
                    return
                }
                guard let snapshot else { return }
                let remote = snapshot.documentChanges
                    .filter { !$0.document.metadata.hasPendingWrites && $0.type != .removed }
                    .map { (key: $0.document.documentID, fields: $0.document.data()) }
                self.apply(remote, uid: uid)
                if !self.hasDownloaded {
                    self.hasDownloaded = true
                    // Whatever this phone has that the account doesn't (e.g. workouts
                    // logged before signing up) goes up now.
                    Task { await self.push() }
                }
            }
        }
    }

    private func apply(_ remote: [(key: String, fields: [String: Any])], uid: String) {
        guard !remote.isEmpty else { return }
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        let local = SyncSnapshot.records(in: context, uid: uid)
        var applied: [String] = []

        // Exercises before the routines that point at them.
        let order = ["settings", "profile", "exercise", "routine", "session", "food"]
        let sorted = remote.sorted {
            (order.firstIndex(of: $0.fields["type"] as? String ?? "") ?? order.count)
                < (order.firstIndex(of: $1.fields["type"] as? String ?? "") ?? order.count)
        }
        for item in sorted {
            let deleted = item.fields["deleted"] as? Bool ?? false
            let pendingLocalEdit = local[item.key].map { syncedHashes[item.key] != $0.hash } ?? false

            if deleted {
                SyncSnapshot.delete(key: item.key, in: context)
                syncedHashes[item.key] = Self.deletedHash
                continue
            }
            guard let type = item.fields["type"] as? String, let data = item.fields["data"],
                  let hash = SyncSnapshot.hash(of: data) else { continue }
            // An edit made here that hasn't uploaded yet wins; it will overwrite the cloud copy.
            if pendingLocalEdit && local[item.key]?.hash != hash { continue }
            if local[item.key]?.hash != hash {
                SyncSnapshot.apply(type: type, key: item.key, data: data, in: context, uid: uid)
                applied.append(item.key)
            }
            syncedHashes[item.key] = hash
        }
        try? context.save()
        // Record what the downloaded items look like here, so they aren't uploaded straight back.
        if !applied.isEmpty {
            let now = SyncSnapshot.records(in: context, uid: uid)
            for key in applied { syncedHashes[key] = now[key]?.hash ?? syncedHashes[key] }
        }
        saveHashes(uid: uid)
        status = .synced(.now)
    }
    #else
    private func listen(uid: String) {}
    #endif

    // MARK: Local bookkeeping

    private static let deletedHash = "deleted"

    // Removes everything that belongs to an account, so the next one starts fresh.
    private func clearLocalData() {
        try? context.delete(model: LoggedSet.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: RoutineItem.self)
        try? context.delete(model: Routine.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: FoodEntry.self)
        try? context.delete(model: UserProfile.self)
        try? context.save()
        // Let the starter exercise library come back for the next person.
        UserDefaults.standard.set(false, forKey: "didSeedExerciseLibrary")
        DataMaintenance.run(in: context)
    }

    private func hashesURL(uid: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "sync-\(uid).json")
    }

    private func loadHashes(uid: String) -> [String: String] {
        guard let data = try? Data(contentsOf: hashesURL(uid: uid)) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func saveHashes(uid: String) {
        let url = hashesURL(uid: uid)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? JSONEncoder().encode(syncedHashes).write(to: url, options: .atomic)
    }

    private static func status(for error: Error) -> Status {
        let nsError = error as NSError
        // Firestore "unavailable" (14) and URL errors mean no connection; it retries by itself.
        if nsError.code == 14 || nsError.domain == NSURLErrorDomain { return .offline }
        if nsError.code == 5 {
            return .failed("The cloud database isn't set up yet. Create it in the Firebase console.")
        }
        if nsError.code == 7 {
            return .failed("The cloud database refused access. Check its security rules.")
        }
        return .failed(error.localizedDescription)
    }
}

// MARK: - Converting between local items and cloud documents

private struct ExerciseRecord: Codable {
    var name: String
    var muscleGroup: String
}

private struct RoutineRecord: Codable {
    struct Item: Codable {
        var exerciseID: String
        var exerciseName: String
        var targetSets: Int
        var targetReps: Int
        var supersetWithNext: Bool
    }
    var name: String
    var items: [Item]
}

private struct SessionRecord: Codable {
    struct SetRecord: Codable {
        var exerciseName: String
        var setNumber: Int
        var reps: Int
        var weight: Double
        var exerciseOrder: Int
        var kind: String
        var supersetGroup: Int
    }
    var date: Double
    var endDate: Double?
    var routineName: String
    var sets: [SetRecord]
}

private struct FoodRecord: Codable {
    var name: String
    var date: Double
    var meal: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
}

private struct ProfileRecord: Codable {
    var birthYear: Int
    var heightCm: Double
    var weightKg: Double
    var sex: String
    var goal: String
    var experience: String
    var setupDone: Bool
    var photo: Data?
}

// Preferences that should follow the person to a new phone.
private struct SettingsRecord: Codable {
    var weightUnit: String?
    var restSeconds: Int?
    var weeklyGoal: Int?
    var genieSuggestions: Bool?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    private static let keys = (unit: "weightUnit", rest: "restSeconds", weekly: WeeklyGoal.key,
                               genie: Genie.enabledKey, calories: NutritionGoals.caloriesKey,
                               protein: NutritionGoals.proteinKey, carbs: NutritionGoals.carbsKey,
                               fat: NutritionGoals.fatKey)

    static func current() -> SettingsRecord {
        let d = UserDefaults.standard
        func value<T>(_ key: String) -> T? { d.object(forKey: key) as? T }
        return SettingsRecord(weightUnit: value(keys.unit), restSeconds: value(keys.rest),
                              weeklyGoal: value(keys.weekly), genieSuggestions: value(keys.genie),
                              calories: value(keys.calories), protein: value(keys.protein),
                              carbs: value(keys.carbs), fat: value(keys.fat))
    }

    func applyToDefaults() {
        let d = UserDefaults.standard
        func set(_ value: Any?, _ key: String) { if let value { d.set(value, forKey: key) } }
        set(weightUnit, Self.keys.unit)
        set(restSeconds, Self.keys.rest)
        set(weeklyGoal, Self.keys.weekly)
        set(genieSuggestions, Self.keys.genie)
        set(calories, Self.keys.calories)
        set(protein, Self.keys.protein)
        set(carbs, Self.keys.carbs)
        set(fat, Self.keys.fat)
    }
}

enum SyncSnapshot {
    struct Record {
        let type: String
        let data: Any        // JSON-compatible value stored in the document's "data" field
        let hash: String
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    // Every syncable item on this phone, keyed by its cloud document ID.
    static func records(in context: ModelContext, uid: String) -> [String: Record] {
        var result: [String: Record] = [:]
        func add<T: Encodable>(_ key: String, _ type: String, _ value: T) {
            guard let json = try? encoder.encode(value),
                  let object = try? JSONSerialization.jsonObject(with: json),
                  let hash = hash(of: object) else { return }
            result[key] = Record(type: type, data: object, hash: hash)
        }

        for exercise in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] where !exercise.syncID.isEmpty {
            add("exercise_\(exercise.syncID)", "exercise",
                ExerciseRecord(name: exercise.name, muscleGroup: exercise.muscleGroup))
        }
        for routine in (try? context.fetch(FetchDescriptor<Routine>())) ?? [] where !routine.syncID.isEmpty {
            let items = routine.sortedItems.map { item in
                RoutineRecord.Item(exerciseID: item.exercise?.syncID ?? "",
                                   exerciseName: item.exercise?.name ?? "",
                                   targetSets: item.targetSets, targetReps: item.targetReps,
                                   supersetWithNext: item.supersetWithNext)
            }
            add("routine_\(routine.syncID)", "routine", RoutineRecord(name: routine.name, items: items))
        }
        // Workouts upload once finished; one in progress stays on this phone.
        let finished = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.inProgress == false })
        for session in (try? context.fetch(finished)) ?? [] where !session.syncID.isEmpty {
            let sets = session.sets
                .sorted { ($0.exerciseOrder, $0.setNumber) < ($1.exerciseOrder, $1.setNumber) }
                .map { SessionRecord.SetRecord(exerciseName: $0.exerciseName, setNumber: $0.setNumber,
                                               reps: $0.reps, weight: $0.weight,
                                               exerciseOrder: $0.exerciseOrder, kind: $0.kind,
                                               supersetGroup: $0.supersetGroup) }
            add("session_\(session.syncID)", "session",
                SessionRecord(date: session.date.timeIntervalSince1970,
                              endDate: session.endDate?.timeIntervalSince1970,
                              routineName: session.routineName, sets: sets))
        }
        for food in (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? [] where !food.syncID.isEmpty {
            add("food_\(food.syncID)", "food",
                FoodRecord(name: food.name, date: food.date.timeIntervalSince1970, meal: food.meal,
                           calories: food.calories, proteinG: food.proteinG,
                           carbsG: food.carbsG, fatG: food.fatG))
        }
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        if let profile = profiles.first(where: { $0.uid == uid }) {
            add("profile", "profile",
                ProfileRecord(birthYear: profile.birthYear, heightCm: profile.heightCm,
                              weightKg: profile.weightKg, sex: profile.sex, goal: profile.goal,
                              experience: profile.experience, setupDone: profile.setupDone,
                              photo: profile.photoData))
        }
        add("settings", "settings", SettingsRecord.current())
        return result
    }

    static func hash(of object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // Writes a downloaded document into the local store.
    static func apply(type: String, key: String, data: Any, in context: ModelContext, uid: String) {
        guard let json = try? JSONSerialization.data(withJSONObject: data) else { return }
        let decoder = JSONDecoder()
        let id = String(key.drop(while: { $0 != "_" }).dropFirst())

        switch type {
        case "exercise":
            guard let record = try? decoder.decode(ExerciseRecord.self, from: json) else { return }
            let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            // Same ID, or the same name (e.g. the starter library on two phones).
            let match = all.first { $0.syncID == id }
                ?? all.first { DataMaintenance.normalized($0.name) == DataMaintenance.normalized(record.name) }
            let exercise = match ?? {
                let new = Exercise(name: record.name)
                context.insert(new)
                return new
            }()
            exercise.syncID = id
            exercise.name = record.name
            exercise.muscleGroup = record.muscleGroup

        case "routine":
            guard let record = try? decoder.decode(RoutineRecord.self, from: json) else { return }
            let routine = find(Routine.self, id: id, in: context) ?? {
                let new = Routine(name: record.name)
                context.insert(new)
                return new
            }()
            routine.syncID = id
            routine.name = record.name
            routine.items.forEach { context.delete($0) }
            routine.items.removeAll()
            let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            for (order, item) in record.items.enumerated() {
                let exercise = exercises.first { $0.syncID == item.exerciseID }
                    ?? exercises.first { DataMaintenance.normalized($0.name) == DataMaintenance.normalized(item.exerciseName) }
                let routineItem = RoutineItem(order: order, exercise: exercise,
                                              targetSets: item.targetSets, targetReps: item.targetReps)
                routineItem.supersetWithNext = item.supersetWithNext
                routine.items.append(routineItem)
            }

        case "session":
            guard let record = try? decoder.decode(SessionRecord.self, from: json) else { return }
            let session = find(WorkoutSession.self, id: id, in: context) ?? {
                let new = WorkoutSession(routineName: record.routineName)
                context.insert(new)
                return new
            }()
            session.syncID = id
            session.date = Date(timeIntervalSince1970: record.date)
            session.endDate = record.endDate.map(Date.init(timeIntervalSince1970:))
            session.routineName = record.routineName
            session.inProgress = false
            session.sets.forEach { context.delete($0) }
            session.sets.removeAll()
            for item in record.sets {
                let set = LoggedSet(exerciseName: item.exerciseName, setNumber: item.setNumber,
                                    reps: item.reps, weight: item.weight, exerciseOrder: item.exerciseOrder)
                set.kind = item.kind
                set.supersetGroup = item.supersetGroup
                session.sets.append(set)
            }

        case "food":
            guard let record = try? decoder.decode(FoodRecord.self, from: json) else { return }
            let date = Date(timeIntervalSince1970: record.date)
            let food = find(FoodEntry.self, id: id, in: context) ?? {
                let new = FoodEntry(name: record.name, date: date, meal: record.meal, calories: 0,
                                    proteinG: 0, carbsG: 0, fatG: 0)
                context.insert(new)
                return new
            }()
            food.syncID = id
            food.name = record.name
            food.date = date
            food.meal = record.meal
            food.calories = record.calories
            food.proteinG = record.proteinG
            food.carbsG = record.carbsG
            food.fatG = record.fatG

        case "profile":
            guard let record = try? decoder.decode(ProfileRecord.self, from: json) else { return }
            let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
            let profile = profiles.first { $0.uid == uid } ?? {
                let new = UserProfile(uid: uid)
                context.insert(new)
                return new
            }()
            profile.birthYear = record.birthYear
            profile.heightCm = record.heightCm
            profile.weightKg = record.weightKg
            profile.sex = record.sex
            profile.goal = record.goal
            profile.experience = record.experience
            profile.setupDone = record.setupDone || profile.setupDone
            profile.photoData = record.photo

        case "settings":
            (try? decoder.decode(SettingsRecord.self, from: json))?.applyToDefaults()

        default:
            break
        }
    }

    static func delete(key: String, in context: ModelContext) {
        let id = String(key.drop(while: { $0 != "_" }).dropFirst())
        let item: (any PersistentModel)? = switch key.prefix(while: { $0 != "_" }) {
        case "exercise": find(Exercise.self, id: id, in: context)
        case "routine": find(Routine.self, id: id, in: context)
        case "session": find(WorkoutSession.self, id: id, in: context)
        case "food": find(FoodEntry.self, id: id, in: context)
        default: nil
        }
        if let item { context.delete(item) }
    }

    private static func find<T: PersistentModel>(_ type: T.Type, id: String, in context: ModelContext) -> T? {
        guard !id.isEmpty else { return nil }
        let items = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return items.first { item in
            switch item {
            case let item as Exercise: item.syncID == id
            case let item as Routine: item.syncID == id
            case let item as WorkoutSession: item.syncID == id
            case let item as FoodEntry: item.syncID == id
            default: false
            }
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// "Backed up · just now" under the profile in Settings.
struct SyncStatusText: View {
    let status: SyncManager.Status
    var onRetry: () -> Void = {}

    var body: some View {
        switch status {
        case .off:
            EmptyView()
        case .syncing:
            Label("Backing up…", systemImage: "arrow.triangle.2.circlepath")
        case .synced(let date):
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Label("Backed up to your account · \(date.formatted(.relative(presentation: .named)))",
                      systemImage: "checkmark.icloud")
            }
        case .offline:
            Label("Offline. Changes will back up when you're connected.", systemImage: "icloud.slash")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Backup problem: \(message)", systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.red)
                Button("Try again", action: onRetry)
                    .font(.footnote.bold())
            }
        }
    }
}
