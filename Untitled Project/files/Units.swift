import SwiftUI

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
}

// The Settings tab.
struct SettingsView: View {
    @AppStorage("weightUnit") private var unitRaw = WeightUnit.kg.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Weight unit", selection: $unitRaw) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Workouts are stored in kilograms, so you can switch any time and your history converts automatically.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
