import Foundation
import Observation

// MARK: - Arrival gate

/// Decides WHEN Home greets, so that tab switches and child screens never
/// count. Armed once per process launch; HomeView consumes it on the first
/// appearance and re-arms it only for real arrivals (a long enough time in
/// the background, or the first hatch replacing the greeter). A static,
/// not view state: SwiftUI can rebuild HomeView freely without re-greeting.
@MainActor @Observable
final class HomeGreetingSession {
    static let shared = HomeGreetingSession()

    private(set) var armed = true
    /// Bumped on every re-arm so an on-screen Home can react (the DEBUG
    /// demo menu uses this to replay a greeting without relaunching).
    private(set) var generation = 0
    /// The feature taught last, so the next tutorial prefers a different one.
    var lastTutorial: DiscoverableFeature?

    func consume() { armed = false }
    func rearm() { armed = true; generation += 1 }
}
