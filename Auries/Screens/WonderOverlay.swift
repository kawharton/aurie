import SwiftUI

/// The Today's Wonder moment, drawn OVER the live Home play area.
///
/// There is no separate screen and no second creature: Home dims a little, a
/// curved-glass shimmer forms over the play space, and the real Home Aurie —
/// full size, in its own family environment — is the one the magic happens to.
/// The swirl itself lives in `CreatureScene` (particles have to straddle the
/// creature's z to pass behind it); everything here is the glass, the dim and
/// the Wonder surface.
enum WonderStage {
    /// Nothing running; Home is completely normal.
    case off
    /// Glass forming, particles waking, Aurie going dizzy.
    case swirling
    /// Today's Wonder is on screen and readable.
    case reading
}

/// A BRIEF glass shimmer over the play area at the moment of the shake.
///
/// Deliberately lightweight. Earlier versions tinted and dimmed the whole
/// screen for the full sequence, which washed out the family environment,
/// dulled Aurie and read as a modal scrim rather than glass. The snow-globe
/// illusion is carried by the particles now; this is only the moment of
/// "something just happened to the world", and it is gone within a second.
///
/// Confined to the environment — never over the top bar, Calm, Settings, the
/// tab bar or the Today's Spark chip.
struct WonderGlassView: View {
    let aura: Rgb
    /// 0 = absent, 1 = fully formed. Driven up fast and back down by ~0.8 s.
    var amount: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // One soft curved specular sweeping across the play area.
                Ellipse()
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.42), .white.opacity(0.10), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: w * 1.05, height: h * 0.17)
                    .rotationEffect(.degrees(-19))
                    .offset(x: -w * 0.06, y: -h * 0.24)
                    .blur(radius: 10)
                    .blendMode(.screen)

                // Faint secondary arc near the opposite edge.
                Ellipse()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: w * 0.52, height: h * 0.07)
                    .rotationEffect(.degrees(14))
                    .offset(x: w * 0.16, y: h * 0.25)
                    .blur(radius: 12)
                    .blendMode(.screen)

                // Very subtle refraction at the play-area perimeter. No fill,
                // no tint — the environment keeps its own colour and contrast.
                RoundedRectangle(cornerRadius: HomeTokens.cardCornerRadius,
                                 style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.30),
                                     Color(aura, brightness: 0.9).opacity(0.18),
                                     .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: min(w, h) * 0.035)
                    .blur(radius: 10)
                    .blendMode(.screen)
            }
            .compositingGroup()
            .opacity(amount)
        }
        .allowsHitTesting(false)
    }
}

/// The Wonder itself, materialising out of the settling particles.
struct WonderSurface: View {
    // Deliberately charm-free (Phase E separation): the Wonder feature
    // only EMITS its completion event — it never renders task rewards,
    // progress, or charm art. Reward celebration is its own
    // presentation, after this card is dismissed.
    let spark: DailyLiftItem
    let aura: Rgb
    let saved: Bool
    var onSave: () -> Void
    var onOpenBook: () -> Void
    var onClose: () -> Void

    /// Staged in: label, then text, then the controls — so it resolves rather
    /// than popping in as one card.
    @State private var labelIn = false
    @State private var textIn = false
    @State private var controlsIn = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Today's Spark")
                .font(.caption.weight(.semibold))
                .kerning(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Color(aura, brightness: 0.95).opacity(0.9))
                .opacity(labelIn ? 1 : 0)

            // Small secondary flavour — the primary branding stays "Spark".
            Text(spark.kind.sparkLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .opacity(labelIn ? 0.85 : 0)

            Text(spark.text)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(textIn ? 1 : 0)
                .blur(radius: textIn ? 0 : 5)

            HStack(spacing: 10) {
                Button(action: onSave) {
                    Label(saved ? "In Wonderbook" : "Save to Wonderbook",
                          systemImage: saved ? "checkmark.seal.fill" : "bookmark")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(saved)
                .foregroundStyle(saved ? Color(aura, brightness: 0.95) : .white)

                Button(action: onOpenBook) {
                    // An OPEN book, recognisable at a glance — `books.vertical`
                    // reads as a shelf, not a book you can open.
                    Image(systemName: "book.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(9)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Wonderbook")
            }
            .opacity(controlsIn ? 1 : 0)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 22)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color(aura, brightness: 0.9).opacity(0.28),
                                      lineWidth: 1)
                )
                .shadow(color: Color(aura).opacity(0.35), radius: 24)
        }
        // Explicit dismissal, top-right, so leaving is obvious rather than
        // something the user has to guess at.
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .opacity(controlsIn ? 1 : 0)
            .accessibilityLabel("Close today's Spark")
        }
        .contentShape(Rectangle())
        .task {
            withAnimation(.easeOut(duration: 0.45)) { labelIn = true }
            try? await Task.sleep(for: .seconds(0.22))
            withAnimation(.easeOut(duration: 0.55)) { textIn = true }
            try? await Task.sleep(for: .seconds(0.30))
            withAnimation(.easeOut(duration: 0.40)) { controlsIn = true }
        }
    }
}
