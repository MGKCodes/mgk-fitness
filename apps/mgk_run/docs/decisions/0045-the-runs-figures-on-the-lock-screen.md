# 0045 — A run's figures are on the lock screen, drawn natively

**Status:** Accepted, 2026-10-01.

## Context

A phone in an armband is a locked phone. The in-run screen has the distance,
the time and the pace, and for the whole of every run all three were behind a
passcode. Asked for at the first look at build 28: "if your phone is locked
you can see a distance, time and pace stat ... when a run is active".

Neither platform lets a Flutter app draw on the lock screen. On the iPhone the
thing that can is a Live Activity, which a separate widget extension draws in
SwiftUI. On Android it is a notification.

## Decision

- **One small interface, `LiveRunReadout`, and a recorder that feeds it.**
  `LiveReadoutRecorder` wraps the real recorder and tells the readout the
  distance and the pace every four seconds, and at once when the runner pauses
  or resumes. Around the recorder, not inside the in-run screen: the screen is
  exactly what is not there when the phone is locked. It refreshes when a fix
  arrives, because a locked iPhone stops an app's timers and keeps delivering
  location.
- **The clock counts natively.** The app says how long the run has been going
  and each platform counts on from there by itself, every second: SwiftUI's
  timer text on the iPhone, the notification's chronometer on Android. Paused,
  it stands still.
- **The app's own platform channel, not a plugin.** The packages that do Live
  Activities want an App Group and a shared store to pass the figures across.
  ActivityKit carries them itself, so the extension needs neither: no new
  capability on the App ID and no entitlement. The native side is about 120
  lines of Swift and 120 of Kotlin.
- **On the iPhone, a widget extension: `RunLiveActivity`.** Lock screen and
  Dynamic Island. It ships inside the app, has its own bundle id
  (`com.mgkcodes.fitness.run.RunLiveActivity`) and needs its own provisioning
  profile. iOS 16.2 and later; the app itself still runs on 15.
- **On Android, a second notification.** The location plugin's own "Recording
  your run" notification cannot carry this: the plugin makes its channel with
  no importance and private visibility, a lock screen will not show that, and
  a channel's importance cannot be changed once made. So the app posts its own
  on a quiet public channel, and asks for the notification permission once, on
  the way to the start screen.
- **Never the reason a run fails.** Every call is caught. Live Activities
  switched off, notifications refused, a phone too old for either: the run is
  recorded exactly as before.

## What it costs

- **A second iOS target that no machine here can build.** The extension was
  written and added to the Xcode project by hand, on Windows, and the first
  thing that compiled it was Codemagic. A change to it is a change nobody can
  check before a build.
- **A second provisioning profile**, with the same expiry discipline as the
  first ([store-setup.md](../store-setup.md) §11).
- **A permission prompt on Android 13 and later**, the first time a runner
  goes to start a run. It closes a known gap: until now the app never asked,
  so the recording notification was hidden unless the runner found the
  setting.
- **Two notifications on Android while a run records**: the plugin's, which
  the foreground service must have, and this one.

## What it does not do

No buttons. Pause and Finish stay in the app: a control on a lock screen is a
control a pocket can press.

It does not survive the app being killed. A Live Activity left behind by a
run the phone killed is ended when the next run starts, and the recovered run
is still found on disk as before (rule 1).

## Disconfirming condition

The sitting. If the Live Activity does not appear, lags the run by more than a
few seconds with the phone locked, or the iPhone build cannot be signed with
the extension in it, this comes out of 1.0.0 by passing no readout in
`main.dart`, and goes to 1.0.1 with a Mac to build it on.
