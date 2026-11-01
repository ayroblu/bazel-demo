Local Call App
===============

Offline audio calls between nearby iPhones and iPads. Signalling over
bluetooth LE, audio over a bluetooth L2CAP channel or peer-to-peer wifi.

## Modules

| Module | Holds |
|---|---|
| `bluetooth` | BLE signalling, pairing, L2CAP channel API |
| `call` | Call state machine and CallKit |
| `transport-protocol` | `DatagramCarrier`, `LinkSetup` |
| `awdl` | Bonjour discovery, DTLS datagrams |
| `l2cap` | L2CAP channel setup, sealed stream carrier |
| `transport` | Call protocol (hello, keepalive, RTT) over the mode's link |
| `audio` | Engine, routing, chime |
| `content` | SwiftUI, `CallViewModel` |

`transportMode` in `transport/transport-mode.swift` selects `awdl` or `l2cap`
at compile time; both devices must run the same mode.

## Building

```sh
bazel build //local-call-app
bazel test //local-call-app/bluetooth/tests //local-call-app/transport/tests \
  //local-call-app/audio/tests --ios_multi_cpus=sim_arm64
bazel run //local-call-app:xcodeproj && xed local-call-app.xcodeproj
```

iOS only. Name test targets explicitly: `//local-call-app/...` builds for
macOS and fails on `UIKit`; `--config=ios` builds a device bundle the
simulator refuses.

After an Xcode update, if Bazel reports a missing SDK or Xcode version:

```sh
bazel shutdown
bazel fetch --configure --force
bazel --output_base=/private/var/tmp/_bazel_$USER/<workspace-hash>/rules_xcodeproj.noindex/build_output_base shutdown
```

Radios and the microphone need physical devices. Provisioning profile for
`com.ayroblu.local-call-app`:

```
cp ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/<uuid>.mobileprovision .
```

The app must be opened once to grant microphone and local network permission
before background calling works. A force-quit app is not relaunched for calls.

## Release

```sh
bazel build:release local-call-app
xcrun altool --upload-app -t ios -f .bazel/bin/local-call-app/local-call-app.ipa \
  --api-key KPYMMWTY9J --api-issuer ef034221-c8c3-40ae-8796-137fa43bcc81
```
