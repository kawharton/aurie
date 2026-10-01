import SwiftUI

/// Earn Charms (Phase E): the player-facing tasks page, PUSHED from the
/// Charms page with a standard Back control — deliberately NOT a fifth
/// tab. Cards come from `CharmTaskCatalog` (data, so future tasks are
/// new entries, not new UI), completion state comes from the grant
/// LEDGER (never reward ownership), and rewards are real charms — no
/// currencies, points or streaks.
struct EarnCharmsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    header
                    ForEach(CharmTaskCatalog.all) { task in
                        CharmTaskCard(
                            task: task,
                            progress: model.charmTaskProgress(task),
                            completed: model.isCharmTaskCompleted(task))
                            .id(task.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            #if DEBUG
            // Capture aid: land scrolled to the bottom so the full
            // 12-task list is screenshottable in two shots.
            .onAppear {
                if ProcessInfo.processInfo
                    .environment["AURIE_TASKS_SCROLL_BOTTOM"] == "1",
                   let last = CharmTaskCatalog.all.last {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            #endif
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(red: 0.07, green: 0.075, blue: 0.10)
            .ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Earn Charms")
                .font(.title2.weight(.bold))
            Text("Complete tasks to earn more charms.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }
}

/// One task card: what to do, and — prominently — what it earns.
private struct CharmTaskCard: View {
    let task: CharmTaskDefinition
    let progress: Int
    let completed: Bool

    private var rewardDef: CharmDefinition? {
        task.rewardCharmID.flatMap(AurieCharmCatalog.definition)
    }
    /// The reward art was pulled and no replacement is assigned yet.
    private var rewardPending: Bool { task.rewardCharmID == nil }

    var body: some View {
        HStack(spacing: 14) {
            // The reward is the point: big, colorful, unmistakable.
            VStack(spacing: 6) {
                Group {
                    if let def = rewardDef {
                        CharmArt(def: def)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .frame(width: 74, height: 74)
                .padding(6)
                .background(.white.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 16))
                Text(rewardDef?.displayName ?? (rewardPending ? "Soon" : "Charm"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(rewardPending ? 0.55 : 0.9))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(task.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                stateRow
                    .padding(.top, 7)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 20))
    }

    /// Multi-step state: a slim progress bar + "n / target", flipping
    /// to the green check once the ledger says completed.
    @ViewBuilder private var stateRow: some View {
        if rewardPending {
            // Honest state: the task exists but cannot award yet, so
            // showing a progress bar (or "completed") would lie.
            Text("Reward coming soon")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.06), in: Capsule())
                .foregroundStyle(.secondary)
        } else if completed {
            Label("Completed", systemImage: "checkmark")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.18), in: Capsule())
                .foregroundStyle(.green)
        } else {
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.10))
                        Capsule()
                            .fill(Color.yellow.opacity(0.85))
                            .frame(width: geo.size.width
                                   * CGFloat(min(progress, task.target))
                                   / CGFloat(max(task.target, 1)))
                    }
                }
                .frame(height: 6)
                Text("\(progress) / \(task.target)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
        }
    }
}
