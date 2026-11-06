import XCTest

final class SolveFlowTests: XCTestCase {
    @MainActor
    func testTimedSolveAndPenaltySurviveRelaunch() {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333", "-timer.startDelayTenths", "2"]
        app.launch()

        let scramble = app.staticTexts["timer.scramble"]
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        let originalScramble = scramble.label
        XCTAssertFalse(originalScramble.isEmpty)

        let timer = app.descendants(matching: .any)["timer.readout"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        let center = timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.5)
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        center.tap()

        let dnf = app.buttons["timer.penalty.dnf"]
        XCTAssertTrue(dnf.waitForExistence(timeout: 5))
        dnf.tap()
        let markedDNF = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "DNF"), object: timer)
        XCTAssertEqual(XCTWaiter.wait(for: [markedDNF], timeout: 5), .completed)

        app.terminate()
        app.launch()

        let results = app.tabBars.buttons["Results"]
        XCTAssertTrue(results.waitForExistence(timeout: 20))
        results.tap()
        let solve = app.descendants(matching: .any).matching(identifier: "solve-row-1").firstMatch
        XCTAssertTrue(solve.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["solve-row-2"].exists)
        solve.tap()

        let time = app.descendants(matching: .any)["solve-detail.time"]
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        XCTAssertEqual(time.value as? String, "DNF")
        let savedScramble = app.staticTexts["solve-detail.scramble"]
        XCTAssertTrue(savedScramble.waitForExistence(timeout: 5))
        XCTAssertEqual(savedScramble.label, originalScramble)
    }
}
