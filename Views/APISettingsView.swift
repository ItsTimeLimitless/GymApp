import SwiftUI

/// Lets you paste your Hugging Face API token in once — stored in the
/// Keychain, never in source. Only needed for the "Identify equipment"
/// photo feature; everything else in GymApp works without it.
struct APISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token: String = KeychainHelper.read(key: .huggingFaceToken) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Hugging Face API token", text: $token)
                } footer: {
                    Text("Used only when you tap \"Identify equipment\" on a photo of a machine. Get a token at huggingface.co/settings/tokens.")
                }
            }
            .navigationTitle("Photo-ID setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        KeychainHelper.save(token, key: .huggingFaceToken)
                        dismiss()
                    }
                }
            }
        }
    }
}
