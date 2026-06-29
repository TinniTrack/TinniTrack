# Study No. 1 Native Consent Redesign Plan

## Summary

- Rebuild Study No. 1 enrollment around the provided mockups, using the existing loudness task modal style as the local design system: full-screen modal, white/system background, circular icon controls, bold large titles, restrained cards, thin strokes, capsule primary CTAs, and the app's bright blue primary color.
- Replace the visible ResearchKit consent flow with native SwiftUI screens: study landing, consent reader, signature, finalizing, and enrolled confirmation.
- Keep Supabase consent storage/RPC enrollment, but switch the client consent completion path from ResearchKit-result-native to app-native.
- Treat 8 AM, 12 PM, 4 PM, and 8 PM as canonical for Study No. 1 scheduling.

## Mockup-Faithful UI Direction

- Study landing page: match the screenshot's centered modal sheet feel, with top back/close circular controls, blue `Study Details` eyebrow, title `Study No. 1: Loudness Match`, two-line gray subtitle, an `At a glance` bordered table, `What you'll do`, `You may be eligible if`, a blue-tinted `Before you enroll` callout, a full-width blue capsule `Review Study Consent`, and small gray footer text.
- Landing table: implement six rows with left blue SF Symbols, bold labels, and values: Duration/14 days, Daily effort/4 brief check-ins per day, Time per check-in/About 1-3 minutes, Equipment/iPhone + AirPods Pro (2nd gen), Type/Research, not treatment, You're in control/You can stop at any time.
- Consent reader: match `Step 1 of 2`, blue progress bar at 50%, large `Informed Consent`, subtitle `Study No. 1: Loudness Match`, blue-tinted key information card, horizontal pill tabs, structured document sections, sticky bottom lock hint, and bottom action bar with text `I do not agree` plus blue capsule `I agree, continue to signature`.
- Consent content: preserve the PDF's richer structure in native layout: PI block, purpose, eligibility bullets, baseline session, daily assessments, 8/12/4/8 schedule chips, debrief, equipment, risks, benefits, compensation, privacy, questions/IRB contact, and final agree/decline language.
- Signature page: match `Step 2 of 2`, full progress bar, `Sign Consent`, explanatory text, checked attestation card, first/last name fields, bordered signature canvas with baseline and `Clear`, signed-today row, secure-save row, blue capsule `Sign and Enroll`, and secondary `I do not agree`.
- Use the loudness modal components as the style baseline: `LoudnessMatchModalColors`, capsule button height around 58 pt, circular control buttons around 54 pt where consistent with existing task modals, horizontal padding around 26-34 pt, compact card radii around 6-8 pt, and SF Symbols instead of custom icon drawing.

## Implementation Changes

- Expand `StudyConsentDefinition` from flat text blobs into structured, versioned content blocks supporting headings, paragraphs, bullets, numbered activities, schedule chips, callouts, contacts, consent choices, key-info bullets, and a deterministic `contentSHA256Hex`.
- Bump Study No. 1 consent to `study-no-1-consent-v2`; store both PDF hash and canonical content hash so the record proves what version/content the participant saw.
- Build native consent views in `TinniTrack/Features/Consent/Views/`: reusable modal chrome, `StudyConsentReaderView`, `StudyConsentSignatureView`, signature canvas wrapper, callout/card/table/chip components, finalizing overlay, and success state.
- Update `StudyConsentFlowViewModel` to own native flow state: scroll gate, section selection, agreement/decline, typed name validation, attestation checkbox, signature capture, PDF artifact generation, finalization, retry, and dismiss.
- Add `ConsentArtifactGenerating` in `TinniTrack/Services/Consent/` using `UIGraphicsPDFRenderer` to generate the participant-copy PDF from the same structured content, typed name, date, signature image, consent version, and content hash.
- Remove consent presentation from `ResearchKitTaskPresenterView`/`ResearchKitTaskRequest` after the native path is wired; keep ResearchKit isolated for audio/study tasks only.
- Update Study No. 1 scheduling constants and new Supabase migration/RPC definitions to use `[8, 12, 16, 20]`, auditing hardcoded slot arrays in existing scheduling functions.
- Add Supabase migration fields for native consent metadata: `consent_content_sha256`, `signature_image_sha256`, `collection_method`, and attestation text/version, while leaving legacy ResearchKit columns nullable for old rows.

## Test Plan

- Unit test the new consent catalog for `v2`, key-info content, PDF-derived section structure, contact blocks, schedule chips, consent choices, and deterministic content hash.
- Unit test flow validation: agree button locked until bottom, signature step locked until attestation, first/last name, drawn signature, signed date, PDF data, PDF hash, and content hash exist.
- Unit test decline/cancel paths: no PDF generation, no Supabase finalization, no enrollment.
- Unit test `SupabaseConsentService` payloads for native metadata and backwards-compatible nullable ResearchKit fields.
- Update `StudyNo1ConfigurationTests` to expect `[8, 12, 16, 20]` and next-day scheduling after the 8 AM boundary.
- Add SwiftUI previews for landing, consent reader, signature empty/filled, finalizing, and success states at small and standard phone heights.
- Verify with one simulator only: `xcodebuild test -scheme "TinniTrack Local Dev" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TinniTrackTests`, plus Supabase migration/advisor checks where available.

## Commit Plan

- Commit 1: structured consent domain model, Study No. 1 v2 content, schedule constants, and tests.
- Commit 2: Supabase migration and consent service payload updates.
- Commit 3: PDF artifact generator and native signature capture.
- Commit 4: mockup-faithful study landing and consent flow UI.
- Commit 5: ResearchKit consent cleanup, preview/verification fixes, and docs updates.

## Assumptions

- The provided mockups are the visual source of truth; implementation should match their hierarchy, spacing, labels, controls, blue accents, and sticky actions closely.
- The existing loudness task modal style is the app-native baseline, so the consent flow should feel like the same family, not like a generic dashboard card stack.
- The draft PDF is provisional, but its structure and meaning should be preserved until the IRB-approved final text replaces it.
- Regulatory grounding remains: key information should appear at the beginning, eConsent should be easy to navigate, and the system should document consent with durable evidence and a participant-copy artifact. Reference guidance reviewed during planning: HHS key information guidance, HHS/OHRP eConsent guidance, and FDA eConsent guidance.

---
9. Footer note

### Header

Place a small blue label near the top of the content:

```text
Study Details
```

The label is bold or semibold, bright blue, and around 13-14 pt.

Below it, place the main title:

```text
Study No. 1: Loudness Match
```

The title is black, bold, and about 23-25 pt.

Below the title, place a gray subtitle:

```text
Help us understand how tinnitus loudness changes throughout the day.
```

The subtitle is around 16 pt, medium gray, and wraps onto two lines if needed.

### At-A-Glance Card

Below the header, place a white card with a thin light-gray border and a 6-8 px corner radius.

The card title is:

```text
At a glance
```

The title is black and bold, positioned at the top-left of the card.

The card contains six rows. Each row has:

- A bright blue outline icon in the left column.
- A bold black label in the middle column.
- A regular-weight value in the right column.
- A thin horizontal divider between rows.

Rows:

| Icon | Label | Value |
| --- | --- | --- |
| Calendar | Duration | 14 days |
| Clock | Daily effort | 4 brief check-ins per day |
| Stopwatch | Time per check-in | About 1-3 minutes |
| Headphones | Equipment | iPhone + AirPods Pro (2nd gen) |
| Lab flask | Type | Research, not treatment |
| Shield check | You're in control | You can stop at any time |

Use compact row heights and keep icon, label, and value aligned vertically.

### What You'll Do Section

Below the card, place a section heading:

```text
What you'll do
```

The heading is black, bold, and around 15-16 pt.

Below it, place the paragraph:

```text
Import baseline audiogram data from Apple Health, complete a loudness-matching task, and answer brief check-ins during the day.
```

The paragraph is medium gray, around 14-15 pt, with comfortable line height.

### Eligibility Section

Place another section heading:

```text
You may be eligible if
```

Below it, show four compact checklist rows. Each row uses a small filled blue circle with a white checkmark, followed by black or dark-gray text.

Checklist items:

- You are 18 or older.
- You experience tinnitus.
- You have an iPhone and AirPods Pro.
- You can complete scheduled tasks.

### Before-You-Enroll Callout

Below the checklist, place a light blue informational callout.

The callout has:

- A very light blue background.
- A thin blue border.
- Rounded corners around 5-6 px.
- A blue outlined info icon on the left.
- Text content on the right.

Heading:

```text
Before you enroll
```

The heading is bold and black.

Body:

```text
You'll review the full study consent form and decide whether you want to participate. You can stop at any time.
```

The body text is compact, dark, and wraps over multiple lines.

### Primary Action

Near the bottom, place a full-width rounded pill button with a bright blue fill. The button is about 43-46 px tall.

Button text:

```text
Review Study Consent
```

The text is centered, white, bold, and around 15-16 pt.

Below the button, center a small gray footer note:

```text
You will not be enrolled until you sign.
```


1. Step label and progress bar
2. Page title and study subtitle
3. Key information card
4. Consent section tabs
5. What-you-will-do section
6. Scroll-to-continue hint
7. Fixed bottom action bar

### Progress Area

Show a small blue label:

```text
Step 1 of 2
```

Below it, show a horizontal progress bar about 4 px tall. The filled portion is bright blue and spans a little over half the available width. The remaining track is light gray.

### Header

Large title:

```text
Informed Consent
```

The title is black, bold, and about 23-25 pt.

Subtitle:

```text
Study No. 1: Loudness Match
```

The subtitle is medium gray and smaller than the title.

### Key Information Card

Place a light blue card below the header. The card has a thin blue border and rounded corners around 6-8 px.

At the top of the card, place a blue outlined info icon followed by the bold title:

```text
Key information
```

Below the title, show a compact list. The first three items use small blue dot bullets:

- This is research, not treatment.
- You'll complete a baseline session, 14 days of brief assessments, and a debrief.
- You'll use your iPhone and AirPods Pro.

The remaining items use small blue checkmarks:

- Risks are minimal but may include increased awareness of tinnitus.
- You can stop at any time.
- Participation is voluntary.
- Compensation is up to $100.
- Your data is coded and used for research only.

The text should be black or very dark gray with tight but readable line height.

### Consent Section Tabs

Below the key information card, place a horizontal row of compact pill or segmented buttons. The row is dense and spans the content width.

Tabs:

- Key Info
- What You'll Do
- Risks
- Privacy
- Compensation
- Contacts

The active tab is `Key Info`. It has a bright blue fill and white text.

Inactive tabs have a white fill, light-gray border, and black text.

### What You'll Do Section

Below the tabs, place a bold heading:

```text
What you'll do
```

Then show a numbered step list. Each step number appears inside a small light-blue filled circle with a darker blue number.

Step 1:

- Number circle: `1`
- Bold label: `Baseline session`
- Body:

```text
You will import your baseline audiogram data from Apple Health and complete a loudness-matching task.
```

Step 2:

- Number circle: `2`
- Bold label: `Daily assessments (14 days)`
- Body:

```text
You will complete brief check-ins four times each day: 8 AM, 12 PM, 4 PM, and 8 PM. Each check-in takes about 1-3 minutes.
```

### Time Chips

Below Step 2, place four compact rounded rectangular chips in one row.

Each chip has:

- A small blue clock icon.
- A time label.
- White or very light-gray fill.
- Light-gray border.
- Rounded corners.

Chips:

- 8 AM
- 12 PM
- 4 PM
- 8 PM

### Scroll-To-Continue Hint

Near the lower content area, center a small gray lock icon and gray text:

```text
Scroll to the end to continue
```

This appears disabled or instructional, not interactive.

### Bottom Action Bar

The bottom action bar is fixed to the bottom of the screen. It has a white background and a thin light-gray top border.

Inside the bar, place two actions horizontally:

- Left: blue text button
- Right: large blue pill button

Left text button:

```text
I do not agree
```

Right primary button:

```text
I agree, continue to signature
```

The primary button is bright blue with white bold text. It takes most of the horizontal space and is about 52 px tall.

## Screen 3: Sign Consent Page

This page presents Step 2 of 2 and collects the participant's typed name and drawn signature before enrollment.

### Layout

The top navigation buttons match the prior screens. Below them is the completed progress indicator, then a form-like consent signature layout.

The content order is:

1. Step label and complete progress bar
2. Page title and explanatory paragraph
3. Eligibility confirmation card
4. First name field
5. Last name field
6. Draw-signature area
7. Signed-date metadata row
8. Secure-copy metadata row
9. Primary CTA
10. Secondary disagreement action

### Progress Area

Show the small blue label:

```text
Step 2 of 2
```

Below it, show a horizontal progress bar. The bar is fully filled in bright blue.

### Header

Large title:

```text
Sign Consent
```

The title is black, bold, and about 23-25 pt.

Below it, place a gray explanatory paragraph:

```text
By signing below, you confirm that you reviewed the consent information and choose to participate in Study No. 1: Loudness Match.
```

The paragraph uses medium-gray text, around 15-16 pt, and wraps across multiple lines.

### Eligibility Confirmation Card

Place a white rounded rectangle card with a light-gray border.

Inside the card:

- A filled blue circular check icon on the left.
- Confirmation text on the right.

Text:

```text
I am 18 or older, understand participation is voluntary, and agree to participate.
```

The text is black and compact, wrapping onto two lines if needed.

### Name Fields

Show two labeled text inputs.

First label:

```text
First name
```

First input value:

```text
Alex
```

Second label:

```text
Last name
```

Second input value:

```text
Morgan
```

Labels are small and medium gray. Inputs are full width, white, lightly bordered, rounded rectangles about 43-46 px tall, with text inset from the left.

### Signature Area

Show the label:

```text
Draw signature
```

Below it, place a large white signature pad with a light-gray border and rounded corners. The pad is roughly 115-125 px tall.

Inside the pad:

- A black cursive signature reading `Alex Morgan`.
- A thin gray horizontal baseline near the lower portion of the pad.
- A blue `Clear` action at the lower-right inside the signature box.

### Metadata Rows

Below the signature pad, place two compact metadata rows.

First row:

- Small black calendar icon.
- Text:

```text
Signed today, Jun 25, 2026
```

Second row:

- Lock icon inside a light gray circular background.
- Gray text:

```text
A signed consent copy will be saved securely.
```

### Actions

Place a full-width bright blue rounded pill button near the bottom.

Primary button text:

```text
Sign and Enroll
```

The text is centered, white, bold, and around 16 pt. The button height is about 48-52 px.

Below the primary button, center a blue text button:

```text
I do not agree
```

The secondary action is semibold and uses the same bright blue as the primary action.

## Interaction Notes

The intended flow is:

1. The participant starts on the Study Landing Page.
2. Tapping `Review Study Consent` opens the Informed Consent Page.
3. On the Informed Consent Page, the participant reviews the content and scrolls to the end.
4. Once eligible to continue, the participant taps `I agree, continue to signature`.
5. The Sign Consent Page opens.
6. The participant confirms eligibility, enters first and last name, draws a signature, and taps `Sign and Enroll`.
7. Tapping any `I do not agree` action exits or declines the consent flow without enrolling.

The interface should make it clear that the user is not enrolled until the final signature step is completed.