# Loudness Match Cycle Ring Design Guidance

Date: 2026-06-24

## Purpose

This document describes the target UI and behavior for the loudness matching active-test screen. The screen is used during a tinnitus loudness match: the app plays repeated tones, the participant adjusts the tone louder or softer until it matches the perceived loudness of their tinnitus, and then accepts the match.

The selected design uses a centered vertical control stack with the Play button as the interaction anchor. When tones are actively playing, the Play button shows a subtle circular cycle indicator that restarts with each repeated tone.

## Visual Structure

The screen should feel calm, clinical, and spacious. Use a white background, dark primary text, muted gray supporting text, blue primary actions, red louder controls, and green softer controls. The layout should be vertically centered and symmetrical, with generous whitespace and the Play button acting as the central anchor.

At the top of the screen, show the normal iOS status area. Below it, place a circular back button at the upper left and a circular close button at the upper right. Both should be light gray circular controls with thin gray outlines and black icons.

Centered between those controls, show the trial label:

```text
Trial 1 of 3
```

Directly below the label, show a horizontal three-step progress indicator. It contains three numbered circles: `1`, `2`, and `3`. The current trial circle is filled blue with white text. Upcoming trial circles are white with gray outlines and dark text. Thin connector lines run between the circles. The completed or active segment is blue; remaining segments are gray.

Below the progress indicator, center the main heading:

```text
Match the loudness
```

Use a large, bold, dark type style. Under the heading, show centered instructional copy in a softer gray-blue color:

```text
Adjust the tone until it sounds as loud
as your tinnitus, then accept the match.
```

Below the instructions, show a centered tone readout. A small muted label reads:

```text
Tone level
```

Under that label, show the current candidate level prominently:

```text
70 dB HL
```

The numeric value should be large, bold, and bright blue. It should be the main data point on the screen.

## Adjustment Stack

The adjustment controls are arranged vertically around the central Play button:

1. `Much Louder`
2. `Louder`
3. Play button
4. `Softer`
5. `Much Softer`

The stack should be centered on the screen. Button text should be visually centered inside each button. Adjustment icons should sit in a consistent left icon column across all four adjustment buttons, so the chevrons align vertically even though the text remains centered.

### Much Louder

The `Much Louder` button sits above `Louder` and is the larger louder control. It uses a pale red background, red border, and red text. The left icon is a double upward chevron, communicating a larger increase in tone level.

This button should be wider and taller than `Louder`, with a slightly stronger red tint and stronger visual emphasis.

### Louder

The `Louder` button sits below `Much Louder` and above the Play button. It uses the same red color family, but the background and border should be softer and lighter than `Much Louder`.

The left icon is a single upward chevron. The button should be slightly narrower and shorter than `Much Louder`, making the small-step action visually distinct from the large-step action.

### Play Button

The Play button sits in the center of the adjustment stack. It is a white circle with a medium-thick blue outline. Inside the circle, show a filled blue play triangle.

This button is the visual and behavioral center of the screen. The tone-playback animation originates from this button only.

### Softer

The `Softer` button sits below the Play button. It matches the size and emphasis of `Louder`, using a pale green background, soft green border, and green text.

The left icon is a single downward chevron in the same left icon column as the louder controls. The text remains centered.

### Much Softer

The `Much Softer` button sits below `Softer` and is the larger softer control. It matches the emphasis of `Much Louder`, using a slightly stronger green tint and border than `Softer`.

The left icon is a double downward chevron in the same left icon column. The text remains centered.

## Same Loudness Button

At the bottom of the screen, show the primary confirmation button:

```text
Same Loudness
```

This button should be a large blue pill-shaped button spanning most of the available width with comfortable horizontal margins. Use white centered text. Do not include a checkmark or any other icon.

The button accepts the current tone level as the participant's loudness match and advances the flow.

## Tone Playback Animation

The selected animation concept is called `Cycle Ring`.

When tones are actively playing, the Play button should show a subtle circular cycle indicator. The goal is to confirm that a sound is playing and to communicate the repeated two-second cadence without adding visual noise.

The animation should behave as follows:

- At the start of each tone playback cycle, a thin circular track appears around the outside edge of the Play button.
- The full circular track is very faint blue.
- A brighter short blue arc travels clockwise around the circle.
- The arc starts near the top of the button and completes one revolution over roughly two seconds.
- When the next tone cycle begins, the arc restarts from the beginning.
- The animation is localized to the Play button. It should not expand into or visually compete with the louder and softer buttons.
- The Play button may receive a very soft inner blue tint or subtle light pulse at the start of each tone, but it should remain mostly white and crisp.
- The animation should feel measured, precise, and clinical. It should not feel playful, flashy, or alarming.

The participant should be able to infer two things from the animation:

1. The tone is currently active.
2. The tone repeats on a predictable rhythm.

## Interaction Behavior

The intended flow is:

1. The participant taps Play.
2. The app plays a tone every two seconds.
3. The Cycle Ring animation starts when playback starts and repeats on the same two-second cadence.
4. The participant adjusts the tone using the red louder controls or green softer controls.
5. The displayed `dB HL` value updates as the candidate tone level changes.
6. When the played tone matches the perceived loudness of the tinnitus, the participant taps `Same Loudness`.
7. The app accepts the match and continues to the next step in the loudness-match flow.

If playback is stopped or unavailable, the Cycle Ring animation should not run. If the app shows a stopped state inside the central control, preserve the same circular placement and avoid reintroducing a separate Stop button row.

## Accessibility And Usability Requirements

- Keep touch targets large enough for comfortable mobile use.
- Preserve readable text sizes and high contrast.
- Do not rely on color alone to distinguish large versus small adjustments. Use both color intensity and icon count: double chevrons for much louder/softer, single chevrons for louder/softer.
- Keep the animation subtle enough that it does not distract participants while they are listening.
- Ensure VoiceOver labels clearly identify each adjustment action, the current tone level, the Play control, and the Same Loudness confirmation action.
- Respect Reduce Motion where practical. For reduced motion, replace the sweeping arc with a static or gently fading ring that indicates active playback without continuous motion.

## Likely Implementation Surface

The active-test UI currently lives in:

```text
TinniTrack/Features/LoudnessMatch/Views/LoudnessMatchActiveTestView.swift
```

Shared modal colors and controls currently live in:

```text
TinniTrack/Features/LoudnessMatch/Views/LoudnessMatchModalControls.swift
```

Follow the existing feature-first structure and avoid importing ResearchKit directly into feature UI code.
