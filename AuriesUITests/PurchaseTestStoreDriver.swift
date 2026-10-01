import XCTest

/// Drives the RevenueCat **Test Store** purchase alerts so the A-K matrix in
/// `PurchaseQA` can run end to end.
///
/// The Test Store deliberately presents an interactive `UIAlertController`
/// ("Test Store Purchase") with "Test valid purchase" / "Test failed
/// purchase" / "Cancel", so a purchase CANNOT complete headlessly. This test
/// supplies the taps in the order `PurchaseQA.run` issues them; the results
/// themselves are asserted in-app and printed as AURIE_PQA lines.
///
/// QA tooling — remove with `PurchaseQA` before App Store submission.
final class PurchaseTestStoreDriver: XCTestCase {

    private enum Tap: String {
        case valid  = "Test valid purchase"
        case fail   = "Test failed purchase"
        case cancel = "Cancel"
    }

    /// The exact order `PurchaseQA.run` performs purchases:
    /// D, E, F, then G twice, then H (cancel), then I (failure).
    private let script: [Tap] = [
        .valid,   // D  buy 5
        .valid,   // E  buy 10
        .valid,   // F  buy 20
        .valid,   // G1 buy 5
        .valid,   // G2 buy 5
        .cancel,  // H  cancellation
        .fail,    // I  simulated failure
    ]

    func testDriveTestStoreMatrix() {
        let app = XCUIApplication()
        app.launchEnvironment["AURIE_PURCHASE_QA"] = "1"
        app.launchEnvironment["AURIE_TUTORIAL_AUTOSKIP"] = "2"
        app.launch()

        for (index, tap) in script.enumerated() {
            let button = app.alerts.buttons[tap.rawValue]
            XCTAssertTrue(button.waitForExistence(timeout: 60),
                          "Test Store alert \(index + 1) (\(tap.rawValue)) never appeared")
            button.tap()
        }

        // Let the in-app matrix finish reconciliation and print its summary.
        Thread.sleep(forTimeInterval: 12)

        // J — kill and relaunch WITHOUT reinstalling, so the data container
        // survives. The second launch only reads the persisted wallet and
        // runs the normal launch reconciliation, which must not re-credit.
        app.terminate()
        app.launchEnvironment["AURIE_PURCHASE_QA"] = "0"
        app.launchEnvironment["AURIE_PURCHASE_QA_VERIFY"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 12)
    }
}
