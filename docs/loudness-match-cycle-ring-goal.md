# Codex Goal: Loudness Match Cycle Ring UI

Date: 2026-06-24

## Codex Docs Notes

The Codex manual describes `/goal` as a persistent objective that Codex works toward until the task is complete or needs more input. The goal text acts as both the starting prompt and completion criteria, so it should include a concrete outcome and measurable success conditions.

The manual also notes that goal objectives are limited to 4,000 characters in the CLI. For longer instructions, put the details in a file and point the goal at that file. This goal keeps the implementation target concise and references the detailed design guidance in:

```text
docs/loudness-match-cycle-ring-design-guidance.md
```

## Paste-Ready `/goal`

```text
/goal Implement the selected Cycle Ring redesign for the loudness matching active-test screen. Use docs/loudness-match-cycle-ring-design-guidance.md as the source of truth for visual layout, button hierarchy, colors, icon alignment, playback animation behavior, accessibility expectations, and likely implementation files.

Scope the work to the loudness-match active-test UI. Preserve the existing feature-first architecture and do not import ResearchKit into feature UI code. Update the ready-for-trial state so the screen uses a centered vertical stack: trial label and 1-2-3 progress indicator, centered title/instructions/tone readout, red Much Louder and Louder controls above a central circular Play control, green Softer and Much Softer controls below it, and a bottom Same Loudness pill button without an icon.

Implement the Play control's active playback indicator as a subtle Cycle Ring: a faint circular track around the Play button with a brighter blue arc that sweeps clockwise and restarts on the tone cadence, approximately every 2 seconds. The animation must originate from the Play button, stay localized, stop when playback is not active, and respect reduced-motion users with a lower-motion active state.

Success criteria:
- The current awkward Play/Stop row and 2x2 louder/softer grid are replaced by the centered vertical control stack described in the guidance doc.
- Louder/Softer are slightly smaller and softer in color than Much Louder/Much Softer.
- Adjustment labels are visually centered, while all adjustment icons align to a consistent left icon column.
- Same Loudness has centered text only, with no checkmark or leading icon.
- The Cycle Ring visibly indicates active repeated tone playback without overwhelming the listening task.
- VoiceOver labels, disabled states, and reduced-motion behavior are handled.
- Relevant SwiftUI previews or tests/build checks are run when practical, using the TinniTrack Local Dev simulator scheme for simulator validation.
- Only files belonging to this UI implementation are staged and committed; leave pre-existing unrelated working-tree changes untouched.
```
