import SwiftUI
import AVKit

/// First-run tutorial (§6): shows once on first launch, replayable from
/// Settings → How to play. Placeholder per the runs-empty rule: three animated
/// walkthrough pages. TODO(art): when real clips exist, bundle `tutorial.mp4`
/// and this view plays it instead of the slides automatically.
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.10).ignoresSafeArea()

            if let url = Bundle.main.url(forResource: "tutorial", withExtension: "mp4") {
                // Real tutorial video drop-in seam.
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            } else {
                TabView(selection: $page) {
                    tutorialPage(
                        icon: "camera.viewfinder",
                        title: "Photograph anything",
                        text: "Take a photo of any object. Its color and shape become a magical egg."
                    ).tag(0)
                    tutorialPage(
                        icon: "hand.tap",
                        title: "Tap to hatch",
                        text: "Tap the egg to crack it open and meet your new Aurie. Every one is unique, and every one is saved."
                    ).tag(1)
                    tutorialPage(
                        icon: "hands.and.sparkles",
                        title: "Play together",
                        text: "Tap it, pet it with a stroke, tickle it with quick taps, hold to pick it up, or shake your phone and see what happens."
                    ).tag(2)
                }
                .tabViewStyle(.page)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(page >= 2 ? "Start" : "Skip") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(20)
        }
        .preferredColorScheme(.dark)
    }

    private func tutorialPage(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
                .symbolEffect(.pulse)
            Text(title)
                .font(.title2.weight(.bold))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
