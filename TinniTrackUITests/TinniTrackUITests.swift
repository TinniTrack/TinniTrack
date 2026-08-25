//
//  TinniTrackUITests.swift
//  TinniTrackUITests
//
//  Created by Basil Shevtsov on 12/4/25.
//

import XCTest

final class TinniTrackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSignupDraftRelaunchRequiresPasswordAndRestoresProfileFields() throws {
        let app = makeApp()
        app.launchEnvironment["UITEST_SEED_SIGNUP_DRAFT"] = "1"
        app.launch()

        app.buttons["Sign Up"].tap()
        XCTAssertTrue(app.textFields["signup_email_field"].waitForExistence(timeout: 2))

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "UITEST_CLEAR_SIGNUP_DRAFT")
        app.launchEnvironment.removeValue(forKey: "UITEST_SEED_SIGNUP_DRAFT")
        app.launch()
        app.buttons["Sign Up"].tap()

        let emailField = app.textFields["signup_email_field"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 2))
        XCTAssertEqual(emailField.value as? String, "draft@example.com")

        let continueButton = app.buttons["signup_continue_button"]
        XCTAssertFalse(continueButton.isEnabled)

        let passwordField = app.secureTextFields["signup_password_field"]
        passwordField.tap()
        passwordField.typeText("replacement-password")
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()

        let firstNameField = app.textFields["signup_first_name_field"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 2))
        XCTAssertEqual(firstNameField.value as? String, "Draft")
        XCTAssertEqual(app.textFields["signup_last_name_field"].value as? String, "Participant")
    }

    @MainActor
    func testSignupProfileStepAndDOBToolbarDoneDismissesKeyboard() throws {
        let app = makeApp()
        app.launch()

        app.buttons["Sign Up"].tap()

        let emailField = app.textFields["signup_email_field"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 2))
        emailField.tap()
        emailField.typeText("signup@example.com")
        emailField.typeText("\n")

        let passwordField = app.secureTextFields["signup_password_field"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 2))
        passwordField.tap()
        passwordField.typeText("password123")
        app.buttons["signup_continue_button"].tap()

        let firstNameField = app.textFields["signup_first_name_field"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 2))
        firstNameField.tap()
        firstNameField.typeText("Taylor")
        firstNameField.typeText("\n")

        let lastNameField = app.textFields["signup_last_name_field"]
        lastNameField.typeText("Rivers")
        lastNameField.typeText("\n")

        let monthField = app.textFields["signup_birth_month_field"]
        XCTAssertTrue(monthField.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["signup_keyboard_done_button"].waitForExistence(timeout: 2))
        app.buttons["signup_keyboard_done_button"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
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

        firstNameField.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
        app.buttons["profile_cancel_edit_button"].tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 2))
        XCTAssertFalse(app.textFields["profile_first_name_field"].exists)
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
    func testStudyNo1DashboardConsentFlowUsesNativePushAndSwipeBack() throws {
        let app = makeAuthenticatedStudyApp()
        app.launch()

        let studyCard = app.buttons["study_card_study-no-1"]
        XCTAssertTrue(
            studyCard.waitForExistence(timeout: 15),
            "Timed out waiting for the hosted development study catalog to show Study No. 1."
        )
        studyCard.tap()

        XCTAssertTrue(app.navigationBars["Study Details"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.scrollViews["study_consent_landing"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Loudness Match Study"].exists)
        let reviewButton = app.buttons["study_consent_review_button"]
        XCTAssertTrue(reviewButton.exists)
        XCTAssertFalse(app.staticTexts["Inclusion Criteria"].exists)
        XCTAssertFalse(app.staticTexts["Exclusion Criteria"].exists)

        reviewButton.tap()

        XCTAssertTrue(app.staticTexts["Informed Consent"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Step 1 of 2"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["Key Info"].exists)
        XCTAssertFalse(app.buttons["What You'll Do"].exists)
        XCTAssertFalse(app.buttons["study_consent_signature_button"].isEnabled)

        scrollConsentToBottom(in: app)
        app.buttons["study_consent_decline_button"].tap()
        XCTAssertTrue(app.alerts["Consent Required"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.alerts["Consent Required"].staticTexts["If you do not agree to these terms, you cannot participate in this study."].exists)
        app.alerts["Consent Required"].buttons["Exit"].tap()
        XCTAssertTrue(app.navigationBars["Study Details"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.scrollViews["study_consent_landing"].waitForExistence(timeout: 2))

        app.buttons["study_consent_review_button"].tap()
        XCTAssertTrue(app.staticTexts["Informed Consent"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["study_consent_signature_button"].isEnabled)

        scrollConsentToBottom(in: app)
        app.buttons["study_consent_decline_button"].tap()
        XCTAssertTrue(app.alerts["Consent Required"].waitForExistence(timeout: 2))
        app.alerts["Consent Required"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Informed Consent"].waitForExistence(timeout: 2))

        let signatureButton = app.buttons["study_consent_signature_button"]
        XCTAssertTrue(signatureButton.waitForExistence(timeout: 2))
        XCTAssertTrue(signatureButton.isEnabled)
        signatureButton.tap()

        XCTAssertTrue(app.staticTexts["Step 2 of 2"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Sign Consent"].exists)
        XCTAssertTrue(app.staticTexts["study_consent_attestation_text"].exists)
        XCTAssertTrue(app.staticTexts["I am 18 or older, understand participation is voluntary, and agree to participate."].exists)
        XCTAssertFalse(app.buttons["I am 18 or older, understand participation is voluntary, and agree to participate."].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        let firstNameField = app.textFields["study_consent_first_name_field"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 2))
        let lastNameField = app.textFields["study_consent_last_name_field"]
        XCTAssertTrue(lastNameField.exists)
        firstNameField.tap()
        firstNameField.typeText("Alex")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))

        app.staticTexts["study_consent_attestation_text"].tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 2))

        firstNameField.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
        firstNameField.typeText("\n")
        lastNameField.typeText("River")
        lastNameField.typeText("\n")
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 2))

        firstNameField.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
        lastNameField.tap()
        lastNameField.typeText("s")
        XCTAssertTrue(keyboard.exists)

        let drawSignatureButton = app.buttons["study_consent_draw_signature_button"]
        XCTAssertTrue(drawSignatureButton.waitForExistence(timeout: 2))
        XCTAssertTrue(drawSignatureButton.label.contains("Tap to draw your signature."))
        drawSignatureButton.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.buttons["study_signature_clear_button"].waitForExistence(timeout: 2))
        let saveSignatureButton = app.buttons["study_signature_save_button"]
        XCTAssertTrue(saveSignatureButton.exists)
        XCTAssertFalse(saveSignatureButton.isEnabled)
        drawSignature(in: app)
        XCTAssertTrue(saveSignatureButton.isEnabled)
        saveSignatureButton.tap()
        XCTAssertTrue(app.navigationBars["Sign Consent"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.images["study_signature_preview_image"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Sign and Enroll"].isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Signed today,")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["A signed consent copy will be saved securely."].exists)

        swipeBack(in: app)
        XCTAssertTrue(app.navigationBars["Informed Consent"].waitForExistence(timeout: 2))

        swipeBack(in: app)
        XCTAssertTrue(app.navigationBars["Study Details"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.scrollViews["study_consent_landing"].waitForExistence(timeout: 2))

        swipeBack(in: app)
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testStudyNo1EnrollmentSuccessRoutesToOrientationAndRefreshesDashboard() throws {
        let app = makeAuthenticatedStudyApp()
        app.launchEnvironment["UITEST_MOCK_STUDY_ENROLLMENT_SUCCESS"] = "1"
        app.launch()

        let studyCard = app.buttons["study_card_study-no-1"]
        XCTAssertTrue(studyCard.waitForExistence(timeout: 5))
        studyCard.tap()

        XCTAssertTrue(app.navigationBars["Study Details"].waitForExistence(timeout: 3))
        app.buttons["study_consent_review_button"].tap()
        XCTAssertTrue(app.staticTexts["Informed Consent"].waitForExistence(timeout: 3))

        scrollConsentToBottom(in: app)
        let signatureButton = app.buttons["study_consent_signature_button"]
        XCTAssertTrue(signatureButton.waitForExistence(timeout: 2))
        XCTAssertTrue(signatureButton.isEnabled)
        signatureButton.tap()

        XCTAssertTrue(app.navigationBars["Sign Consent"].waitForExistence(timeout: 3))
        let firstNameField = app.textFields["study_consent_first_name_field"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 2))
        firstNameField.tap()
        firstNameField.typeText("Alex")
        firstNameField.typeText("\n")

        let lastNameField = app.textFields["study_consent_last_name_field"]
        XCTAssertTrue(lastNameField.waitForExistence(timeout: 2))
        lastNameField.typeText("Rivers")
        lastNameField.typeText("\n")

        let drawSignatureButton = app.buttons["study_consent_draw_signature_button"]
        XCTAssertTrue(drawSignatureButton.waitForExistence(timeout: 2))
        drawSignatureButton.tap()
        let saveSignatureButton = app.buttons["study_signature_save_button"]
        XCTAssertTrue(saveSignatureButton.waitForExistence(timeout: 2))
        drawSignature(in: app)
        XCTAssertTrue(saveSignatureButton.isEnabled)
        saveSignatureButton.tap()

        let signAndEnrollButton = app.buttons["Sign and Enroll"]
        let signatureScroll = app.scrollViews["study_consent_signature"]
        for _ in 0..<3 where !signAndEnrollButton.isHittable {
            signatureScroll.swipeUp()
        }
        XCTAssertTrue(signAndEnrollButton.waitForExistence(timeout: 2))
        XCTAssertTrue(signAndEnrollButton.isEnabled)
        signAndEnrollButton.tap()

        XCTAssertTrue(app.buttons["Begin Orientation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Welcome. Thanks for choosing to participate in this study!"].exists)
        XCTAssertFalse(app.navigationBars["Sign Consent"].exists)
        XCTAssertFalse(app.navigationBars["Informed Consent"].exists)
        XCTAssertFalse(app.navigationBars["Study Details"].exists)

        swipeBack(in: app)
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["ENROLLED"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Go to Tasks"].exists)
    }

    @MainActor
    func testStudyConsentEmailLinksExposeCopyMenu() throws {
        let app = makeAuthenticatedStudyApp()
        app.launch()

        let studyCard = app.buttons["study_card_study-no-1"]
        XCTAssertTrue(
            studyCard.waitForExistence(timeout: 15),
            "Timed out waiting for the hosted development study catalog to show Study No. 1."
        )
        studyCard.tap()

        XCTAssertTrue(app.navigationBars["Study Details"].waitForExistence(timeout: 3))
        app.buttons["study_consent_review_button"].tap()
        XCTAssertTrue(app.staticTexts["Informed Consent"].waitForExistence(timeout: 3))

        assertConsentEmailCopyMenu(
            "study_consent_email_armstrtr_whitman_edu_eligibility_questions",
            in: app
        )
        assertConsentEmailCopyMenu(
            "study_consent_email_armstrtr_whitman_edu",
            in: app
        )
        assertConsentEmailCopyMenu(
            "study_consent_email_irb_whitman_edu",
            in: app
        )
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

    private func makeAuthenticatedStudyApp() -> XCUIApplication {
        let app = makeAuthenticatedProfileApp()
        app.launchEnvironment["SUPABASE_URL"] = "https://vhgbjeeoqmbqvxtstpcq.supabase.co"
        app.launchEnvironment["SUPABASE_ANON_KEY"] = "sb_publishable_tzvCA-Go43bESrFD67sr8Q_8bdat__Q"
        app.launchEnvironment["SUPABASE_ENVIRONMENT"] = "Development"
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

    @MainActor
    private func swipeBack(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func scrollConsentToBottom(in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 2))

        for _ in 0..<10 where !app.buttons["study_consent_signature_button"].isEnabled {
            scrollView.swipeUp()
        }
    }

    @MainActor
    private func assertConsentEmailCopyMenu(_ identifier: String, in app: XCUIApplication) {
        let emailButton = app.buttons[identifier]
        let scrollView = app.scrollViews["study_consent_reader_scroll"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 2))

        for _ in 0..<10 where !emailButton.isHittable {
            scrollView.swipeUp()
        }

        XCTAssertTrue(emailButton.waitForExistence(timeout: 2))
        XCTAssertTrue(emailButton.isHittable)
        emailButton.press(forDuration: 1.1)

        let copyEmailButton = app.buttons["Copy Email"].firstMatch
        XCTAssertTrue(copyEmailButton.waitForExistence(timeout: 2))
        copyEmailButton.tap()
        XCTAssertTrue(copyEmailButton.waitForNonExistence(timeout: 2))
    }

    @MainActor
    private func drawSignature(in app: XCUIApplication) {
        let drawingSurface = app.otherElements["study_signature_drawing_surface"]
        XCTAssertTrue(drawingSurface.waitForExistence(timeout: 2))

        let start = drawingSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.58))
        let end = drawingSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
