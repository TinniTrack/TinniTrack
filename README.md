# Tinnitus Research and Tracking App

## 1. Project Overview
We are building an iOS research app that measures tinnitus loudness using calibrated headphone-based psychoacoustic tasks. Participants complete pitch-matching and loudness-matching tasks that produce scientifically interpretable, repeatable data.

**Data collection:**
*   Baseline hearing thresholds (via HealthKit Audiograms).
*   Longitudinal Tinnitus Loudness-Match (LM) and Pitch-Match (PM) measurements.

## 2. Why we’re building it
*   **Objectivity:** Tinnitus is subjective; standardized calibration (dB SL/HL) allows for inter-subject and longitudinal comparison.
*   **Hardware Consistency:** Apple devices (specifically AirPods Pro) provide known acoustic profiles, enabling clinical-grade accuracy outside a sound booth.
*   **Temporal Resolution:** Daily measurements could capture the volatile nature of tinnitus, revealing patterns missed in infrequent clinical visits.

## 3. V1 User Journey

### A. Authentication (Login / Sign Up)
Upon downloading the app, the user is prompted to either **Log In** or **Sign Up**.

*   **Log In:** If the user already has an account, they authenticate and proceed into the app.
*   **Sign Up:** If the user is new, they create an account using email/password. During signup, we collect:
    *   First name
    *   Last name
    *   Date of birth

After signup, the user proceeds to the home dashboard.

### B. Home Dashboard (Studies List)
The home screen shows a list of available recruiting studies.

For each study, the user can see:
*   Study title
*   Brief description
*   Current recruitment status (recruiting, recruiting paused, closed)

The user can tap into a study to view its details.
*   If the user is **not enrolled** in a study, selecting a study displays:
    *   Study description
    *   Inclusion criteria
    *   Exclusion criteria
*   The user can then choose to:
    *   **Enroll** in the study, or
    *   **Exit** (return to the studies list)

### C. Enrollment & eConsent
To participate in a study, the user must:

1.  Review study details:
    *   Study purpose
    *   Inclusion / exclusion criteria
    *   Time commitment
    *   Data collected
2.  Complete eConsent:
    *   The user signs an electronic consent form.
    *   The app stores the signed consent in the backend.
3.  Enrollment confirmation:
    *   Once consent is completed, the user becomes “enrolled” in the study.

### D. Study No. 1: Audiogram Import (HealthKit) Prerequisite
For Study No. 1, the first requirement is importing an **audiogram from HealthKit**.

*   **Audiogram Check:** The app queries HealthKit for an existing valid audiogram.
*   **If no audiogram is available:** the app prompts the user to complete a hearing test from the native Apple flow (via **Apple Settings** or the **Health app**, depending on iOS version/device).
*   **Import:** Once available, the app imports the audiogram data and proceeds to enable the study tasks.

### E. Study No. 1: Loudness-Match (LM) Tasks
Users complete loudness-matching tasks at specific times of day.

*   The Study Home Page shows:
    *   A list of **future tasks**, sorted **soonest → latest**
    *   A list of **completed tasks**
*   A task is only available to start if the user is currently within the **active time window** for that task.
*   **Schedule:** 4 tasks per day for 7 consecutive days.
*   **Task execution:** Each task follows a structured validation and measurement flow:
    1.  **Headphone gating (AirPods Pro 2 required):**
        *   When the user taps **Start Task**, the app verifies the connected audio output device.
        *   Only **AirPods Pro (2nd generation)** are permitted for Study No. 1.
        *   If the correct headphones are **not connected**, the task cannot proceed.
            *   The user is shown a blocking message instructing them to connect AirPods Pro (2nd generation).
            *   The task remains locked until the correct headphones are detected.
        *   If the correct headphones are connected, the app proceeds to environmental validation.
    2.  **Quiet-room gating (environmental noise check):**
        *   The user is prompted to confirm they are in a quiet environment.
        *   The app measures ambient environmental noise using the device microphone.
        *   A predefined environmental threshold (X dB SPL, to be finalized during validation testing) determines acceptability.
        *   If environmental noise exceeds the threshold:
            *   The task cannot begin.
            *   The user is instructed to move to a quieter location.
            *   Ambient noise is continuously monitored.
        *   Once environmental noise falls below the threshold:
            *   The task becomes available to start.
    3.  **Continuous monitoring during task:**
        *   Environmental noise continues to be monitored throughout the Loudness-Match task.
        *   If ambient noise rises above the allowed threshold at any point:
            *   A visible on-screen alert indicates that the environment is too loud.
            *   Tone adjustment is temporarily paused or disabled.
        *   When environmental noise returns below the threshold:
            *   The alert automatically disappears.
            *   The user may resume the task.
    4.  **Loudness-matching procedure:**
        *   The user adjusts the volume of a **1,000 Hz pure tone** until it matches their tinnitus loudness.
        *   The match is recorded in calibrated units (dB HL and/or dB SL).
        *   The user submits the match and receives a confirmation that the task has been completed.

## 4. Scientific & Engineering Core
*   **Calibration:** Implements RETSPL tables to convert generic dB SPL to clinical dB HL (Hearing Level) and dB SL (Sensation Level).
*   **Hardware Gating:** Allow-list enforcement for headphones with known sensitivity profiles to prevent uncalibrated data collection.

## 5. System Architecture

### Frontend (iOS)
*   **UI/UX:** SwiftUI
*   **Frameworks:**
    *   **HealthKit:** For audiogram retrieval.
    *   **ResearchKit (StanfordBDHG Fork):** We use [StanfordBDHG’s SPM fork of Apple ResearchKit](https://github.com/StanfordBDHG/ResearchKit).

### Backend
*   **Supabase:** PostgreSQL + Auth.

### Source Layout (iOS)

We use a **feature-first** structure in a single app target for V1, with clear seams for future module extraction:

*   `TinniTrack/Features/`
    *   UI screens and flow state organized by product area.
    *   Current areas: `Onboarding`, `Dashboard`, `HearingTest`, `LoudnessMatch`.
*   `TinniTrack/Domain/`
    *   Pure domain logic and models (no direct UI dependencies).
    *   Includes audio engine, calibration logic, and study/task data models.
*   `TinniTrack/Services/`
    *   Integration boundaries for external systems (`Supabase`, `HealthKit`).
    *   Prefer protocol-based interfaces so features depend on abstractions.
*   `TinniTrack/Modules/`
    *   Reusable protocol engines intended to support future studies (e.g., Study No. 2).
    *   Keep in-app for now; extract to SPM modules when workflows stabilize.
*   `TinniTrack/Shared/`
    *   Cross-feature app infrastructure (app root, navigation shell, shared UI primitives).

Dependency direction for maintainability:

*   `Features` → depends on `Domain` and service protocols.
*   `Services` implements protocol contracts used by `Features`.
*   `Domain` should not depend on `Features`.

## 6. Backend Responsibilities
*   **Authentication:** Email/password login and account signup via Supabase Auth. Users authenticate by logging in to an existing account or signing up for a new account (collecting name and DOB during signup).
*   **Row Level Security (RLS):** Policies ensuring users can only insert/read their own data, while researchers can read all anonymized data.

### Database (Supabase Postgres)

The backend database lives in **Supabase (PostgreSQL)**. We treat the database schema as *version-controlled infrastructure*:

*   **All schema changes must be made via SQL migration files** (no “click ops” in the Supabase UI for anything that affects tables/columns/constraints). This keeps the schema reproducible across environments and makes review/rollback possible.
*   Migrations should be **additive and explicit** (create/alter/drop with clear intent) and committed to the repo alongside the code that depends on them.

#### Current Schema:

Below is the initial data model and how each table fits into the picture.

##### 1) `auth.users` (Supabase Auth)
*   Supabase manages credentials and the canonical user id (`uuid`).
*   All app-owned tables that are user-scoped reference `auth.users.id`.

##### 2) `public.profiles`
**Purpose:** Store participant metadata collected during signup.

*   `id` (`uuid`): Primary key. Defaults to `auth.uid()` and is a foreign key to `auth.users(id)`.
*   `participant_id` (`integer`, identity, unique): A stable, sequential participant identifier for research-facing workflows/exports.
*   `first_name`, `last_name`, `date_of_birth`: Required demographic fields captured at signup.
*   `timezone`: Optional (useful for scheduling task windows).
*   `created_at`: Server timestamp.

Relationship notes:
*   `profiles.id` → `auth.users.id` with **ON DELETE CASCADE** (deleting an auth user cleans up the profile).

##### 3) `public.studies`
**Purpose:** Define research studies that appear in the Home Dashboard.

*   `id` (`uuid`): Primary key.
*   `slug` (`text`, unique): Stable identifier used by the client (deep links, routing, etc.).
*   `title`, `description`: User-facing study content.
*   `status` (`text`): Constrained to `recruiting`, `recruiting paused`, or `closed`.
*   `created_at`: Server timestamp.

##### 4) `public.study_enrollments`
**Purpose:** Link a user to a study and track enrollment state.

*   `id` (`uuid`): Primary key.
*   `user_id` (`uuid`): FK → `auth.users(id)`.
*   `study_id` (`uuid`): FK → `public.studies(id)`.
*   `status` (`text`): One of `enrolled`, `withdrawn`, `completed`, `screen_failed`.
*   `enrolled_at`, `created_at`: Timestamps (note: `enrolled_at` is the domain timestamp; `created_at` is record creation).

Constraints:
*   Unique `(user_id, study_id)` so a user has at most one enrollment record per study.

##### 5) `public.consents`
**Purpose:** Store eConsent signatures per user per study per consent version.

*   `id` (`uuid`): Primary key.
*   `user_id` (`uuid`): FK → `auth.users(id)` (defaults to `auth.uid()`).
*   `study_id` (`uuid`): FK → `public.studies(id)`.
*   `consent_version` (`text`): Version string (e.g., `v1`, `2026-02-01`).
*   `consent_pdf_path` (`text`): Storage path for the signed PDF (Supabase Storage).
*   `signed_at`: Timestamp.

Constraints:
*   Unique `(user_id, study_id, consent_version)` so a user can’t sign the same version twice.

##### 6) `public.audiograms`
**Purpose:** Persist baseline hearing threshold data (from HealthKit audiograms) needed for calibration and analysis.

*   `id` (`uuid`): Primary key.
*   `user_id` (`uuid`): FK → `auth.users(id)` (defaults to `auth.uid()`).
*   `created_at`: Timestamp (record creation).
*   `measured_at` (`timestamptz`): When the audiogram was measured.
*   `source` (`text`): Where the audiogram came from (e.g., HealthKit / manual import).
*   `headphone_name` (`text`): The output route/headphone used when relevant.
*   `frequency_data` (`jsonb`): Frequency→threshold payload. We store this as JSONB because HealthKit audiograms can be sparse and device-dependent.

##### 7) `public.scheduled_tasks`
**Purpose:** Generate the *planned* schedule of tasks for a user’s study enrollment (what should happen, when).

This table is intentionally minimal about “what the task does” — the task algorithms live in the client code, while the DB stores scheduling + lifecycle.

*   `id` (`uuid`): Primary key.
*   `enrollment_id` (`uuid`): FK → `public.study_enrollments(id)`.
*   `task_key` (`text`): Minimal task identifier (e.g., `lm_1khz_v1`).
*   `task_version` (`int`): Schema-level versioning for task definition changes.
*   `scheduled_for`, `window_start`, `window_end`: The intended time and gating window.
*   `status` (`text`): One of `scheduled`, `completed`, `missed`, `skipped`, `cancelled`.
*   `day_index` (`int`): Deterministic ordering (0..6).
*   `slot_index` (`int`): Deterministic ordering (0..3).
*   `created_at`, `completed_at`: Timestamps.

Constraints:
*   Unique `(enrollment_id, day_index, slot_index)` to prevent duplicate slots.

##### 8) `public.task_runs`
**Purpose:** Store the *actual* execution data for a task (what happened) — this is the core research dataset.

*   `id` (`uuid`): Primary key.
*   `scheduled_task_id` (`uuid`): FK → `public.scheduled_tasks(id)`.
*   `enrollment_id` (`uuid`): FK → `public.study_enrollments(id)`.
*   `user_id` (`uuid`): FK → `auth.users(id)` (defaults to `auth.uid()`).
*   `run_status` (`text`): One of `completed`, `aborted`, `failed`.
*   `started_at`, `completed_at`, `submitted_at`: Timing metadata.
*   `app_version`, `protocol_version`, `calibration_version`: Reproducibility fields for analysis.
*   `device_info` (`jsonb`): Model / iOS version / etc.
*   `headphone_info` (`jsonb`): Route name, model id, firmware if available.
*   `gating` (`jsonb`): Persist outputs of gating logic (computed in app code).
*   `raw_payload` (`jsonb`): The full task payload (trials, slider moves, responses, etc.).
*   `created_at`: Server timestamp.

#### Data Flow Summary
*   **Sign up / login:** `auth.users` is created by Supabase Auth → we insert a matching `public.profiles` row.
*   **Study discovery:** Client reads from `public.studies` (filtered by status).
*   **Enrollment:** Client creates `public.study_enrollments` and then generates `public.scheduled_tasks` for the protocol.
*   **Consent:** Client writes `public.consents` + stores the PDF in Supabase Storage.
*   **Measurements:** Audiograms → `public.audiograms`; task executions → `public.task_runs` (linked back to `scheduled_tasks` and `study_enrollments`).

#### Access Control (RLS Plan)
RLS policies are required on all user-scoped tables (`profiles`, `consents`, `audiograms`, `study_enrollments`, `scheduled_tasks`, `task_runs`) so:

*   Participants can only read/insert/update rows that belong to their own `auth.uid()`.
*   Research/admin access is granted via Supabase roles/claims (e.g., service role for ETL/exports, or a dedicated “researcher” role) and should never be shipped to the client.

(Policies are not defined in the initial schema migration yet, but this is the intended enforcement model.)

## 7. Version Plan

### Version 1 (MVP)
*   User account creation and login (signup collects name and DOB)
*   Home dashboard that lists available recruiting studies
*   Users can view study description + inclusion/exclusion criteria
*   Users can enroll in a study via eConsent
*   Study No. 1 built and available for loudness matching
*   For study No. 1:
    *   Consent + permissions
    *   Prompt Apple hearing test (if needed) and import audiogram via HealthKit
    *   Headphone gating for Apple Airpods Pro 2
    *   Quiet-room gating
    *   Single-frequency (1kHz) LM
    *   4 tasks per day for 7 days
    *   Daily local push notifications

### V2 (Future Work)
*   Home screen lists all available studies
*   Users can enroll in multiple studies
*   Study No. 2 built and available for LM and multi-frequency PM (Pitch Match) testing. Have the user both frequency match and loudness match their tinnitus.
*   Add compatibility for AirPods Pro 3
*   Login with biometric auth (faceid or fingerprint)
*   EMA Questionnaires.
*   Researcher dashboard to access participant data.
*   In-app hearing test (bypassing Apple native test).

---

## Appendix: Scientific Background & Vocabulary

### Decibels, Loudness, and Hearing Background

**What sound is:**
Sound is vibrating air creating pressure waves.
*   **Frequency (Hz):** cycles per second → pitch
*   **Amplitude:** size of pressure swings → loudness
*   **Phase:** timing within the cycle
*   **Pressure:** Measured in Pascals (Pa). Speech is a few mPa; threshold of hearing ≈ 20 µPa.
*   **RMS amplitude:** The standard measure for loudness.

**How do we measure loudness:**
The ear reacts to sound logarithmically. Large physical changes in sound often feel like small changes in loudness. Decibels (dB) are a way to describe sound levels on this logarithmic scale. A dB value always compares a sound to a reference point.

### The Decibel Scales (Critical for Calibration)
*   **dB SPL (Sound Pressure Level):** Absolute loudness relative to 20 µPa (physical pressure). Nearly all real‑world sound numbers use dB SPL.
*   **dB HL (Hearing Level):** Normalized clinical scale where "0 dB HL" represents the average human hearing threshold for a specific frequency. Corrects for the ear's varying sensitivity across pitches (e.g., quiet tones at 250 Hz are harder to hear than at 1000 Hz).
*   **dB SL (Sensation Level):** Relative loudness above the user's individual threshold. It expresses loudness relative to your personal ability to hear at a specific frequency.
    *   *Example:* If a user hears a tone at 10 dB HL, and plays a sound at 40 dB HL, the sound is 30 dB SL.

### RETSPL: The Glue Between SPL and HL
**RETSPL = Reference Equivalent Threshold Sound Pressure Level.**
It’s a table (per frequency) giving the SPL that corresponds to 0 dB HL for a specific transducer measured on a standard ear coupler.
*   **Convert HL → SPL:** `SPL = HL + RETSPL(f, transducer)`
*   **Convert SPL → HL:** `HL = SPL − RETSPL(f, transducer)`

Apple’s ResearchKit framework gives us RETSPL tables and device mappings for certain Apple headphones so we can get clinically meaningful dB HL from a phone.

### Other Vocabulary
*   **EMA:** Ecological Momentary Assessment — brief, in‑the‑moment self‑report questions (e.g., tinnitus loudness, annoyance, mood).
*   **Hearing threshold:** (for a given frequency & ear) = the quietest level that a person detects reliably (e.g., 50% of trials).
*   **Audiogram:** a plot of hearing threshold vs frequency for the left and right ear.
