import SwiftUI
import UIKit
import Vision
import VisionKit

// Calories (kcal) and macros (grams) for some amount of food.
struct Macros {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

// What a scan found, ready to drop into the Add Food form.
struct ScannedFood {
    var name: String?
    var macros: Macros?
    // Set when values are per 100 g/ml, so the form can scale them to the amount eaten.
    var per100: Macros?
    var defaultAmount: Double = 100
    var amountUnit = "g"
    var note: String
}

extension ScannedFood {
    init(estimate: FoodEstimate) {
        name = estimate.name
        macros = Macros(calories: estimate.calories, protein: estimate.proteinG,
                        carbs: estimate.carbsG, fat: estimate.fatG)
        let note = estimate.notes.isEmpty ? "Estimated from your photo." : estimate.notes
        self.note = estimate.confidence == "low" ? "Rough guess. \(note)" : note
    }
}

enum FoodScanError: LocalizedError {
    case noLabelValues, noBarcode, productNotFound, noNutrition, unreadableImage

    var errorDescription: String? {
        switch self {
        case .noLabelValues: "Couldn't find nutrition values. Try a sharp, straight-on photo of the label in good light."
        case .noBarcode: "Couldn't find a barcode in that photo. Try again closer up, or type the number."
        case .productNotFound: "This product isn't in the Open Food Facts database yet. Try reading the nutrition label instead."
        case .noNutrition: "This product has no nutrition info in Open Food Facts. Try reading the nutrition label instead."
        case .unreadableImage: "Couldn't open that photo."
        }
    }
}

// MARK: - Nutrition labels (on device, free)

enum NutritionLabelReader {
    static func read(_ image: UIImage) async throws -> ScannedFood {
        guard let cgImage = image.cgImage else { throw FoodScanError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let lines = try await Task.detached(priority: .userInitiated) {
            try recognizeLines(in: cgImage, orientation: orientation)
        }.value
        return try parse(lines)
    }

    // Returns the label's text one row at a time, left to right, so "Calories" and
    // "230" end up on the same line even when they're far apart on the label.
    nonisolated private static func recognizeLines(in cgImage: CGImage,
                                                   orientation: CGImagePropertyOrientation) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])

        let pieces = (request.results ?? []).compactMap { observation -> (text: String, box: CGRect)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (text, observation.boundingBox)
        }
        // Vision's coordinates start at the bottom, so sort top to bottom first.
        var rows: [[(text: String, box: CGRect)]] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = rows.last?.last,
               abs(last.box.midY - piece.box.midY) < min(last.box.height, piece.box.height) * 0.6 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
    }

    // Pulls calories, protein, carbs and fat out of the label's text.
    static func parse(_ rawLines: [String]) throws -> ScannedFood {
        let lines = rawLines.map { $0.lowercased().replacingOccurrences(of: ",", with: ".") }
        let calories = kcal(in: lines)
            ?? value(for: ["calories"], excluding: ["from fat", "fat cal", "a day"], in: lines)
        let fat = value(for: ["total fat", "fat"],
                        excluding: ["saturated", "trans", "sat.", "unsat", "from fat", "fat cal"], in: lines)
        let carbs = value(for: ["total carbohydrate", "carbohydrate", "carbs"],
                          excluding: ["of which", "sugar"], in: lines)
        let protein = value(for: ["protein"], excluding: [], in: lines)

        guard calories != nil || protein != nil || carbs != nil || fat != nil else {
            throw FoodScanError.noLabelValues
        }
        let p = protein ?? 0, c = carbs ?? 0, f = fat ?? 0
        let macros = Macros(calories: calories ?? NutritionGoals.calories(protein: p, carbs: c, fat: f),
                            protein: p, carbs: c, fat: f)

        // Many labels outside the US list values per 100 g instead of per serving.
        let text = lines.joined(separator: " ")
        let per100 = (text.contains("per 100") || text.contains("100 g") || text.contains("100g")
                      || text.contains("100 ml") || text.contains("100ml"))
            && !text.contains("per serving") && !text.contains("serving size")
        if per100 {
            let unit = text.contains("100 ml") || text.contains("100ml") ? "ml" : "g"
            return ScannedFood(per100: macros, amountUnit: unit,
                               note: "Read from the label (per 100 \(unit)). Set the amount you had, then add a name.")
        }
        return ScannedFood(macros: macros,
                           note: "Read from the label for one serving. Check the numbers, then add a name.")
    }

    // "Energy 1046 kJ / 250 kcal" -> 250
    private static func kcal(in lines: [String]) -> Double? {
        for line in lines {
            if let range = line.range(of: #"\d+(\.\d+)?\s*kcal"#, options: .regularExpression) {
                return firstNumber(in: String(line[range]))
            }
        }
        return nil
    }

    // The number after a keyword, or on the next line when that line is only a number.
    private static func value(for keywords: [String], excluding: [String], in lines: [String]) -> Double? {
        for (index, line) in lines.enumerated() {
            guard let range = keywords.lazy.compactMap({ line.range(of: $0) }).first,
                  !excluding.contains(where: { line.contains($0) }) else { continue }
            if let number = firstNumber(in: String(line[range.upperBound...])) { return number }
            if index + 1 < lines.count,
               lines[index + 1].range(of: #"^\s*\d+(\.\d+)?\s*(g|kcal)?\s*$"#, options: .regularExpression) != nil {
                return firstNumber(in: lines[index + 1])
            }
        }
        return nil
    }

    private static func firstNumber(in text: String) -> Double? {
        // Text recognition often reads "0g" as "Og".
        let fixed = text.replacingOccurrences(of: #"\bo(?=\s*g\b)"#, with: "0", options: .regularExpression)
        guard let range = fixed.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(fixed[range])
    }
}

// MARK: - Barcodes

enum BarcodeReader {
    // Finds a product barcode in a still photo (used when live scanning isn't available).
    static func detect(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw FoodScanError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let code = try await Task.detached(priority: .userInitiated) {
            try firstBarcode(in: cgImage, orientation: orientation)
        }.value
        guard let code else { throw FoodScanError.noBarcode }
        return code
    }

    nonisolated private static func firstBarcode(in cgImage: CGImage,
                                                 orientation: CGImagePropertyOrientation) throws -> String? {
        func detect(revision: Int?) throws -> String? {
            let request = VNDetectBarcodesRequest()
            if let revision { request.revision = revision }
            request.symbologies = [.ean13, .ean8, .upce, .code128]
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            return request.results?.compactMap(\.payloadStringValue).first
        }
        do {
            return try detect(revision: nil)
        } catch {
            // The newest detector needs the Neural Engine (missing in the simulator); the first one doesn't.
            return try? detect(revision: VNDetectBarcodesRequestRevision1)
        }
    }
}

// Looks products up in Open Food Facts, a free public food database (no account needed).
enum OpenFoodFacts {
    static func lookup(barcode: String) async throws -> ScannedFood {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty,
              var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json")
        else { throw FoodScanError.productNotFound }
        components.queryItems = [URLQueryItem(name: "fields",
                                              value: "product_name,brands,serving_size,serving_quantity,nutriments")]
        guard let url = components.url else { throw FoodScanError.productNotFound }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // Open Food Facts asks apps to identify themselves.
        request.setValue("WorkoutGenie/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["status"] as? Int == 1,
              let product = json["product"] as? [String: Any] else { throw FoodScanError.productNotFound }

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        func number(_ value: Any?) -> Double? {
            if let value = value as? Double { return value }
            if let value = value as? String { return Double(value) }
            return nil
        }
        func nutrient(_ key: String) -> Double? { number(nutriments[key]) }

        let servingSize = product["serving_size"] as? String ?? ""
        let servingQuantity = number(product["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil }
        let unit = servingSize.lowercased().contains("ml") ? "ml" : "g"

        // Prefer per-100 values so the amount can be changed; derive them from the serving if needed.
        var per100: Macros?
        let kcal100 = nutrient("energy-kcal_100g") ?? nutrient("energy_100g").map { $0 / 4.184 }
        let p100 = nutrient("proteins_100g"), c100 = nutrient("carbohydrates_100g"), f100 = nutrient("fat_100g")
        if kcal100 != nil || p100 != nil || c100 != nil || f100 != nil {
            let p = p100 ?? 0, c = c100 ?? 0, f = f100 ?? 0
            per100 = Macros(calories: kcal100 ?? NutritionGoals.calories(protein: p, carbs: c, fat: f),
                            protein: p, carbs: c, fat: f)
        } else if let quantity = servingQuantity,
                  let kcal = nutrient("energy-kcal_serving") {
            let scale = 100 / quantity
            per100 = Macros(calories: kcal * scale,
                            protein: (nutrient("proteins_serving") ?? 0) * scale,
                            carbs: (nutrient("carbohydrates_serving") ?? 0) * scale,
                            fat: (nutrient("fat_serving") ?? 0) * scale)
        }
        guard let per100 else { throw FoodScanError.noNutrition }

        let productName = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let brand = (product["brands"] as? String)?.split(separator: ",").first.map(String.init) ?? ""
        let name = productName.isEmpty ? (brand.isEmpty ? "Scanned product" : brand) : productName

        let note = servingQuantity == nil
            ? "From Open Food Facts, per 100 \(unit). Set the amount you had."
            : "From Open Food Facts, set to one serving (\(servingSize)). Change the amount if you had more or less."
        return ScannedFood(name: name, per100: per100,
                           defaultAmount: servingQuantity ?? 100, amountUnit: unit, note: note)
    }
}

// Live barcode scanning with the camera, plus typing the number by hand.
struct BarcodeScannerSheet: View {
    let onCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingEntry = false
    @State private var typed = ""

    static var isLiveScanningAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            LiveBarcodeScanner { code in finish(with: code) }
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    Text("Point the camera at the barcode")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 40)
                }
                .navigationTitle("Scan Barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Type number") { showingEntry = true }
                    }
                }
                .alert("Barcode number", isPresented: $showingEntry) {
                    TextField("e.g. 5449000000996", text: $typed)
                        .keyboardType(.numberPad)
                    Button("Look up") { finish(with: typed) }
                    Button("Cancel", role: .cancel) { typed = "" }
                }
        }
    }

    private func finish(with code: String) {
        dismiss()
        onCode(code)
    }
}

private struct LiveBarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var found = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !found else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue {
                    found = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCode(code)
                    return
                }
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
