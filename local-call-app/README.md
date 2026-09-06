Local Call App
===============

An offline audio call app for nearby iPhones and iPads. Signalling runs over
bluetooth LE and audio over peer-to-peer wifi, so no internet or shared
network is required. The wifi radio does have to be on, because peer-to-peer
wifi is what carries the audio between devices that share no network.

## How it works

* Paired calling (iOS): the `connect` module keeps a small bluetooth LE
  service advertised at all times, which iOS keeps doing in the background and
  restores after termination, so a write from a paired device relaunches the
  app and rings it through CallKit with no button pressed on either side.
  Pair once from the lobby while both apps are open; after that a paired
  device shows as in range and can be called straight away. Scanning is the
  expensive half of bluetooth and only runs in the foreground, which is where
  a caller always is. Once the call is answered the audio runs over the wifi
  transport: the bluetooth link only carries invite, cancel, answer, decline,
  busy and silenced, each signed with the secret exchanged at pairing.
  CallKit owns the audio session for these calls, so the engine starts when it
  hands the session over and stops when it takes it back.
* Discovery: the `p2p-audio-call` bonjour service is advertised and browsed
  only while a call is being set up, and a connection is accepted only from
  the peer the bluetooth side named. There is no manual device list: a device
  has to be paired before it can be called.
* Audio: an `AVAudioEngine` mic tap with voice processing on, for the system's
  echo cancellation and automatic gain control, is resampled to 16kHz mono
  Int16 PCM and written to an `NWConnection` carrying both directions. It is
  a TLS connection keyed by a pre-shared key built into the app, which
  encrypts the call without authenticating the peer. Received samples are
  scheduled onto an `AVAudioPlayerNode`,
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
  (e.g. AirPods auto-switching) again. Inputs come from
  `AVAudioSession.availableInputs` and the output picker offers
  automatic/speaker. The engine restarts itself on
  `AVAudioEngineConfigurationChange` so switching devices mid-call keeps the
  audio flowing.

## Modules

| Module | Holds |
|---|---|
| `connect` | Bluetooth LE signalling, pairing and CallKit |
| `transport` | The peer-to-peer wifi connection carrying call audio |
| `audio` | The engine, routing and the disconnect chime |
| `content` | SwiftUI views and `CallViewModel`, which wires the other three |

`connect` depends on neither `transport` nor `audio`: it reports what a call
needs through callbacks that `CallViewModel` connects up, so the three can be
built and tested on their own.

## Building

```sh
bazel build //local-call-app
bazel test //local-call-app/connect/tests //local-call-app/transport/tests \
  //local-call-app/audio/tests --ios_multi_cpus=sim_arm64
bazel run //local-call-app:xcodeproj && xed local-call-app.xcodeproj
```

The app is iOS and iPadOS only: CallKit does not exist on macOS. Most modules
only build in an iOS configuration, so name test targets explicitly rather
than using `//local-call-app/...`. Tests run on a simulator rather than the
host, which is what `--ios_multi_cpus=sim_arm64` selects: without it they
build for macOS and fail on `UIKit`, and `--config=ios` builds for a device
whose bundle the simulator then refuses to load.

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

Peer-to-peer wifi, bluetooth and the microphone don't work in the
simulator, so run the app on physical devices. To install on a device, add a
`provisioning_profile` for the `com.ayroblu.local-call-app` bundle id to the
`ios_application` target, same as g1-app:

```
# cp ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/<uuid>.mobileprovision .
```

Both devices need wifi and bluetooth enabled (airplane mode with them toggled
back on is fine), and the app must be granted microphone and local network
permissions on first launch. Local network permission cannot be granted from
the background, so the app has to be opened once before paired calling works.
Force quitting the app also stops it being relaunched for a call, which is a
system rule no background mode gets around.
