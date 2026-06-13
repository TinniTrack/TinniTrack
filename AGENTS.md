# AGENTS.md

## Project Context

- This is an iOS research app prototype for tinnitus study workflows, built with SwiftUI, HealthKit, a StanfordBDHG ResearchKit SwiftPM fork, and Supabase.
- Keep the current scientific boundary clear: the loudness-match prototype records normalized playback level and metadata, but validated dB SPL, dB HL, and dB SL mapping is deferred until calibration and device-validation work is complete.
- Preserve the feature-first structure:
  - `TinniTrack/Features/` for product flows, UI, and flow view models.
  - `TinniTrack/Domain/` for pure domain logic and models.
  - `TinniTrack/Services/` for external-system boundaries and protocol implementations.
  - `TinniTrack/Shared/` for cross-feature app infrastructure.
- Feature code should not import ResearchKit directly by default. Use `TinniTrack/Services/ResearchKit/ResearchKitStudyTaskAdapter.swift` as the boundary for ResearchKit presentation and result handling.
- Supabase schema changes must be made through new SQL migration files in `supabase/migrations/`. Do not rewrite migrations that may already have been applied remotely.

## Commit Workflow

- For implementation tasks, work in small, reviewable commits. A single focused commit is fine for a small change; multi-step work should be split into coherent milestones.
- Before editing, inspect `git status --short` and identify likely commit boundaries. Mention those boundaries before making substantial edits.
- Commit after each coherent milestone when the repository is in a coherent state. Good boundaries include:
  - schema or model changes
  - core implementation
  - UI integration
  - tests
  - cleanup or documentation
- Do not batch unrelated changes into one commit.
- Only stage files that belong to the current milestone. Do not use `git add .` unless every changed file is known to belong to that milestone.
- Never include user-authored or pre-existing unrelated working-tree changes in a commit.
- Run relevant checks before committing when practical. If checks cannot run or are too expensive for the current turn, state that explicitly.
- Use concise commit messages that explain intent, for example `Add loudness task result builder tests` or `Persist study enrollment timestamps`.
- Do not squash, amend, rebase, push, force-push, or otherwise rewrite history unless the user explicitly asks.
- If Codex-generated commits are available, use them normally, but do not rely on that feature being enabled. Fall back to ordinary `git commit` commands when needed.

## Validation

- For general iOS changes, prefer:

  ```bash
  xcodebuild test -project TinniTrack.xcodeproj -scheme TinniTrack -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
  ```

- For quick compile validation when tests are unnecessary or too slow, use:

  ```bash
  xcodebuild build -project TinniTrack.xcodeproj -scheme TinniTrack -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
  ```

- If a simulator named above is unavailable, choose an available iOS Simulator from `xcrun simctl list devices available` and report the destination used.
- For database work, review the relevant SQL migration and any Swift code that depends on it together before committing.

## Safety

- Do not commit secrets, service-role keys, real participant data, private seed data, or generated local build products.
- Client code should only use anon/public Supabase credentials.
- Keep changes scoped to the requested task and the existing architecture. Avoid drive-by refactors unless they are needed to complete the work safely.
