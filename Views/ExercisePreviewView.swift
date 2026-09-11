import SwiftUI

/// Shows the two-photo demo sequence for an exercise, cross-fading
/// between them in a loop to suggest the movement — used both before
/// starting a workout (from the preview screen) and mid-set (a small
/// corner button in LogSetView, so you can double check form without
/// leaving the capture screen).
struct ExercisePreviewView: View {
    let exerciseName: String
    let demoAssetId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var showingSecondFrame = false

    private var startImage: UIImage? { loadImage(frame: 0) }
    private var endImage: UIImage? { loadImage(frame: 1) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let startImage, let endImage {
                    ZStack {
                        Image(uiImage: startImage)
                            .resizable()
                            .scaledToFit()
                            .opacity(showingSecondFrame ? 0 : 1)
                        Image(uiImage: endImage)
                            .resizable()
                            .scaledToFit()
                            .opacity(showingSecondFrame ? 1 : 0)
                    }
                    // Scoped directly to this ZStack via .animation(value:)
                    // rather than a global withAnimation() call — that's
                    // what was leaking the repeating loop into unrelated
                    // parts of the screen (the toolbar's "Done" button
                    // included), since withAnimation applies to the whole
                    // transaction, not just the view it's called near.
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: showingSecondFrame)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .onAppear { showingSecondFrame = true }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No demo photo for this one yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Spacer()
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func loadImage(frame: Int) -> UIImage? {
        guard let demoAssetId,
              let url = Bundle.main.url(forResource: "\(frame)", withExtension: "jpg", subdirectory: "PhotoAssets/\(demoAssetId)"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }
}

/// Small rounded thumbnail — frame 0 of the demo sequence, or a
/// placeholder icon if there isn't one. Used directly in exercise list
/// rows so you can recognize a movement at a glance without opening
/// the full preview.
struct ExerciseThumbnailView: View {
    let demoAssetId: String?
    var size: CGFloat = 54

    var body: some View {
        Group {
            if let demoAssetId,
               let url = Bundle.main.url(forResource: "0", withExtension: "jpg", subdirectory: "PhotoAssets/\(demoAssetId)"),
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(.secondarySystemBackground)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Small, unobtrusive corner button — same quiet-text visual weight as
/// LogSetView's "Skip Rest", so it doesn't compete with the actual
/// logging controls. Shown whether or not a demo photo exists; if one
/// doesn't, ExercisePreviewView says so rather than the button vanishing
/// and looking broken.
struct ExercisePreviewButton: View {
    let exerciseName: String
    let demoAssetId: String?
    @State private var showingPreview = false

    var body: some View {
        Button {
            showingPreview = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundColor(GymTheme.textSecondary)
                .padding(10)
        }
        .sheet(isPresented: $showingPreview) {
            ExercisePreviewView(exerciseName: exerciseName, demoAssetId: demoAssetId)
        }
    }
}
