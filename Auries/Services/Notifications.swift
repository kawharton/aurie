import Foundation
import UserNotifications

/// Daily local notification (§12) — strictly **pre-photo** copy: gentle
/// invitations to go find something to hatch. NEVER "a new egg is ready"
/// before the user has taken a photo (there is no async egg in this app, so
/// post-photo copy is unused by design).
enum Notifications {

    private static let prePhotoLines = [
        "Who will hatch today?",
        "Something ordinary is waiting to become magical.",
        "Find something tiny to hatch.",
    ]

    /// Ask permission (first enable) and schedule the daily nudge.
    /// Returns whether notifications are actually authorized.
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        if granted { await scheduleDaily() }
        return granted
    }

    static func disable() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private static func scheduleDaily() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let content = UNMutableNotificationContent()
        content.title = "Aurie"
        content.body = prePhotoLines.randomElement() ?? prePhotoLines[0]
        content.sound = .default
        var at = DateComponents()
        at.hour = 10   // a friendly mid-morning nudge
        let trigger = UNCalendarNotificationTrigger(dateMatching: at, repeats: true)
        try? await center.add(UNNotificationRequest(
            identifier: "aurie.daily.prephoto", content: content, trigger: trigger))
    }
}
