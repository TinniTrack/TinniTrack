//
//  TinniTrackUITests.swift
//  TinniTrackUITests
//
//  Created by Basil Shevtsov on 12/4/25.
//

import XCTest

final class TinniTrackUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testSignupDraftResumesOnStepTwoAfterRelaunch() throws {
        let app = makeApp()
        app.launchEnvironment["UITEST_SEED_SIGNUP_DRAFT_STEP_TWO"] = "1"
        app.launch()

        app.buttons["Sign Up"].tap()
        XCTAssertTrue(app.textFields["signup_first_name_field"].waitForExistence(timeout: 2))

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "UITEST_CLEAR_SIGNUP_DRAFT")
        app.launchEnvironment.removeValue(forKey: "UITEST_SEED_SIGNUP_DRAFT_STEP_TWO")
        app.launch()
        app.buttons["Sign Up"].tap()

        XCTAssertTrue(app.textFields["signup_first_name_field"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testEmailVerificationWaitingScreenBlocksDashboard() throws {
        let app = makeApp()
        app.launchEnvironment["UITEST_PENDING_VERIFICATION_EMAIL"] = "waiting@example.com"
        app.launch()

        XCTAssertTrue(app.staticTexts["email_verification_title"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["HOME"].exists)
    }

    @MainActor
    func testEmailVerificationWaitingScreenResumesAfterRelaunch() throws {
        let app = makeApp()
        app.launchEnvironment["UITEST_PENDING_VERIFICATION_EMAIL"] = "resume@example.com"
        app.launch()

        XCTAssertTrue(app.staticTexts["email_verification_title"].waitForExistence(timeout: 2))

        app.terminate()
        app.launch()

        XCTAssertTrue(app.staticTexts["email_verification_title"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testEmailVerificationCheckTransitionsWhenSessionBecomesAvailable() throws {
        let app = makeApp()
        app.launchEnvironment["UITEST_PENDING_VERIFICATION_EMAIL"] = "verify@example.com"
        app.launchEnvironment["UITEST_NOOP_VERIFY_AFTER_SESSION_CHECKS"] = "2"
        app.launch()

        let verifyTitle = app.staticTexts["email_verification_title"]
        XCTAssertTrue(verifyTitle.waitForExistence(timeout: 2))

        app.buttons["email_verification_check_button"].tap()

        XCTAssertTrue(app.navigationBars["Onboarding"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testProfileEditingRevealsEditableFieldsAndHidesResearchMetadata() throws {
        let app = makeAuthenticatedProfileApp()
        app.launch()

        openProfileTab(in: app)

        XCTAssertTrue(app.staticTexts["Name"].exists)
        XCTAssertTrue(app.staticTexts["Taylor Rivers"].exists)
        XCTAssertTrue(app.staticTexts["Login Email"].exists)
        XCTAssertTrue(app.staticTexts["p@e.co"].exists)
        XCTAssertTrue(app.staticTexts["Date of Birth"].exists)
        XCTAssertTrue(app.staticTexts["Age"].exists)
        XCTAssertFalse(app.textFields["profile_first_name_field"].exists)
        XCTAssertFalse(app.staticTexts["Participant ID"].exists)
        XCTAssertFalse(app.staticTexts["User ID"].exists)
        XCTAssertFalse(app.staticTexts["Time Zone"].exists)
        XCTAssertFalse(app.staticTexts["Created"].exists)

        let editButton = app.buttons["profile_edit_info_button"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 2))
        editButton.tap()

        let firstNameField = app.textFields["profile_first_name_field"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["profile_last_name_field"].exists)
        XCTAssertTrue(app.datePickers["profile_date_of_birth_picker"].exists)
    }

    @MainActor
    func testProfileDeleteAccountShowsConfirmationAndRoutesToLogin() throws {
        let app = makeAuthenticatedProfileApp()
        app.launch()

        openProfileTab(in: app)

        let deleteButton = app.buttons["profile_delete_account_button"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        XCTAssertTrue(confirmation.staticTexts["Delete Account?"].exists)
        XCTAssertTrue(confirmation.staticTexts["This permanently deletes your TinniTrack account and study data."].exists)
        confirmation.buttons["profile_confirm_delete_account_button"].firstMatch.tap()

        XCTAssertTrue(app.buttons["Sign Up"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_CLEAR_PENDING_VERIFICATION"] = "1"
        app.launchEnvironment["UITEST_CLEAR_SIGNUP_DRAFT"] = "1"
        return app
    }

    private func makeAuthenticatedProfileApp() -> XCUIApplication {
        let app = makeApp()
        app.launchEnvironment["UITEST_READY_PROFILE"] = "1"
        app.launchEnvironment["UITEST_PROFILE_EMAIL"] = "p@e.co"
        return app
    }

    @MainActor
    private func openProfileTab(in app: XCUIApplication) {
        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 3))
        profileTab.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        if let currentValue = field.value as? String,
           currentValue != text,
           !currentValue.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }
        field.typeText(text)
    }
}
