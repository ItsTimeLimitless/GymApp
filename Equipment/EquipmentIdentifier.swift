import Foundation
import UIKit

/// Sends a photo of unfamiliar gym equipment to a captioning model on
/// Hugging Face and gets back a plain description to cache locally.
/// This is the one deliberate exception to "everything stays
/// on-device" — a photo of gym equipment, nothing personal, sent only
/// when you explicitly tap "Identify equipment". Every other feature in
/// GymApp works with zero network calls.
///
/// Uses a basic image-captioning model rather than a full
/// instruction-following vision model — chosen specifically because it
/// runs on Hugging Face's own free serverless infrastructure rather
/// than being routed to a paid third-party provider, so there's no
/// billing risk. The tradeoff: it just describes what's in the photo
/// ("a machine with weights attached to it"), it doesn't reason about
/// what the machine is called or how to use it safely — there's no
/// usage-instructions field here the way a fuller model could give.
enum EquipmentIdentifier {
    struct IdentifiedEquipment {
        let name: String
        let rawResponse: String
    }

    enum IdentifierError: LocalizedError {
        case noAPIToken
        case invalidResponse
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAPIToken:
                return "Add your Hugging Face API token first (the key icon on the home screen)."
            case .invalidResponse:
                return "Could not read a response from the model."
            case .requestFailed(let message):
                return "Request failed: \(message)"
            }
        }
    }

    // Runs on Hugging Face's own free inference infrastructure, not a
    // paid third-party provider — swap models at huggingface.co/models
    // (filter: image-to-text) if this one's ever taken down, but keep
    // that "not provider-routed" property in mind when picking a
    // replacement, since that's specifically what avoids billing risk.
    private static let model = "Salesforce/blip-image-captioning-large"
    private static let endpoint = URL(string: "https://api-inference.huggingface.co/models/\(model)")!

    static func identify(image: UIImage) async throws -> IdentifiedEquipment {
        guard let apiToken = KeychainHelper.read(key: .huggingFaceToken), !apiToken.isEmpty else {
            throw IdentifierError.noAPIToken
        }
        guard let jpegData = image.jpegData(compressionQuality: 0.7) else {
            throw IdentifierError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpegData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw IdentifierError.requestFailed(message)
        }

        // Response shape: [{"generated_text": "a machine with weights..."}]
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let caption = json.first?["generated_text"] as? String,
            !caption.isEmpty
        else {
            throw IdentifierError.invalidResponse
        }

        return IdentifiedEquipment(
            name: caption.prefix(1).capitalized + caption.dropFirst(),
            rawResponse: caption
        )
    }
}
