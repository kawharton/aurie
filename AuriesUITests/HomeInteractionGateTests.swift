import XCTest

/// The Home interaction completion gate, driven by REAL system touch events
/// (XCUITest), not synthesized calls into the reaction functions. Every tap
/// travels the full UIKit pipeline — hit-testing, `touchesBegan/Ended`, the
/// scene's region classifier — exactly as a finger does.
///
/// Tap coordinates come from the `AURIE_REGION_AUDIT` overlay pass: the
/// window-space centres of each body's LIVE sprite regions on the iPhone 17
/// simulator (402x874pt). They are asserted against `AURIE_TOUCH_LOG`
/// externally (the harness tails the log while this runs).
final class HomeInteractionGateTests: XCTestCase {

    enum Region { case head, belly, armLeft, armRight, footLeft, footRight }

    /// Window-space tap points per body, measured from the live sprite frames.
    static let points: [String: [Region: CGPoint]] = [
        "round": [.head: CGPoint(x: 201.0, y: 369.9), .belly: CGPoint(x: 201.0, y: 431.7), .armLeft: CGPoint(x: 128.7, y: 452.6), .armRight: CGPoint(x: 273.3, y: 452.4), .footLeft: CGPoint(x: 173.5, y: 498.7), .footRight: CGPoint(x: 228.3, y: 498.7)],
        "tall": [.head: CGPoint(x: 201.0, y: 369.9), .belly: CGPoint(x: 201.0, y: 432.8), .armLeft: CGPoint(x: 143.9, y: 457.3), .armRight: CGPoint(x: 258.1, y: 457.3), .footLeft: CGPoint(x: 179.0, y: 498.7), .footRight: CGPoint(x: 223.0, y: 498.6)],
        "small": [.head: CGPoint(x: 201.0, y: 370.2), .belly: CGPoint(x: 201.0, y: 431.0), .armLeft: CGPoint(x: 135.9, y: 455.5), .armRight: CGPoint(x: 266.1, y: 455.6), .footLeft: CGPoint(x: 173.5, y: 494.7), .footRight: CGPoint(x: 228.5, y: 494.7)],
        "pear": [.head: CGPoint(x: 201.0, y: 370.0), .belly: CGPoint(x: 201.0, y: 432.2), .armLeft: CGPoint(x: 136.6, y: 454.9), .armRight: CGPoint(x: 265.5, y: 454.7), .footLeft: CGPoint(x: 176.9, y: 498.5), .footRight: CGPoint(x: 224.9, y: 498.5)],
        "beanbag": [.head: CGPoint(x: 201.6, y: 373.7), .belly: CGPoint(x: 201.6, y: 430.6), .armLeft: CGPoint(x: 117.8, y: 454.7), .armRight: CGPoint(x: 284.7, y: 455.7), .footLeft: CGPoint(x: 163.9, y: 492.4), .footRight: CGPoint(x: 238.2, y: 492.9)],
        "heart": [.head: CGPoint(x: 201.0, y: 367.1), .belly: CGPoint(x: 201.0, y: 430.0), .armLeft: CGPoint(x: 135.5, y: 453.3), .armRight: CGPoint(x: 266.5, y: 453.3), .footLeft: CGPoint(x: 178.7, y: 497.2), .footRight: CGPoint(x: 223.3, y: 497.2)],
    ]

    private func launch(body: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "AURIE_SEED_HOME": "1",
            "AURIE_BLENDER_DEMO": "ember",
            "AURIE_BLENDER_BODY": body,
            "AURIE_TOUCH_LOG": "1",
            "AURIE_TOY_LOG": "1",
        ]
        app.launch()
        sleep(3)   // scene settles; greeting bubble appears
        return app
    }

    private func tap(_ app: XCUIApplication, _ body: String, _ region: Region,
                     settle: UInt32 = 2) {
        let p = Self.points[body]![region]!
        let size = app.windows.firstMatch.frame.size
        let c = app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: p.x / size.width,
                                                       dy: p.y / size.height))
        c.tap()
        sleep(settle)
    }

    /// The full nine-step gate on Round, at normal speed, for the recording.
    func testGateRound() {
        let app = launch(body: "round")
        let win = app.windows.firstMatch
        let size = win.frame.size

        sleep(4)                                     // 1. untouched idle

        // 2. drag through EMPTY space (left of the creature): pupils follow.
        let from = win.coordinate(withNormalizedOffset:
            CGVector(dx: 60 / size.width, dy: 430 / size.height))
        let to = win.coordinate(withNormalizedOffset:
            CGVector(dx: 60 / size.width, dy: 620 / size.height))
        from.press(forDuration: 0.3, thenDragTo: to,
                   withVelocity: .slow, thenHoldForDuration: 0.6)
        sleep(2)                                     // eyes return to rest

        tap(app, "round", .belly, settle: 3)         // 3. belly tickle
        tap(app, "round", .head, settle: 3)          // 4. head reaction
        tap(app, "round", .footLeft, settle: 3)      // 5. left-foot kick
        tap(app, "round", .footRight, settle: 3)     // 6. right-foot kick
        tap(app, "round", .armLeft, settle: 3)       // 7. left-arm wave
        tap(app, "round", .armRight, settle: 3)      // 8. right-arm wave

        // 9. several rapid repeats, then rest — alignment check.
        tap(app, "round", .head, settle: 1)
        tap(app, "round", .armRight, settle: 1)
        tap(app, "round", .footLeft, settle: 1)
        tap(app, "round", .belly, settle: 1)
        sleep(5)                                     // settle at rest
    }

    /// Region sweep on the other five bodies: head, feet, arms each classify
    /// and react from a real tap on the visible sprite.
    func testRegionsTall()    { sweep("tall") }
    func testRegionsSmall()   { sweep("small") }
    func testRegionsPear()    { sweep("pear") }
    func testRegionsBeanbag() { sweep("beanbag") }
    func testRegionsHeart()   { sweep("heart") }

    private func sweep(_ body: String) {
        let app = launch(body: body)
        tap(app, body, .head)
        tap(app, body, .footLeft)
        tap(app, body, .footRight)
        tap(app, body, .armLeft)
        tap(app, body, .armRight)
        sleep(3)
    }

    // MARK: - Play toys

    private func windowTap(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) {
        let size = app.windows.firstMatch.frame.size
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: x / size.width,
                                                       dy: y / size.height)).tap()
    }

    private func windowDrag(_ app: XCUIApplication,
                            from: CGPoint, to: CGPoint,
                            hold: TimeInterval = 0.4) {
        let size = app.windows.firstMatch.frame.size
        let a = app.windows.firstMatch.coordinate(withNormalizedOffset:
            CGVector(dx: from.x / size.width, dy: from.y / size.height))
        let b = app.windows.firstMatch.coordinate(withNormalizedOffset:
            CGVector(dx: to.x / size.width, dy: to.y / size.height))
        a.press(forDuration: 0.25, thenDragTo: b,
                withVelocity: .slow, thenHoldForDuration: hold)
    }

    /// The full toy choreography on Round, refinement-pass edition:
    /// bubbles hands-off (autonomous reach/hop-reach/watch/miss), ball
    /// (foot kick, toss toward the body for mid-air hand bats), star
    /// (drag around -> reach-touch -> chest hold for the two-hand catch),
    /// butterfly (chase with movement beats + almost-catch), plus a belly
    /// tap mid-butterfly for interruption and idle homing at the end.
    func testToysRound() {
        let app = launch(body: "round")

        app.buttons["playShelf"].tap(); sleep(1)
        app.buttons["toy_bubble"].tap()
        sleep(27)                                  // autonomous bubble play

        app.buttons["playShelf"].tap(); sleep(1)
        app.buttons["toy_ball"].tap()
        sleep(1)                                   // ball drops to rest
        windowDrag(app, from: CGPoint(x: 287, y: 488),
                   to: CGPoint(x: 235, y: 330))    // toss toward upper body
        sleep(9)                                   // bats + kick rally

        app.buttons["playShelf"].tap(); sleep(1)
        app.buttons["toy_star"].tap()
        sleep(2)
        windowDrag(app, from: CGPoint(x: 115, y: 340),
                   to: CGPoint(x: 272, y: 430), hold: 1.6)   // right + reach
        windowDrag(app, from: CGPoint(x: 272, y: 430),
                   to: CGPoint(x: 201, y: 305), hold: 1.8)   // overhead stretch
        windowDrag(app, from: CGPoint(x: 201, y: 305),
                   to: CGPoint(x: 201, y: 428), hold: 1.8)   // chest -> catch
        sleep(3)

        app.buttons["playShelf"].tap(); sleep(1)
        app.buttons["toy_butterfly"].tap()
        sleep(24)                                  // chase + almost-catch
        tap(app, "round", .belly, settle: 3)       // user wins mid-toy
        sleep(8)
        app.buttons["playShelf"].tap(); sleep(1)
        app.buttons["toy_butterfly"].tap()         // put it away
        sleep(4)
    }

    /// Field-drag QA (perspective correction): six REAL drag gestures — the
    /// grab is a 0.7 s hold on the creature, then a slow drag with the finger
    /// held down. near->far, far->near, both diagonals, a zig-zag, and a
    /// mid-depth hold. Each grab starts where the previous drag ended.
    func testFieldDragQA() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "AURIE_SEED_HOME": "1",
            "AURIE_BLENDER_DEMO": "ember",
            "AURIE_BLENDER_BODY": "round",
            "AURIE_ENV_GREYBOX": "1",
            "AURIE_ENV_ZONES": "1",
            "AURIE_TOUCH_LOG": "1",
        ]
        app.launch()
        sleep(4)
        let win = app.windows.firstMatch
        let size = win.frame.size
        func pt(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            win.coordinate(withNormalizedOffset:
                CGVector(dx: x / size.width, dy: y / size.height))
        }
        func drag(_ from: CGPoint, _ to: CGPoint,
                  hold: TimeInterval = 0.6) {
            pt(from.x, from.y).press(forDuration: 0.7,
                                     thenDragTo: pt(to.x, to.y),
                                     withVelocity: .slow,
                                     thenHoldForDuration: hold)
            sleep(1)
        }
        NSLog("AURIE_DRAGQA d1 near->far")
        drag(CGPoint(x: 201, y: 440), CGPoint(x: 201, y: 300))
        NSLog("AURIE_DRAGQA d2 far->near")
        drag(CGPoint(x: 201, y: 300), CGPoint(x: 201, y: 620))
        NSLog("AURIE_DRAGQA d3 nearC->farR")
        drag(CGPoint(x: 201, y: 620), CGPoint(x: 252, y: 300))
        NSLog("AURIE_DRAGQA d4 farR->nearL")
        drag(CGPoint(x: 252, y: 300), CGPoint(x: 85, y: 615))
        NSLog("AURIE_DRAGQA d5 zigzag")
        drag(CGPoint(x: 85, y: 615), CGPoint(x: 300, y: 430), hold: 0.2)
        drag(CGPoint(x: 300, y: 430), CGPoint(x: 130, y: 560), hold: 0.2)
        NSLog("AURIE_DRAGQA d6 hold mid-depth")
        drag(CGPoint(x: 130, y: 560), CGPoint(x: 201, y: 480), hold: 2.2)
        sleep(3)
    }

    /// iPad variant of the field-drag QA: same six gestures expressed as
    /// window FRACTIONS so they land on the iPad's wider field.
    func testFieldDragQAiPad() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "AURIE_SEED_HOME": "1",
            "AURIE_BLENDER_DEMO": "ember",
            "AURIE_BLENDER_BODY": "round",
            "AURIE_ENV_GREYBOX": "1",
            "AURIE_ENV_ZONES": "1",
        ]
        app.launch()
        sleep(4)
        let win = app.windows.firstMatch
        func pt(_ fx: CGFloat, _ fy: CGFloat) -> XCUICoordinate {
            win.coordinate(withNormalizedOffset: CGVector(dx: fx, dy: fy))
        }
        func drag(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat),
                  hold: TimeInterval = 0.6) {
            pt(a.0, a.1).press(forDuration: 0.7, thenDragTo: pt(b.0, b.1),
                               withVelocity: .slow, thenHoldForDuration: hold)
            sleep(1)
        }
        drag((0.50, 0.55), (0.50, 0.36))            // near -> far
        drag((0.50, 0.36), (0.50, 0.68))            // far -> near
        drag((0.50, 0.68), (0.60, 0.36))            // nearC -> farR
        drag((0.60, 0.36), (0.34, 0.67))            // farR -> nearL
        drag((0.34, 0.67), (0.62, 0.50), hold: 0.2) // zigzag 1
        drag((0.62, 0.50), (0.42, 0.60), hold: 0.2) // zigzag 2
        drag((0.42, 0.60), (0.50, 0.55), hold: 2.2) // hold mid-depth
        sleep(3)
    }

    /// A long hands-off bubble session, for the probabilistic variants
    /// (hop-reach, miss) to appear on camera.
    func testBubblesLong() {
        let app = launch(body: "round")
        app.buttons["playShelf"].tap(); sleep(1)
        app.buttons["toy_bubble"].tap()
        sleep(55)
        app.buttons["playShelf"].tap(); sleep(1)
        app.buttons["toy_bubble"].tap()
        sleep(2)
    }

    /// Star-delight sweep: on each body, activate the star and bring it to
    /// the creature — the reaction plus clean rest is the cross-body proof.
    func testToysStarTall()    { starSweep("tall") }
    func testToysStarSmall()   { starSweep("small") }
    func testToysStarPear()    { starSweep("pear") }
    func testToysStarBeanbag() { starSweep("beanbag") }
    func testToysStarHeart()   { starSweep("heart") }

    private func starSweep(_ body: String) {
        let app = launch(body: body)
        app.buttons["playShelf"].tap()
        sleep(1)
        app.buttons["toy_star"].tap()
        sleep(2)
        windowDrag(app, from: CGPoint(x: 115, y: 340),
                   to: CGPoint(x: 201, y: 424), hold: 2.2)
        sleep(3)
        app.buttons["playShelf"].tap(); sleep(1)
        app.buttons["toy_star"].tap()             // put it away
        sleep(2)
    }

    /// Interruption: real belly taps timed to land during the first autonomous
    /// behaviours (which arrive at 5–9 s, then every 8–20 s). The log +
    /// recording show the behaviour stopping cleanly and the tap reaction
    /// playing at once.
    func testInterruptAutonomous() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "AURIE_SEED_HOME": "1",
            "AURIE_BLENDER_DEMO": "ember",
            "AURIE_BLENDER_BODY": "round",
            "AURIE_TOUCH_LOG": "1",
            "AURIE_AUTO_LOG": "1",
        ]
        app.launch()
        sleep(3)
        // Tap every ~2 s across both behaviour windows (first at 5–9 s, next
        // 8–20 s later): any behaviour ≥2 s long gets tapped mid-flight.
        for _ in 0 ..< 9 {
            sleep(2)
            tap(app, "round", .belly, settle: 0)
        }
        sleep(6)
    }
}
