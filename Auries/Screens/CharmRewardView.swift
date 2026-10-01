import SwiftUI

/// The SEPARATE task-reward celebration (Phase E): a small reusable
/// sheet for any charm earned through a task — presented by whichever
/// feature hosted the completing activity, only AFTER that activity's
/// own presentation is done. Never rendered inside the activity itself
/// (the Wonder card, Calm, etc. stay reward-free). Not a generic
/// rewards framework: one charm, one sheet.
struct CharmRewardView: View {
    let reward: AppModel.CharmTaskResult
    /// True when the host gave this card a sheet taller than its content
    /// (iPad's full-height form sheet), so it centres instead of stranding
    /// the buttons above a half-empty panel. The presenter decides because
    /// an iPad form sheet is narrow enough to report a COMPACT width class
    /// from in here — the container's height is not visible to this view.
    var centersVertically: Bool = false
    @Environment(\.dismiss) private var dismiss

    private var def: CharmDefinition? {
        reward.task.rewardCharmID.flatMap(AurieCharmCatalog.definition)
    }

    var body: some View {
        VStack(spacing: 16) {
            if centersVertically { Spacer(minLength: 0) }
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow.opacity(0.9))
                Text(reward.newlyUnlocked ? "New Charm!" : "Task Completed")
                    .font(.title3.weight(.bold))
            }
            .padding(.top, 26)

            Group {
                if let def {
                    CharmArt(def: def)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(width: 150, height: 150)
            .padding(14)
            .background(.white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 28))

            Text(def?.displayName ?? "Charm")
                .font(.title2.weight(.semibold))

            Text(reward.newlyUnlocked
                 ? "You earned a new charm."
                 : "“\(reward.task.title)” is complete.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Button("View Charms") {
                    dismiss()
                    // Same deep-link pattern the widget uses for Home.
                    NotificationCenter.default.post(
                        name: .auriesOpenCharms, object: nil)
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 40)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.07, green: 0.075, blue: 0.10)
            .ignoresSafeArea())
        #if DEBUG
        // Capture aid, twin of AURIE_WONDER_AUTOCLOSE: acknowledge the card
        // after N seconds so a QUEUE of rewards can be captured without taps.
        // Calls the same dismiss() the Done button calls, so the queue
        // advances through the real path. AURIE_REWARD_AUTOCLOSE=3
        .onAppear {
            if let raw = ProcessInfo.processInfo
                .environment["AURIE_REWARD_AUTOCLOSE"],
               let secs = Double(raw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                    dismiss()
                }
            }
        }
        #endif
    }
}
