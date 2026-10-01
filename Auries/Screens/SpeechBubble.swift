import SwiftUI

/// A rounded speech bubble whose tail can sit on any edge and slide along it,
/// so the tail keeps pointing at the creature wherever the bubble had to be
/// placed (Stage C). Used for the daily greeting line and play reaction barks.
struct SpeechBubble: View {
    /// Which edge the tail sits on, and how far it slides along that edge from
    /// the bubble's centre (x for top/bottom edges, y for the sides).
    struct Tail: Equatable {
        var edge: Edge = .bottom
        var offset: CGFloat = 0
    }

    let text: String
    var tail = Tail()

    var body: some View {
        Text(text)
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.white)
                    .overlay(alignment: tailAlignment) {
                        BubbleTail(edge: tail.edge)
                            .fill(.white)
                            .frame(width: tailSize.width, height: tailSize.height)
                            .offset(tailOffset)
                            .accessibilityHidden(true)   // decorative pointer only
                    }
            }
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private var tailAlignment: Alignment {
        switch tail.edge {
        case .bottom: .bottom
        case .top: .top
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    private var tailSize: CGSize {
        switch tail.edge {
        case .top, .bottom: CGSize(width: 22, height: 12)
        case .leading, .trailing: CGSize(width: 12, height: 22)
        }
    }

    /// Push the tail just past the bubble edge (2 pt stays tucked under the
    /// rounded rect so the two shapes read as one), then slide it along the
    /// edge toward the creature.
    private var tailOffset: CGSize {
        switch tail.edge {
        case .bottom: CGSize(width: tail.offset, height: 10)
        case .top: CGSize(width: tail.offset, height: -10)
        case .leading: CGSize(width: -10, height: tail.offset)
        case .trailing: CGSize(width: 10, height: tail.offset)
        }
    }
}

/// Triangle pointing away from the bubble, out of the given edge.
private struct BubbleTail: Shape {
    var edge: Edge = .bottom

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch edge {
        case .bottom:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        case .top:
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        case .leading:
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        case .trailing:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        p.closeSubpath()
        return p
    }
}
