Live Bus App
============

Live London bus map, modelled on
[traintimes.org.uk/map/london-buses](https://traintimes.org.uk/map/london-buses).
The map opens on your location with nearby bus stops. Tap a stop for live
arrivals, or choose a route to see its live buses moving along the road.

Data comes from the [TfL Unified API](https://api.tfl.gov.uk), anonymously.
TfL publishes arrival predictions, not GPS positions. Each bus is placed on
the route's road geometry by interpolating between its previous stop and its
predicted arrivals, recalculated every second and refreshed from TfL every
30 seconds.

All ~21k bus stops are downloaded once (33 pages from `/StopPoint/Mode/bus`,
about 2 MB compressed) into `Library/Caches/bus-stops.json`, so panning the
map filters stops locally. TfL has no stop-change feed, so the cache is
re-downloaded in the background once it is a week old.

## Building

```sh
bazel build //live-bus-app
bazel run //live-bus-app:xcodeproj && xed live-bus-app.xcodeproj
```

Deep links open a route or a stop, like traintimes' `#73` links:

```sh
xcrun simctl openurl booted livebus://route/73
xcrun simctl openurl booted livebus://stop/490000129D
```

In the simulator, set a London location first:

```sh
xcrun simctl location booted set 51.5308,-0.1238
```

Run on a device

```sh
bazel run --config=ios --ios_device=iphone //live-bus-app
```

## Release

Uploading needs an App Store Connect app record for `com.ayroblu.live-bus-app`.

```sh
bazel build --config=release //live-bus-app
xcrun altool --upload-app -t ios -f .bazel/bin/live-bus-app/live-bus-app.ipa \
  --api-key KPYMMWTY9J --api-issuer ef034221-c8c3-40ae-8796-137fa43bcc81
```
