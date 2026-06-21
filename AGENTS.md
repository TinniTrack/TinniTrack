# AGENTS.md

## Project Context

- This is an iOS research app for tinnitus study workflows, built with SwiftUI, HealthKit, Apple ResearchKit embedded dynamic frameworks, and Supabase.

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
- Use concise commit messages that explain intent.
- Do not squash, amend, rebase, push, force-push, or otherwise rewrite history unless the user explicitly asks.
- If Codex-generated commits are available, use them normally, but do not rely on that feature being enabled. Fall back to ordinary `git commit` commands when needed.
