import SwiftUI
import UIKit
import Security

// What Claude estimated from a food photo.
struct FoodEstimate: Decodable {
    let isFood: Bool
    let name: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let confidence: String  // "low", "medium" or "high"
    let notes: String

    enum CodingKeys: String, CodingKey {
        case isFood = "is_food", name, calories
        case proteinG = "protein_g", carbsG = "carbs_g", fatG = "fat_g"
        case confidence, notes
    }
}

enum FoodPhotoError: LocalizedError {
    case missingKey, notFood, refused, unreadable
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Anthropic API key in Settings › Food photo scanning."
        case .notFood: "That photo doesn't seem to show food. Try again with the meal in frame."
        case .refused: "Claude couldn't analyse this photo. Try a different one."
        case .unreadable: "The estimate came back incomplete. Please try again."
        case .api(let message): message
        }
    }
}

// Sends a food photo to Claude and returns its estimate.
// This is the only file that talks to the network: to move the API key onto
// your own server later, point `analyze(_:)` at that server instead.
enum FoodPhotoAnalyzer {
    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static var hasKey: Bool { APIKeyStore.read() != nil }

    static func analyze(_ image: UIImage) async throws -> FoodEstimate {
        guard let key = APIKeyStore.read() else { throw FoodPhotoError.missingKey }
        guard let jpeg = jpegData(for: image) else { throw FoodPhotoError.unreadable }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Lets another model answer if the main one declines the photo.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(imageBase64: jpeg.base64EncodedString()))

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200, let json else {
            throw FoodPhotoError.api(errorMessage(status: status, json: json))
        }

        switch json["stop_reason"] as? String {
        case "refusal": throw FoodPhotoError.refused
        case "max_tokens": throw FoodPhotoError.unreadable
        default: break
        }

        // The answer is the last text block; thinking blocks come before it.
        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let text = blocks.last(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let estimate = try? JSONDecoder().decode(FoodEstimate.self, from: Data(text.utf8)) else {
            throw FoodPhotoError.unreadable
        }
        guard estimate.isFood else { throw FoodPhotoError.notFood }
        return estimate
    }

    private static let instructions = """
        You estimate nutrition from photos for a food-logging app. Identify the food and drink \
        in the photo, estimate the portion actually shown, and give totals for everything visible \
        (not per 100 g). Allow for likely cooking oil, butter, sauces and dressings, since people \
        tend to under-log these. If a nutrition label is visible, use its values for the serving shown. \
        Give a short, plain name such as "Chicken, rice and broccoli". In notes, say in one sentence \
        what you assumed about portion size or hidden ingredients. Set confidence to low when the \
        portion or ingredients are hard to judge. If the photo shows no food or drink, set is_food \
        to false and use 0 for every number.
        """

    private static func requestBody(imageBase64: String) -> [String: Any] {
        let number: [String: Any] = ["type": "number"]
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "is_food": ["type": "boolean"],
                "name": ["type": "string"],
                "calories": number,
                "protein_g": number,
                "carbs_g": number,
                "fat_g": number,
                "confidence": ["type": "string", "enum": ["low", "medium", "high"]],
                "notes": ["type": "string"]
            ],
            "required": ["is_food", "name", "calories", "protein_g", "carbs_g", "fat_g", "confidence", "notes"],
            "additionalProperties": false
        ]
        return [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "system": instructions,
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": schema]
            ],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64", "media_type": "image/jpeg", "data": imageBase64]],
                    ["type": "text", "text": "Estimate the nutrition for this meal."]
                ]
            ]]
        ]
    }

    // Phone photos are far bigger than needed; 1568 px on the long side keeps detail and cost down.
    private static func jpegData(for image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 1568 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    private static func errorMessage(status: Int, json: [String: Any]?) -> String {
        switch status {
        case 401, 403: return "Your API key was rejected. Check it in Settings › Food photo scanning."
        case 429: return "Too many scans right now. Try again in a minute."
        case 500...599: return "Claude is busy right now. Try again shortly."
        default:
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            return message ?? "Something went wrong (error \(status))."
        }
    }
}

// Keeps the API key in the iPhone Keychain, never in plain settings.
enum APIKeyStore {
    private static let service = "WorkoutGenie.AnthropicAPIKey"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

// Settings › Food photo scanning: add or remove the API key.
struct PhotoScanSettingsView: View {
    @State private var keyInput = ""
    @State private var hasKey = FoodPhotoAnalyzer.hasKey
    @State private var saveFailed = false

    private var trimmedKey: String {
        keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                if hasKey {
                    Label("Key saved on this iPhone", systemImage: "checkmark.seal.fill")
                    Button("Remove key", role: .destructive) {
                        APIKeyStore.delete()
                        hasKey = false
                    }
                } else {
                    SecureField("sk-ant-…", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key") {
                        hasKey = APIKeyStore.save(trimmedKey)
                        saveFailed = !hasKey
                        keyInput = ""
                    }
                    .disabled(trimmedKey.isEmpty)
                }
            } header: {
                Text("Anthropic API key")
            } footer: {
                Text("Stored in the iPhone Keychain and only sent to Anthropic when you scan a photo. Each scan costs a few cents at most on your Anthropic account. Create a key at console.anthropic.com.")
            }
        }
        .navigationTitle("Food Photo Scanning")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't save the key", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        }
    }
}

// The system camera, for snapping a meal.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
