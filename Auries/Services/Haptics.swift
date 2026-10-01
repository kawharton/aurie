import UIKit

/// One-line haptic hooks (§8.7). iOS itself respects the system haptics
/// setting, so these are safe to call unconditionally.
enum Haptics {
    static func light()  { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func soft()   { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6) }
    /// The special moment (Starlight hatch, rare delights).
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
