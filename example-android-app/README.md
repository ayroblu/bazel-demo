Example Android App
===================

Make sure your emulator is running:

```
# Make sure you have the right paths setup (happens automatically in android dir)
# init-android
# emulator -list-avds
# emulator -avd Pixel_3a_API_34_extension_level_7_arm64-v8a -netdelay none -netspeed full
emulator -avd Pixel_3a_API_34_extension_level_7_arm64-v8a
```

Build

```
bazel build :example-android-app
```

Install app on device:

```
./install
```

### Source

Inspiration and reference for bazel config comes from: https://github.com/bazelbuild/rules_kotlin/tree/master/examples/jetpack_compose
