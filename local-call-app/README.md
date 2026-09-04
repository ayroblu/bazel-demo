Local Call App
===============

An offline audio call app for nearby iPhones and Macs. It uses MultipeerConnectivity,
which connects devices directly over peer-to-peer wifi and bluetooth, so no
internet or shared network is required.

## How it works

* Discovery: pressing "Search for nearby devices" both advertises and browses
  for the `p2p-audio-call` bonjour service; discovery stops while the app is
  backgrounded and resumes on foreground if it was running. Tap a discovered
  device to invite it, the other side gets an accept/decline prompt.
* Audio: an `AVAudioEngine` mic tap is resampled to 16kHz mono Int16 PCM and
  written to an `MCSession` byte stream, one per direction, opened when the
  call connects. Received samples are scheduled onto an `AVAudioPlayerNode`,
  which plays its queue in order and never catches up on its own, so a stall
  or a clock difference would be added to the delay permanently. Past 200ms
  behind, playback speeds up smoothly to at most 1.08x through an
  `AVAudioUnitTimePitch`, which keeps the pitch and loses no words. Past a
  second behind it skips to the newest audio instead, because playing 8%
  faster would take a minute to absorb a five second stall.
* Ending: a call that ends for any reason plays a short descending two tone
  chime through the call's own route before the engine is torn down, so a
  drop is noticed without looking at the screen.
* Diagnostics: the Logs screen is backed by a sqlite table that survives
  relaunch (7 day retention). While connected, a heartbeat logs bytes sent and
  received, time since the last packet each way, playback backlog and drops,
  so a call that dies can be read back afterwards.
* Routing: calls follow the system default input and output until you pin a
  device in the in-call menu pickers; picking the device that currently is
  the default clears the pin, so the call follows future default changes
  (e.g. AirPods auto-switching) again. On iOS inputs come from
  `AVAudioSession.availableInputs` and the output picker offers
  automatic/speaker; on macOS both pickers list CoreAudio devices and pin the
  `AVAudioEngine` IO units directly. The engine restarts itself on
  `AVAudioEngineConfigurationChange` so switching devices mid-call keeps the
  audio flowing.

Two processes on one Mac can call each other without any devices, see
`harness/README.md`.

## Building

```sh
bazel build //local-call-app
bazel build //local-call-app:macos_app
bazel run //local-call-app:macos
bazel run //local-call-app:xcodeproj && xed local-call-app.xcodeproj
```

After updating Xcode, Bazel's cached toolchain config can point at SDKs that no
longer exist (errors like "SDK ... cannot be located" or "'<build>' is not an
available Xcode version"). Reset the caches and re-detect Xcode with:

```sh
bazel shutdown
bazel fetch --configure --force
# rules_xcodeproj uses a separate output base with its own server:
bazel --output_base=/private/var/tmp/_bazel_$USER/<workspace-hash>/rules_xcodeproj.noindex/build_output_base shutdown
bazel run //local-call-app:xcodeproj
```

The `<workspace-hash>` directory is visible in any failing build's error output,
or via `bazel info output_base` (it's the sibling `rules_xcodeproj.noindex`
directory).

MultipeerConnectivity and the microphone don't work in the iOS simulator, so run
the iOS app on physical devices. To install on a device, add a
`provisioning_profile` for the `com.ayroblu.local-call-app` bundle id to the
`ios_application` target, same as g1-app:

```
# cp ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/<uuid>.mobileprovision .
```

Both devices need wifi and bluetooth enabled (airplane mode with them toggled
back on is fine), and the app must be granted microphone and local network
permissions on first launch.
