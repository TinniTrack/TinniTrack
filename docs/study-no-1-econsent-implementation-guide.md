# Study No. 1 eConsent Implementation Guide

Date: 2026-06-25

## Objective

Implement a production-quality eConsent flow for Study No. 1. The user should start from the Study No. 1 detail page, complete consent in a full-screen modal, sign with typed first/last name and drawn signature, have a signed PDF stored securely, and become actively enrolled only after consent persistence succeeds.

The provided PDF at `/Users/vasyl/Downloads/Consent_LoudnessMatch_Armstrong.docx.pdf` is the provisional source structure for Study No. 1 consent content. Its exact wording may change later, so implement the consent as structured versioned content rather than a static PDF embed.

## Current Repo Facts

- The app is a SwiftUI iOS research app targeting iOS 18.1+.
- Preserve the feature-first layout:
  - `TinniTrack/Features/` for product flows and SwiftUI.
  - `TinniTrack/Domain/` for pure consent/study models.
  - `TinniTrack/Services/` for ResearchKit, Supabase, Storage, and other external boundaries.
  - `TinniTrack/Shared/` for app infrastructure.
- Feature UI should not import ResearchKit directly. Keep ResearchKit behind `TinniTrack/Services/ResearchKit/`.
- `ResearchKitStudyTaskAdapter` already presents ResearchKit tasks through `ORKTaskViewController`.
- The dashboard currently calls `HomeDashboardViewModel.enroll(studyID:)` directly from the Study Detail button. Replace that direct action with eConsent completion followed by backend-validated enrollment.
- The existing `public.consents` table was part of an early schema mockup and is not currently used or secured by later migrations.
- Pre-existing unrelated working-tree changes were present before this planning work:
  - `Frameworks/ResearchKit`
  - `TinniTrack.xcodeproj/project.pbxproj`
  Do not stage or revert those unless the eConsent implementation intentionally changes them.

## Product Flow

1. User signs in or signs up and lands on the dashboard.
2. Dashboard lists recruiting studies.
3. User opens Study No. 1 details.
4. User taps `Begin eConsent & Enroll`.
5. App presents a large full-screen consent modal.
6. User reviews consent sections, reviews the full consent document, scrolls to the bottom, explicitly agrees, enters first/last name, and draws a signature.
7. App generates the signed consent PDF using ResearchKit.
8. App uploads the signed PDF to a private Supabase Storage bucket.
9. App stores consent metadata in Postgres.
10. App calls an enrollment RPC that validates the signed consent and activates enrollment.
11. Dashboard refreshes and routes the user into the existing Study No. 1 task/orientation experience.

Declining, discarding, cancelling, or failing consent must not create or activate enrollment.

## ResearchKit Decision

Use ResearchKit for the consent mechanics, but do not force the implementation into old sample code.

ResearchKit provides useful components:

- `ORKConsentDocument`
- `ORKConsentSection`
- `ORKConsentReviewStep`
- `ORKConsentSignature`
- `ORKConsentSignatureResult`
- `ORKSignatureStep`
- `ORKInstructionStep`
- signed PDF generation through `ORKConsentDocument.makePDFWithCompletionHandler`

The old ResearchKit sample references `ORKVisualConsentStep`, but the vendored public headers currently expose consent document/review/signature APIs rather than a reliable visual-consent step API. Implement the Study No. 1 consent as ResearchKit instruction steps plus ResearchKit review/signature steps. This still gives native ResearchKit document review, scroll-gated agreement, confirmation, typed name, drawn signature, and PDF generation.

ResearchKit explicitly states that its consent signature is not a cryptographic identity proof. Treat it as a participant attestation tied to the authenticated Supabase user, timestamp, PDF hash, app version, and audit metadata.

## Consent Content Model

Add pure domain models under `TinniTrack/Domain/Models/` or a nearby consent-focused domain folder:

- `StudyConsentDefinition`
- `StudyConsentSection`
- `StudyConsentSignatureRequirement`
- `StudyConsentCompletion`
- `StudyConsentArtifact`
- `StudyConsentCatalog`

Recommended fields:

- `studySlug`
- `studyTitle`
- `consentVersion`
- `documentTitle`
- `reviewReasonForConsent`
- `signaturePageTitle`
- `signaturePageContent`
- `sections`
- `requiresScrollToBottom`
- `requiresName`
- `requiresSignatureImage`

Study No. 1 should use consent version:

```text
study-no-1-consent-v1
```

Initial Study No. 1 section structure:

- Purpose of the Study
- Who Can Participate
- What You Will Do
- Equipment
- Risks
- Benefits
- Compensation
- Privacy
- Questions
- Consent

Keep copy as simple strings in code for the first implementation unless the codebase already has a better local content strategy by implementation time. The key requirement is that consent is versioned and can support future studies without rewriting the flow.

## ResearchKit Adapter Changes

Extend `ResearchKitTaskRequest` with a consent request, for example:

```swift
case studyConsent(StudyConsentDefinition)
```

Extend `ResearchKitTaskResultSummary` with consent output, for example:

```swift
let studyConsent: StudyConsentResultSummary?
```

Suggested result summary fields:

- `taskIdentifier`
- `consentVersion`
- `consented`
- `givenName`
- `familyName`
- `signedAt`
- `pdfData`
- `pdfSHA256Hex`
- `finishState`

Implementation notes:

- Build an `ORKConsentDocument` from `StudyConsentDefinition`.
- Convert consent sections into `ORKInstructionStep`s or manually create `ORKInstructionStep`s with title/text/detail text.
- Create an `ORKConsentSignature` for the participant.
- Set `requiresName = true`.
- Set `requiresSignatureImage = true`.
- Create `ORKConsentReviewStep`.
- Set `requiresScrollToBottom = true`.
- Set `reasonForConsent` to a concise explicit agreement statement.
- Add a final `ORKCompletionStep`.
- On `ORKTaskViewControllerDelegate.didFinishWith`, only treat `.completed` plus `consented == true` as successful consent.
- Extract `ORKConsentSignatureResult`, apply it back to a copy of the consent document, generate a signed PDF, compute SHA-256, and return the result summary.

Keep `ResearchKitTaskPresenterView` as the SwiftUI bridge. Feature views should pass a request and receive the result summary.

## Supabase And Storage Design

Use a new append-only migration in `supabase/migrations/`. Do not rewrite existing migrations.

Before writing the migration, use:

```bash
supabase migration new study_no_1_econsent
```

Modernize the existing mock `public.consents` table through the new migration:

- Enable RLS.
- Add missing metadata columns with `ADD COLUMN IF NOT EXISTS`.
- Add indexes and constraints needed for lookup.
- Keep a uniqueness rule for one signed consent per user, study, and consent version.
- Grant only needed privileges to `authenticated`.

Recommended `public.consents` metadata:

- `id uuid primary key`
- `user_id uuid not null`
- `study_id uuid not null`
- `consent_version text not null`
- `signed_at timestamptz not null`
- `signer_given_name text`
- `signer_family_name text`
- `consent_pdf_bucket text not null`
- `consent_pdf_path text not null`
- `consent_pdf_sha256 text not null`
- `researchkit_task_identifier text`
- `researchkit_finish_state text`
- `app_version text`
- `device_info jsonb`
- `created_at timestamptz not null default now()`

Create or configure a private Supabase Storage bucket:

```text
study-consents
```

Recommended object path:

```text
{user_id}/{study_id}/{consent_version}/{consent_id}.pdf
```

Storage policy requirements:

- Authenticated users can upload only under their own user-id folder.
- Authenticated users can read only their own consent PDFs.
- Do not allow client-side update or delete of signed consent artifacts.
- Bucket is private.

Add an RPC such as:

```sql
public.enroll_in_study_after_consent(
  p_study_id uuid,
  p_consent_id uuid
)
```

The RPC should:

- Require `auth.uid()`.
- Confirm the study exists and is recruiting.
- Confirm the consent row belongs to `auth.uid()`.
- Confirm the consent row matches `p_study_id`.
- Confirm the consent version is the current app-supported Study No. 1 consent version.
- Insert or reactivate `study_enrollments` with `status = 'enrolled'`.
- Set `enrolled_at = now()`.
- Return the enrollment row or void, matching the app service needs.

Use explicit grants and RLS. Supabase documentation reviewed during planning:

- `https://supabase.com/docs/guides/api/securing-your-api`
- `https://supabase.com/docs/guides/storage/security/access-control`

## Service Layer Changes

Add a consent service under `TinniTrack/Services/Studies/` or `TinniTrack/Services/Consent/`:

```swift
protocol ConsentServiceProtocol {
    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws
}
```

`SupabaseConsentService` should:

- Resolve the current authenticated user.
- Build a consent id or receive one from Postgres, depending on final implementation.
- Upload the signed PDF to Supabase Storage.
- Insert the consent metadata row.
- Call `enroll_in_study_after_consent`.

If Supabase Swift Storage API shape is uncertain during implementation, verify against the installed package or current docs before coding. The package is already present and the Xcode project links the `Storage` product.

Update `StudyServiceProtocol` only if enrollment should remain on that service. Prefer separating consent finalization from generic study fetching so the consent flow remains explicit.

## UI Integration

Add a new consent feature area:

```text
TinniTrack/Features/Consent/
```

Suggested components:

- `StudyConsentFlowView`
- `StudyConsentFlowViewModel`
- `StudyConsentFinalizingView`

Integrate from `StudyDetailView`:

- Replace direct enrollment with full-screen consent presentation.
- Keep the primary button label `Begin eConsent & Enroll`.
- Show a loading/finalizing state after ResearchKit returns successful consent.
- Disable duplicate taps while finalizing.
- On success, dismiss details or navigate to the active Study No. 1 task dashboard after dashboard refresh.
- On cancel/decline, return to details without error unless ResearchKit reports a real failure.
- On upload/metadata/RPC failure, show a user-facing error and do not mark enrollment active.

Use `.fullScreenCover(item:)` or equivalent enum-based modal state rather than multiple boolean sheet flags.

## Tests And Verification

Add focused unit tests where practical:

- Study No. 1 consent catalog contains expected version, sections, and signature requirements.
- Consent completion is considered valid only when:
  - ResearchKit finish state is completed.
  - `consented == true`.
  - signed PDF data exists.
  - SHA-256 exists.
  - required signer fields exist.
- Dashboard/view-model flow does not call enrollment/finalization when consent is cancelled or declined.
- Supabase consent metadata payload encodes expected fields and storage path.

Run relevant checks before committing:

```bash
xcodebuild test -scheme "TinniTrack Local Dev" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TinniTrackTests
supabase db lint
supabase db advisors
```

If simulator availability differs, use one iOS Simulator only and keep the `TinniTrack Local Dev` scheme for simulator testing.

## Commit Plan

Follow the repository commit workflow. Inspect `git status --short` before editing and before every commit.

Recommended commit boundaries:

1. Consent domain models, catalog, and tests.
2. Supabase migration and consent persistence service.
3. ResearchKit consent task adapter/result extraction.
4. SwiftUI consent modal integration on Study Detail.
5. Verification fixes and cleanup.

Only stage files belonging to the current milestone. Do not stage pre-existing unrelated changes.

## Acceptance Criteria

- A new account can reach Study No. 1 details and start eConsent.
- eConsent is presented as a full-screen modal.
- Participant must review, explicitly agree, type name, and draw signature.
- Decline/cancel/discard does not enroll.
- Successful consent generates a signed PDF and SHA-256 hash.
- Signed PDF uploads to private Supabase Storage.
- Consent metadata is stored in Postgres under the authenticated user.
- Enrollment is activated only by backend validation of the stored consent.
- Existing Study No. 1 orientation and task dashboard continue to work after enrollment.
- Future studies can add new consent definitions without copying the whole Study No. 1 flow.
- Relevant tests/build checks pass or any skipped checks are documented clearly.
