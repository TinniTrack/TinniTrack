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
        app.launch()

        app.buttons["Sign Up"].tap()

        let emailField = app.textFields["signup_email_field"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 2))
        emailField.tap()
        emailField.typeText("draft@example.com")

        let passwordField = app.secureTextFields["signup_password_field"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 2))
        passwordField.tap()
        passwordField.typeText("password123")

        let continueButton = app.buttons["signup_continue_button"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 2))
        continueButton.tap()

        XCTAssertTrue(app.textFields["signup_first_name_field"].waitForExistence(timeout: 2))

        app.terminate()
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
}
