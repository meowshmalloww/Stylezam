import XCTest

@MainActor
final class StylezamControlUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLiveScreenControlOpensSystemSharingPicker() throws {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "-stylezam-ui-test-live-screen",
            "-stylezam.onboarding.version",
            "2",
        ])
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "Stylezam did not reach the foreground before the Control Center test."
        )

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let topRight = springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.96, dy: 0.01)
        )
        let lowerRight = springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.96, dy: 0.72)
        )
        topRight.press(forDuration: 0.08, thenDragTo: lowerRight)

        let liveScreenControl = springboard.descendants(matching: .any)
            .matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Live Screen")
            )
            .firstMatch
        if !liveScreenControl.waitForExistence(timeout: 3) {
            let addControls = springboard.buttons["Add Controls"]
            XCTAssertTrue(
                addControls.waitForExistence(timeout: 3),
                "Control Center opened without its Add Controls button.\n\(springboard.debugDescription)"
            )
            addControls.tap()
            let addAControl = springboard.buttons["Add a Control"]
            XCTAssertTrue(
                addAControl.waitForExistence(timeout: 3),
                "Control Center did not enter edit mode.\n\(springboard.debugDescription)"
            )
            addAControl.tap()

            let searchField = springboard.searchFields.firstMatch
            XCTAssertTrue(
                searchField.waitForExistence(timeout: 5),
                "The Add a Control gallery did not expose its search field."
            )
            searchField.tap()
            searchField.typeText("Stylezam")

            let galleryLiveScreenControl = springboard.descendants(matching: .any)
                .matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "Live Screen")
                )
                .firstMatch
            if !galleryLiveScreenControl.waitForExistence(timeout: 5) {
                let stylezamResult = springboard.descendants(matching: .any)
                    .matching(
                        NSPredicate(format: "label CONTAINS[c] %@", "Stylezam")
                    )
                    .firstMatch
                XCTAssertTrue(
                    stylezamResult.waitForExistence(timeout: 3),
                    "Stylezam did not appear in the Add a Control gallery."
                )
                stylezamResult.tap()
            }

            let controlToAdd = springboard.descendants(matching: .any)
                .matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "Live Screen")
                )
                .firstMatch
            XCTAssertTrue(
                controlToAdd.waitForExistence(timeout: 5),
                "The Stylezam gallery entry did not include Live Screen."
            )
            controlToAdd.tap()
        }

        let installedLiveScreenControl = springboard.descendants(matching: .any)
            .matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Live Screen")
            )
            .firstMatch
        XCTAssertTrue(
            installedLiveScreenControl.waitForExistence(timeout: 5),
            "The Stylezam Live Screen control is not visible in Control Center.\n\(springboard.debugDescription)"
        )

        installedLiveScreenControl.tap()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "Tapping the real Live Screen control did not open Stylezam."
        )

        // Apple does not include ScreenCaptureKit in the iOS Simulator SDK. The
        // simulator still exercises the real Control Center tile and OpenIntent
        // app handoff above; only a physical iOS 27 device can exercise the picker.
        #if !targetEnvironment(simulator)
        let pickerText = NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
            "Share Entire Screen",
            "Choose What to Share",
            "Share Your Screen"
        )
        let appPicker = app.descendants(matching: .any).matching(pickerText).firstMatch
        let systemPicker = springboard.descendants(matching: .any).matching(pickerText).firstMatch
        XCTAssertTrue(
            appPicker.waitForExistence(timeout: 10) || systemPicker.waitForExistence(timeout: 2),
            "Stylezam opened, but Apple's Live Screen sharing picker did not appear."
        )
        #endif
    }
}
