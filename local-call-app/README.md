Local Call App
===============

An offline audio call app for nearby iPhones and Macs. It uses MultipeerConnectivity,
which connects devices directly over peer-to-peer wifi and bluetooth, so no
internet or shared network is required.

## How it works

* Discovery: each device both advertises and browses for the
  `p2p-audio-call` bonjour service. Tap a discovered device to invite it, the
  other side gets an accept/decline prompt.
* Audio: an `AVAudioEngine` mic tap is resampled to 16kHz mono Int16 PCM,
  chunked to stay under the datagram MTU, and sent as unreliable datagrams
  over the `MCSession`. Received packets are scheduled onto an
  `AVAudioPlayerNode`.
* Routing: during a call you can pick the microphone from
  `AVAudioSession.availableInputs` (e.g. phone mic instead of airpods mic),
  toggle the speakerphone, and pick any output (airpods, etc.) via the system
  route picker.

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
