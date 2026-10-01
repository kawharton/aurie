import SwiftUI

/// The Play Shelf: a small, quiet toy tray floating in the play area's
/// corner. Collapsed it is one soft glass button; open it offers the four
/// play objects, each drawn with the SAME procedural art the scene spawns,
/// so the shelf promises exactly what the toy delivers. Selecting a toy
/// activates it in the live scene; selecting it again puts it away. One toy
/// at a time, no badges, no counters — just toys.
struct PlayShelfView: View {
    @Environment(AppModel.self) private var model
    let handle: SceneHandle
    @Binding var activeToy: PlayToy?
    @Binding var radioOut: Bool
    /// True while a Toy Box tutorial greeting is showing: the closed shelf
    /// pulses a few times so the player can see what the Aurie means.
    var attention: Bool = false
    @State private var isOpen = false

    var body: some View {
        HStack(spacing: 10) {
            if isOpen {
                ForEach(PlayToy.shelf, id: \.rawValue) { toy in
                    toyButton(toy)
                        .transition(.scale.combined(with: .opacity))
                }
                radioButton
                    .transition(.scale.combined(with: .opacity))
            }
            toggleButton
        }
        .padding(.horizontal, isOpen ? 10 : 0)
        .padding(.vertical, isOpen ? 8 : 0)
        .background {
            if isOpen {
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            }
        }
        .animation(.spring(duration: 0.35), value: isOpen)
        .animation(.spring(duration: 0.3), value: activeToy)
        .animation(.spring(duration: 0.3), value: radioOut)
    }

    private func toyButton(_ toy: PlayToy) -> some View {
        Button {
            let next: PlayToy? = activeToy == toy ? nil : toy
            activeToy = next
            handle.scene?.setActiveToy(next)
            if next != nil {
                withAnimation(.spring(duration: 0.35)) { isOpen = false }
            }
        } label: {
            Image(uiImage: ToyBox.icon(for: toy))
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .padding(5)
                .background {
                    Circle().fill(.white.opacity(activeToy == toy ? 0.22 : 0.06))
                }
                .overlay {
                    if activeToy == toy {
                        Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(toy.label)
        .accessibilityIdentifier("toy_\(toy.rawValue)")
    }

    /// The radio sits on the same tray as the toys — bring it out, put it
    /// away. Its transport (play/pause, next loop) lives on the object itself
    /// in the scene, so the shelf stays a tray and never becomes a music UI.
    private var radioButton: some View {
        Button {
            radioOut.toggle()
            handle.scene?.setRadio(out: radioOut)
            if radioOut {
                withAnimation(.spring(duration: 0.35)) { isOpen = false }
            }
        } label: {
            Image(uiImage: RadioBox.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .padding(5)
                .background {
                    Circle().fill(.white.opacity(radioOut ? 0.22 : 0.06))
                }
                .overlay {
                    if radioOut {
                        Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Radio")
        .accessibilityIdentifier("toy_radio")
    }

    private var toggleButton: some View {
        Button {
            withAnimation(.spring(duration: 0.35)) { isOpen.toggle() }
            // Feature discovery: opening the shelf once retires the Toy Box
            // tutorial greeting for good.
            if isOpen, !model.store.settings.hasOpenedToyBox {
                model.store.settings.hasOpenedToyBox = true
            }
        } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                if let activeToy, !isOpen {
                    // The active toy peeks from the closed shelf.
                    Image(uiImage: ToyBox.icon(for: activeToy))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                } else {
                    // TOYS, not magic. This used `sparkles`, which made it read as a
                    // second Wonder control. Magical language is reserved for
                    // the single Wonder trigger in the top bar.
                    Image(systemName: isOpen ? "xmark" : "teddybear.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .attentionBlink(active: attention)
        .accessibilityLabel("Play shelf")
        .accessibilityIdentifier("playShelf")
    }
}
