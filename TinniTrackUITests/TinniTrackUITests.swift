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
        let app = makeMockedStudyApp(scenario: .success)
        app.launch()

        let studyCard = app.buttons["study_card_study-no-1"]
        XCTAssertTrue(studyCard.waitForExistence(timeout: 5))
        studyCard.tap()

        XCTAssertTrue(app.navigationBars["Study Details"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.scrollViews["study_consent_landing"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Loudness Match Study"].exists)
        let reviewButton = app.buttons["study_consent_review_button"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.staticTexts["Consent reviewed. You can continue."].exists)
        XCTAssertTrue(waitForEnabledState(true, of: signatureButton))

        swipeBack(in: app)
        XCTAssertTrue(app.navigationBars["Study Details"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.scrollViews["study_consent_landing"].waitForExistence(timeout: 2))

        swipeBack(in: app)
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testStudyConsentBackNavigationPreservesReviewAndDraftUntilFreshReentry() throws {
        let app = makeMockedStudyApp(scenario: .success)
        app.launch()

        openStudyConsentReader(in: app)
        continueToStudyConsentSignature(in: app)
        completeStudyConsentSignature(in: app, firstName: "Alex", lastName: "Rivers")
        XCTAssertTrue(signAndEnrollButton(in: app).isEnabled)

        let nativeBackButton = app.navigationBars["Sign Consent"].buttons.firstMatch
        XCTAssertTrue(nativeBackButton.waitForExistence(timeout: 2))
        nativeBackButton.tap()
        XCTAssertTrue(app.navigationBars["Informed Consent"].waitForExistence(timeout: 2))

        let signatureButton = app.buttons["study_consent_signature_button"]
        XCTAssertTrue(app.staticTexts["Consent reviewed. You can continue."].exists)
        XCTAssertTrue(waitForEnabledState(true, of: signatureButton))
        signatureButton.tap()
        XCTAssertTrue(app.navigationBars["Sign Consent"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.textFields["study_consent_first_name_field"].value as? String, "Alex")
        XCTAssertEqual(app.textFields["study_consent_last_name_field"].value as? String, "Rivers")
        XCTAssertTrue(app.images["study_signature_preview_image"].waitForExistence(timeout: 2))

        swipeBack(in: app)
        XCTAssertTrue(app.navigationBars["Informed Consent"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Consent reviewed. You can continue."].exists)
        XCTAssertTrue(waitForEnabledState(true, of: signatureButton))

        swipeBack(in: app)
        assertStudyConsentLanding(in: app)

        openStudyConsentReaderFromLanding(in: app)
        XCTAssertTrue(signatureButton.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Scroll to the bottom of the consent form to continue."].exists)
        XCTAssertTrue(waitForEnabledState(false, of: signatureButton))
        continueToStudyConsentSignature(in: app)

        XCTAssertEqual(app.textFields["study_consent_first_name_field"].value as? String, "Alex")
        XCTAssertEqual(app.textFields["study_consent_last_name_field"].value as? String, "Rivers")
        XCTAssertTrue(app.images["study_signature_preview_image"].waitForExistence(timeout: 2))
        XCTAssertTrue(signAndEnrollButton(in: app).isEnabled)
    }

    @MainActor
    func testStudyConsentDeclineFromReaderAndSignatureReturnsToStudyDetails() throws {
        let app = makeMockedStudyApp(scenario: .success)
        app.launch()

        openStudyConsentReader(in: app)
        let readerDeclineButton = app.buttons["study_consent_decline_button"]
        XCTAssertTrue(readerDeclineButton.waitForExistence(timeout: 2))
        readerDeclineButton.tap()

        let readerAlert = app.alerts["Consent Required"]
        XCTAssertTrue(readerAlert.waitForExistence(timeout: 2))
        readerAlert.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Informed Consent"].waitForExistence(timeout: 2))

        readerDeclineButton.tap()
        XCTAssertTrue(readerAlert.waitForExistence(timeout: 2))
        readerAlert.buttons["Exit"].tap()
        assertStudyConsentLanding(in: app)

        openStudyConsentReaderFromLanding(in: app)
        continueToStudyConsentSignature(in: app)

        let signatureDeclineButton = app.buttons["study_consent_signature_decline_button"]
        let signatureScroll = app.scrollViews["study_consent_signature"]
        for _ in 0..<4 where !signatureDeclineButton.isHittable {
            signatureScroll.swipeUp()
        }
        XCTAssertTrue(signatureDeclineButton.isHittable)
        signatureDeclineButton.tap()

        let signatureAlert = app.alerts["Consent Required"]
        XCTAssertTrue(signatureAlert.waitForExistence(timeout: 2))
        signatureAlert.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Sign Consent"].waitForExistence(timeout: 2))

        signatureDeclineButton.tap()
        XCTAssertTrue(signatureAlert.waitForExistence(timeout: 2))
        signatureAlert.buttons["Exit"].tap()
        assertStudyConsentLanding(in: app)
    }

    @MainActor
    func testStudyConsentFailOnceStaysOnSignatureAndRetrySucceeds() throws {
        let app = makeMockedStudyApp(scenario: .failOnce)
        app.launch()

        openStudyConsentReader(in: app)
        continueToStudyConsentSignature(in: app)
        completeStudyConsentSignature(in: app, firstName: "Alex", lastName: "Rivers")
        makeSignAndEnrollButtonHittable(in: app).tap()

        let failureAlert = app.alerts["Unable to Finish Enrollment"]
        XCTAssertTrue(failureAlert.waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Sign Consent"].exists)
        failureAlert.buttons["Try Again"].tap()

        XCTAssertTrue(failureAlert.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.navigationBars["Sign Consent"].exists)
        XCTAssertEqual(app.textFields["study_consent_first_name_field"].value as? String, "Alex")
        XCTAssertEqual(app.textFields["study_consent_last_name_field"].value as? String, "Rivers")
        XCTAssertTrue(app.images["study_signature_preview_image"].exists)

        let retryButton = makeSignAndEnrollButtonHittable(in: app)
        XCTAssertTrue(waitForEnabledState(true, of: retryButton))
        retryButton.tap()
        assertStudyTaskDashboardDestination(in: app)
    }

    @MainActor
    func testStudyConsentPendingRecoveryRoutesToTaskDashboard() throws {
        let app = makeMockedStudyApp(scenario: .pendingRecovery)
        app.launch()

        openStudyDetails(in: app)
        let resumeButton = app.buttons["study_consent_resume_enrollment_button"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["study_consent_review_button"].exists)
        resumeButton.tap()

        assertStudyTaskDashboardDestination(in: app)
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

        XCTAssertTrue(app.buttons["study_begin_orientation_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Welcome to Study No. 1"].exists)
        XCTAssertFalse(app.navigationBars["Sign Consent"].exists)
        XCTAssertFalse(app.navigationBars["Informed Consent"].exists)
        XCTAssertTrue(app.navigationBars["Loudness Matching Study"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Study Details"].exists)

        swipeBack(in: app)
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["ENROLLED"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Go to Tasks"].exists)
    }

    @MainActor
    func testStudyNo1OrientationBeginsOnHearingSetup() throws {
        let app = launchEnrolledStudyOrientation()

        XCTAssertTrue(app.otherElements["study_onboarding_hearing_test_step"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Take an Apple Hearing Test"].exists)
        XCTAssertFalse(app.otherElements["study_onboarding_welcome_step"].exists)
    }

    @MainActor
    func testStudyNo1OrientationForwardNavigationSupportsNativeEdgeSwipe() throws {
        let app = launchEnrolledStudyOrientation(audioPreflightReady: true)
        let primaryButton = app.buttons["study_onboarding_primary_button"]

        XCTAssertTrue(primaryButton.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        XCTAssertEqual(primaryButton.label, "Continue")
        primaryButton.tap()

        let introTitle = app.staticTexts["Test Your Tinnitus"]
        XCTAssertTrue(introTitle.waitForExistence(timeout: 3))
        XCTAssertEqual(primaryButton.label, "Get Started")
        primaryButton.tap()

        let airPodsStep = app.descendants(matching: .any)["loudness_airpods_step"]
        XCTAssertTrue(airPodsStep.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["AirPods Pro 2 confirmed"].exists)

        swipeBack(in: app)

        XCTAssertTrue(introTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(airPodsStep.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testNativeOrientationThresholdContinuesInOrientationChrome() throws {
        let app = launchEnrolledStudyOrientation(audioPreflightReady: true)
        let primaryButton = app.buttons["study_onboarding_primary_button"]

        XCTAssertTrue(primaryButton.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        primaryButton.tap()

        XCTAssertTrue(app.staticTexts["Test Your Tinnitus"].waitForExistence(timeout: 3))
        primaryButton.tap()

        let airPodsStep = app.descendants(matching: .any)["loudness_airpods_step"]
        XCTAssertTrue(airPodsStep.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        primaryButton.tap()

        XCTAssertTrue(app.otherElements["loudness_noise_gate_step"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        primaryButton.tap()

        XCTAssertTrue(
            app.staticTexts[
                "Adjust the position and depth of each AirPod until the fit is snug but comfortable."
            ].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        primaryButton.tap()

        XCTAssertTrue(
            app.staticTexts[
                "Please use the volume buttons on your iPhone to set the volume to maximum."
            ].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        XCTAssertEqual(primaryButton.label, "Start Test")
        primaryButton.tap()

        XCTAssertTrue(
            app.otherElements["study_onboarding_threshold_test_step"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.navigationBars["Orientation"].exists)
        XCTAssertTrue(app.buttons["study_onboarding_close_button"].exists)

        let beginRightEarButton = app.buttons["study_threshold_begin_right_ear_button"]
        XCTAssertTrue(beginRightEarButton.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts[
                "You’ll hear a series of tones through one AirPod. Tap as soon as you hear a tone."
            ].exists
        )
        XCTAssertFalse(app.staticTexts["Quiet tones are expected"].exists)
        beginRightEarButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["study_threshold_heard_button"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Listen carefully"].exists)
        XCTAssertTrue(app.staticTexts["Tap the button whenever you hear a tone"].exists)
        XCTAssertTrue(app.staticTexts["Don’t tap during silence"].exists)
        XCTAssertFalse(app.staticTexts["Keep your phone still and your AirPods in place."].exists)
        XCTAssertFalse(app.staticTexts["0 responses recorded"].exists)
        XCTAssertTrue(app.navigationBars["Orientation"].exists)
        XCTAssertTrue(app.buttons["study_onboarding_close_button"].exists)
    }

    @MainActor
    func testRecurringLoudnessPreflightSupportsNativeEdgeSwipe() throws {
        let app = makeAuthenticatedStudyApp()
        app.launchEnvironment["UITEST_MOCK_AUDIO_PREFLIGHT_READY"] = "1"
        app.launchEnvironment["UITEST_MOCK_RECURRING_LOUDNESS_TASK"] = "1"
        app.launch()

        let studyCard = app.buttons["study_card_study-no-1"]
        XCTAssertTrue(studyCard.waitForExistence(timeout: 5))
        studyCard.tap()

        let startTaskButton = app.buttons["study_start_loudness_task_button"]
        XCTAssertTrue(startTaskButton.waitForExistence(timeout: 5))
        XCTAssertTrue(startTaskButton.isEnabled)
        startTaskButton.tap()

        let introTitle = app.staticTexts["Test Your Tinnitus"]
        let primaryButton = app.buttons["loudness_modal_primary_button"]
        XCTAssertTrue(introTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 3))
        XCTAssertEqual(primaryButton.label, "Get Started")
        XCTAssertFalse(app.alerts["Unable to Continue"].exists)

        app.buttons["loudness_modal_close_button"].tap()
        let exitConfirmation = app.alerts["Exit this task?"]
        XCTAssertTrue(exitConfirmation.waitForExistence(timeout: 2))
        exitConfirmation.buttons["Keep Going"].tap()
        XCTAssertTrue(introTitle.waitForExistence(timeout: 2))

        primaryButton.tap()

        let airPodsStep = app.descendants(matching: .any)["loudness_airpods_step"]
        XCTAssertTrue(airPodsStep.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        primaryButton.tap()

        let quietRoomStep = app.otherElements["loudness_noise_gate_step"]
        XCTAssertTrue(quietRoomStep.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        primaryButton.tap()

        let fitTitle = app.staticTexts[
            "Adjust the position and depth of each AirPod until the fit is snug but comfortable."
        ]
        XCTAssertTrue(fitTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        primaryButton.tap()

        let maxVolumeTitle = app.staticTexts[
            "Please use the volume buttons on your iPhone to set the volume to maximum."
        ]
        XCTAssertTrue(maxVolumeTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))

        swipeBack(in: app)

        XCTAssertTrue(fitTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(maxVolumeTitle.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testRecurringActiveTestContinuesInLoudnessMatchChrome() throws {
        let app = makeAuthenticatedStudyApp()
        app.launchEnvironment["UITEST_MOCK_AUDIO_PREFLIGHT_READY"] = "1"
        app.launchEnvironment["UITEST_MOCK_RECURRING_LOUDNESS_TASK"] = "1"
        app.launch()

        let studyCard = app.buttons["study_card_study-no-1"]
        XCTAssertTrue(studyCard.waitForExistence(timeout: 5))
        studyCard.tap()

        let startTaskButton = app.buttons["study_start_loudness_task_button"]
        XCTAssertTrue(startTaskButton.waitForExistence(timeout: 5))
        XCTAssertTrue(startTaskButton.isEnabled)
        startTaskButton.tap()

        let primaryButton = app.buttons["loudness_modal_primary_button"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 3))
        XCTAssertEqual(primaryButton.label, "Get Started")
        primaryButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["loudness_airpods_step"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        primaryButton.tap()

        XCTAssertTrue(app.otherElements["loudness_noise_gate_step"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        primaryButton.tap()

        XCTAssertTrue(
            app.staticTexts[
                "Adjust the position and depth of each AirPod until the fit is snug but comfortable."
            ].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        primaryButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["loudness_volume_gate_step"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        XCTAssertEqual(primaryButton.label, "Continue")
        primaryButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["loudness_tinnitus_location_step"]
                .waitForExistence(timeout: 3)
        )
        let leftLateralityButton = app.buttons["Left"]
        XCTAssertTrue(leftLateralityButton.waitForExistence(timeout: 3))
        leftLateralityButton.tap()

        XCTAssertTrue(waitForEnabledState(true, of: primaryButton, timeout: 3))
        XCTAssertEqual(primaryButton.label, "Start Test")
        primaryButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["loudness_active_test_step"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.navigationBars["Loudness Match"].exists)
        XCTAssertTrue(app.buttons["loudness_modal_close_button"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["loudness_play_button"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["loudness_louder_button"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["loudness_softer_button"].exists)
        XCTAssertTrue(app.buttons["Play Tone"].exists)
        XCTAssertEqual(primaryButton.label, "Same loudness")
    }

    @MainActor
    func testStudyNo1OrientationConfirmsExit() throws {
        let app = launchEnrolledStudyOrientation()
        let closeOrientationButton = app.buttons["study_onboarding_close_button"]
        XCTAssertTrue(closeOrientationButton.exists)
        closeOrientationButton.tap()

        let exitAlert = app.alerts["Exit Orientation?"]
        XCTAssertTrue(exitAlert.waitForExistence(timeout: 2))
        XCTAssertTrue(exitAlert.staticTexts["Your current Study No. 1 onboarding progress will be discarded."].exists)
        exitAlert.buttons["Exit Orientation"].tap()
        let beginOrientationButton = app.buttons["study_begin_orientation_button"]
        XCTAssertTrue(beginOrientationButton.waitForExistence(timeout: 3))

        beginOrientationButton.tap()
        XCTAssertTrue(app.otherElements["study_onboarding_hearing_test_step"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["study_onboarding_welcome_step"].exists)
        XCTAssertFalse(app.otherElements["study_onboarding_loudness_intro_step"].exists)
    }

    @MainActor
    func testStudyNo1EnrollmentSuccessRoutesAfterSignatureFirstAndNameEdits() throws {
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
        let signatureStepButton = app.buttons["study_consent_signature_button"]
        XCTAssertTrue(signatureStepButton.waitForExistence(timeout: 2))
        XCTAssertTrue(signatureStepButton.isEnabled)
        signatureStepButton.tap()

        XCTAssertTrue(app.navigationBars["Sign Consent"].waitForExistence(timeout: 3))
        let signAndEnrollButton = app.buttons["Sign and Enroll"]
        XCTAssertFalse(signAndEnrollButton.isEnabled)

        let drawSignatureButton = app.buttons["study_consent_draw_signature_button"]
        XCTAssertTrue(drawSignatureButton.waitForExistence(timeout: 2))
        drawSignatureButton.tap()
        let saveSignatureButton = app.buttons["study_signature_save_button"]
        XCTAssertTrue(saveSignatureButton.waitForExistence(timeout: 2))
        drawSignature(in: app)
        XCTAssertTrue(saveSignatureButton.isEnabled)
        saveSignatureButton.tap()

        XCTAssertTrue(app.images["study_signature_preview_image"].waitForExistence(timeout: 2))
        XCTAssertFalse(signAndEnrollButton.isEnabled)

        let firstNameField = app.textFields["study_consent_first_name_field"]
        let lastNameField = app.textFields["study_consent_last_name_field"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 2))
        XCTAssertTrue(lastNameField.exists)

        lastNameField.tap()
        lastNameField.typeText("Draft")
        XCTAssertTrue(waitForEnabledState(false, of: signAndEnrollButton))

        firstNameField.tap()
        firstNameField.typeText("Alex")
        XCTAssertTrue(waitForEnabledState(true, of: signAndEnrollButton))

        replaceText(in: lastNameField, with: "")
        XCTAssertTrue(waitForEnabledState(false, of: signAndEnrollButton))
        replaceText(in: lastNameField, with: "Rivers")
        XCTAssertTrue(waitForEnabledState(true, of: signAndEnrollButton))

        replaceText(in: firstNameField, with: "")
        XCTAssertTrue(waitForEnabledState(false, of: signAndEnrollButton))
        replaceText(in: firstNameField, with: "Alex")
        XCTAssertTrue(waitForEnabledState(true, of: signAndEnrollButton))

        let signatureScroll = app.scrollViews["study_consent_signature"]
        for _ in 0..<3 where !signAndEnrollButton.isHittable {
            signatureScroll.swipeUp()
        }
        XCTAssertTrue(signAndEnrollButton.isHittable)
        signAndEnrollButton.tap()

        XCTAssertTrue(app.buttons["study_begin_orientation_button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Sign Consent"].exists)
        XCTAssertFalse(app.navigationBars["Informed Consent"].exists)
        XCTAssertTrue(app.navigationBars["Loudness Matching Study"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Study Details"].exists)
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

    private func makeMockedStudyApp(scenario: MockStudyScenario) -> XCUIApplication {
        let app = makeAuthenticatedStudyApp()
        app.launchEnvironment["UITEST_MOCK_STUDY_SCENARIO"] = scenario.rawValue
        return app
    }

    @MainActor
    private func launchEnrolledStudyOrientation(
        audioPreflightReady: Bool = false
    ) -> XCUIApplication {
        let app = makeAuthenticatedStudyApp()
        app.launchEnvironment["UITEST_MOCK_STUDY_ALREADY_ENROLLED"] = "1"
        if audioPreflightReady {
            app.launchEnvironment["UITEST_MOCK_AUDIO_PREFLIGHT_READY"] = "1"
        }
        app.launch()

        let studyCard = app.buttons["study_card_study-no-1"]
        XCTAssertTrue(studyCard.waitForExistence(timeout: 5))
        studyCard.tap()

        let beginOrientationButton = app.buttons["study_begin_orientation_button"]
        XCTAssertTrue(beginOrientationButton.waitForExistence(timeout: 3))
        XCTAssertEqual(beginOrientationButton.label, "Begin Orientation")
        XCTAssertTrue(app.staticTexts["Welcome to Study No. 1"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "We will set up your hearing-test baseline, then run the same tinnitus loudness-match flow used for every Study No. 1 task."
            ].exists
        )
        beginOrientationButton.tap()

        XCTAssertTrue(app.navigationBars["Orientation"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["study_onboarding_hearing_test_step"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Take an Apple Hearing Test"].exists)
        XCTAssertFalse(app.otherElements["study_onboarding_welcome_step"].exists)
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
    private func openStudyDetails(in app: XCUIApplication) {
        let studyCard = app.buttons["study_card_study-no-1"]
        XCTAssertTrue(studyCard.waitForExistence(timeout: 5))
        studyCard.tap()
        XCTAssertTrue(app.navigationBars["Study Details"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func openStudyConsentReader(in app: XCUIApplication) {
        openStudyDetails(in: app)
        openStudyConsentReaderFromLanding(in: app)
    }

    @MainActor
    private func openStudyConsentReaderFromLanding(in app: XCUIApplication) {
        let reviewButton = app.buttons["study_consent_review_button"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 3))
        reviewButton.tap()
        XCTAssertTrue(app.navigationBars["Informed Consent"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func continueToStudyConsentSignature(in app: XCUIApplication) {
        scrollConsentToBottom(in: app)
        let signatureButton = app.buttons["study_consent_signature_button"]
        XCTAssertTrue(signatureButton.waitForExistence(timeout: 2))
        XCTAssertTrue(signatureButton.isEnabled)
        signatureButton.tap()
        XCTAssertTrue(app.navigationBars["Sign Consent"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func completeStudyConsentSignature(
        in app: XCUIApplication,
        firstName: String,
        lastName: String
    ) {
        let firstNameField = app.textFields["study_consent_first_name_field"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 2))
        firstNameField.tap()
        firstNameField.typeText(firstName)
        firstNameField.typeText("\n")

        let lastNameField = app.textFields["study_consent_last_name_field"]
        XCTAssertTrue(lastNameField.waitForExistence(timeout: 2))
        lastNameField.tap()
        lastNameField.typeText(lastName)
        lastNameField.typeText("\n")

        let drawSignatureButton = app.buttons["study_consent_draw_signature_button"]
        XCTAssertTrue(drawSignatureButton.waitForExistence(timeout: 2))
        drawSignatureButton.tap()

        let saveSignatureButton = app.buttons["study_signature_save_button"]
        XCTAssertTrue(saveSignatureButton.waitForExistence(timeout: 2))
        drawSignature(in: app)
        XCTAssertTrue(saveSignatureButton.isEnabled)
        saveSignatureButton.tap()
        XCTAssertTrue(app.images["study_signature_preview_image"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func signAndEnrollButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedButton = app.buttons["study_consent_sign_and_enroll_button"]
        if identifiedButton.waitForExistence(timeout: 0.5) {
            return identifiedButton
        }
        return app.buttons["Sign and Enroll"]
    }

    @MainActor
    private func makeSignAndEnrollButtonHittable(in app: XCUIApplication) -> XCUIElement {
        let button = signAndEnrollButton(in: app)
        let signatureScroll = app.scrollViews["study_consent_signature"]
        for _ in 0..<4 where !button.isHittable {
            signatureScroll.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 2))
        XCTAssertTrue(button.isHittable)
        return button
    }

    @MainActor
    private func assertStudyConsentLanding(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Study Details"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.scrollViews["study_consent_landing"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func assertStudyTaskDashboardDestination(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["study_begin_orientation_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Welcome to Study No. 1"].exists)
        XCTAssertFalse(app.navigationBars["Sign Consent"].exists)
        XCTAssertFalse(app.navigationBars["Informed Consent"].exists)
        XCTAssertTrue(app.navigationBars["Loudness Matching Study"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Study Details"].exists)
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        if let currentValue = field.value as? String,
           currentValue != text,
           !currentValue.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }
        if !text.isEmpty {
            field.typeText(text)
        }
    }

    @MainActor
    private func waitForEnabledState(
        _ isEnabled: Bool,
        of element: XCUIElement,
        timeout: TimeInterval = 2
    ) -> Bool {
        let predicate = NSPredicate(format: "enabled == %@", NSNumber(value: isEnabled))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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

    private enum MockStudyScenario: String {
        case success
        case failOnce = "fail_once"
        case pendingRecovery = "pending_recovery"
    }
}
