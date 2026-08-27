# AirPods Pro 2 Runtime Verification Findings

Last reviewed: 2026-08-26

## Summary

Public iOS APIs do not provide a trustworthy way for an App Store app to prove that the currently connected headphones are AirPods Pro 2. `AVAudioSession` can report the active audio route and some route metadata, but it does not expose AirPods model number, generation, serial number, firmware version, Bluetooth MAC address, noise-control mode, or a signed device identity.

For TinniTrack, AirPods Pro 2 should be treated as a study setup and eligibility requirement that is confirmed by the participant or researcher, then continuously checked at runtime with conservative audio-route guardrails. The app can verify that playback is currently routed through a compatible Bluetooth playback profile, but it cannot independently attest the exact headphone model.

## Implementation Status

The product now follows this trust boundary:

- The correct-ear step asks the participant to confirm that the current device is AirPods Pro 2.
- The confirmation is bound to the current A2DP route UID for the task attempt. If iOS supplies no UID, the app falls back to the exact route name for within-attempt correlation only.
- A matching confirmed route resolves the `AIRPODSPROV2` calibration identifier with the `.researchProtocol` source.
- Route names provide an advisory AirPods Pro family signal. The product conservatively requires that family signal together with participant confirmation; the name never proves generation or satisfies calibrated-profile verification on its own.
- `CalibratedAudioGuardrailPolicy` rejects `.routeNameHeuristic` as calibration proof.
- The app continues to require one A2DP output, maximum volume, and route/volume continuity.

## Public API Findings

### AVAudioSession

`AVAudioSession` is the correct public API for runtime audio-route checks. After activating a playback session, the app can inspect `AVAudioSession.sharedInstance().currentRoute.outputs`.

Useful fields from `AVAudioSessionPortDescription`:

- `portType`: route class such as `.bluetoothA2DP`, `.bluetoothHFP`, `.bluetoothLE`, `.headphones`, `.builtInSpeaker`, `.airPlay`, or `.carAudio`.
- `portName`: user-visible route name, often but not reliably the accessory name.
- `uid`: system-assigned route identifier. This may help correlate routes within the app, but it is not a stable hardware identity or model proof.
- `channels`: channel descriptions when available.

Useful session fields:

- `outputVolume`: current system output volume from `0.0` to `1.0`.
- `routeChangeNotification`: notification to detect route changes after a guardrail pass.

What `AVAudioSession` cannot verify:

- AirPods generation.
- AirPods model number.
- AirPods serial number.
- AirPods firmware.
- Bluetooth MAC address.
- Whether a Bluetooth A2DP route is definitely headphones rather than another Bluetooth audio device.
- Whether the route is physically in the participant's ears.

### CoreBluetooth

CoreBluetooth should not be used for this requirement. It is a Bluetooth Low Energy and GATT API, not a general Bluetooth Settings or audio-accessory inventory API. It cannot enumerate all connected Bluetooth audio devices or identify the current AirPods model.

### ExternalAccessory and AccessorySetupKit

ExternalAccessory is for MFi accessories and supported protocols. AccessorySetupKit is for accessory discovery/setup flows. Neither provides a general-purpose way to inspect connected AirPods or prove the active headphone model.

### CMHeadphoneMotionManager

`CMHeadphoneMotionManager` can be useful as a supporting signal. It can stream motion data from supported head-tracking audio products such as AirPods Pro and report connection state. This can help distinguish a compatible head-tracking headset from an arbitrary Bluetooth speaker in some cases.

It still does not prove AirPods Pro 2 specifically. It should be treated as capability evidence, not model identity.

### HealthKit

HealthKit headphone audio exposure data can support hearing-health context and retrospective exposure analysis. It does not provide live headphone model verification.

## Recommended Runtime Assessment

Implement runtime verification as an assessment with confidence levels rather than a boolean model check.

Route assessment levels:

- `failed`: route is absent or incompatible.
- `compatibleBluetoothPlaybackRoute`: exactly one Bluetooth A2DP output is active.
- `likelyAirPodsProRoute`: A2DP output is active and the route name looks like AirPods Pro.
- `likelyAirPodsProCommunicationRoute`: an AirPods Pro-like route is active through HFP call/headset audio rather than A2DP playback.

Model confirmation is tracked separately from route assessment. A `ResearchProtocolHeadphoneRouteConfirmation` records the expected calibration identifier and the route UID (or exact route name fallback) that the participant confirmed during onboarding or pre-task setup.

For calibrated playback tasks, require:

- exactly one active output,
- output port type is `.bluetoothA2DP`,
- required system volume policy passes,
- route and volume remain unchanged after verification,
- participant or researcher AirPods Pro 2 confirmation is present.

The route name is an advisory AirPods Pro family signal and must not be the sole basis for passing the AirPods Pro 2 requirement because users can rename AirPods and other devices can use misleading names. TinniTrack conservatively combines that family signal with an explicit route-bound generation confirmation.

## AVAudioSession Checks

At runtime, check:

1. Activate a playback audio session before reading route data.
2. `currentRoute.outputs.count == 1`.
3. The only output has `portType == .bluetoothA2DP`.
4. Reject `.bluetoothHFP` because it is the headset/call profile, not the calibrated high-quality playback route.
5. Reject `.bluetoothLE` unless a separate validation phase proves it is acceptable for the calibration profile.
6. Inspect `portName` for AirPods-like wording only as a weak heuristic.
7. Capture `uid` for audit/correlation, but do not use it as hardware proof.
8. Capture `channels` when available.
9. Validate `outputVolume` against the calibration policy.
10. Observe route and volume changes during the task; require restart if either changes after guardrails pass.

Suggested Swift shape:

```swift
struct HeadphoneRouteAssessment: Equatable {
    let level: HeadphoneVerificationLevel
    let outputCount: Int
    let portName: String?
    let portType: AVAudioSession.Port?
    let routeUID: String?
    let channelNames: [String]
    let outputVolume: Double?
    let issues: [HeadphoneRouteIssue]
}

enum HeadphoneVerificationLevel: String, Equatable {
    case failed
    case compatibleBluetoothPlaybackRoute
    case likelyAirPodsProRoute
    case likelyAirPodsProCommunicationRoute
}

struct ResearchProtocolHeadphoneRouteConfirmation: Equatable {
    let headphoneIdentifier: String
    let portUID: String?
    let portName: String
    let confirmedAt: Date
}
```

## Participant and Researcher Messages

Use plain participant-facing messages for recoverable setup issues.

No output:

> Connect AirPods Pro 2, select them as the audio output, then check again.

Built-in speaker or receiver:

> Audio is playing through the iPhone. Select AirPods Pro 2 in Control Center.

Wired headphones, USB audio, AirPlay, or car audio:

> This task requires AirPods Pro 2. Current output is not an AirPods Bluetooth playback route.

Bluetooth HFP:

> Your AirPods are connected in call/headset mode, not calibrated playback mode. End calls or recording sessions, reconnect AirPods, then check again.

Bluetooth A2DP, but route name does not look like AirPods Pro:

> Bluetooth playback is active, but the selected route is not identified as AirPods Pro. Select the AirPods Pro route, then check again.

AirPods Pro-like route name:

> AirPods Pro playback route detected. Confirm these are AirPods Pro 2 before continuing.

Manual model confirmation:

> Check Settings > Bluetooth > AirPods > Info. AirPods Pro 2 model numbers are A2931, A2699, A2698, A3047, A3048, or A3049.

Route changed after verification:

> Audio route changed after verification. Restart this task before playback.

Volume changed after verification:

> System volume changed after verification. Set volume back to the required level and restart this task.

## Recommended Study Data to Log

For each calibrated task attempt, the study protocol should log:

- verification level,
- participant/researcher confirmation source,
- confirmation timestamp,
- route output count,
- route `portType`,
- route `portName`,
- route `uid` or a privacy-preserving hash,
- channel names,
- output volume,
- route-change events,
- volume-change events,
- guardrail pass/fail reason,
- task restart requirement.

Do not log serial numbers or participant-entered model numbers unless the IRB/protocol explicitly requires it. If model numbers are collected, store only the selected model code or confirmation status, not screenshots.

The current payload records the resolved calibration identifier and `.researchProtocol` verification source, but not the confirmation actor or timestamp. Those fields remain future schema work.

## SensorKit Findings

SensorKit is a plausible research-only route for collecting additional audio-related context, but not for proving AirPods Pro 2 identity.

Apple requires:

- an Apple-approved research study,
- the private `com.apple.developer.sensorkit.reader.allow` entitlement,
- user permission,
- study-specific approval and App Store review.

SensorKit includes an `SRSensor.acousticSettings` stream in current Apple documentation. Public snippets indicate it can expose acoustic settings such as headphone safety audio level, environmental sound measurement state, and music EQ settings. This could help identify confounders for calibrated tinnitus workflows, including:

- Headphone Accommodations,
- music EQ,
- headphone safety level,
- environmental sound measurement settings.

Do not assume SensorKit exposes connected headphone model identity. If TinniTrack pursues SensorKit, the recommended scope is a separate entitlement spike focused on acoustic-settings confounders, not headset attestation.

## Recommended Product Approach

1. Add or preserve a manual AirPods Pro 2 confirmation step in onboarding or pre-task setup.
2. Guide the participant to Apple Settings to confirm model number:
   - A2931, A2699, A2698 for AirPods Pro 2 with Lightning case.
   - A3047, A3048, A3049 for AirPods Pro 2 with USB-C case.
3. Use `AVAudioSession` as the required live runtime gate.
4. Treat `portName` as advisory only.
5. Require task restart whenever route or volume changes after passing guardrails.
6. Store verification metadata with each calibrated task payload.
7. Optionally evaluate `CMHeadphoneMotionManager` as a supporting capability signal.
8. Evaluate SensorKit only if acoustic-settings confounders are important enough to justify Apple research entitlement work.

## Sources

- Apple Developer Documentation: `AVAudioSession.Port`
  https://developer.apple.com/documentation/avfaudio/avaudiosession/port
- Apple Developer Documentation: `AVAudioSessionPortDescription`
  https://developer.apple.com/documentation/avfaudio/avaudiosessionportdescription
- Apple Developer Documentation: Responding to audio route changes
  https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes
- Apple Developer Documentation: SensorKit
  https://developer.apple.com/documentation/sensorkit
- Apple Developer Documentation: SensorKit entitlement
  https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.sensorkit.reader.allow
- Apple Developer WWDC23: What's new in Core Motion
  https://developer.apple.com/videos/play/wwdc2023/10179/
- Apple Support: Identify your AirPods
  https://support.apple.com/en-us/109525
