Example Android App
===================

## Get Started

Make sure your emulator is running:

```
# Make sure you have the right paths setup (happens automatically in android dir)
# init-android
# emulator -list-avds
# emulator -avd Pixel_3a_API_34_extension_level_7_arm64-v8a -netdelay none -netspeed full
emulator -avd Medium_Phone_API_35
```

Build

```
bazel build :example-android-app
```

Install app on device:

```
# Doesn't work anymore?
# ./install
bazel mobile-install:android //example-android-app -- --launch_activity=com.example.bazel.MainActivity
```

## Helpful

Toggle dark mode:

```
adb shell "cmd uimode night yes"
adb shell "cmd uimode night no"
```

Setup Android Studio

- https://www.kodeco.com/31558158-building-with-bazel/lessons/16

## Source

Inspiration and reference for bazel config comes from: https://github.com/bazelbuild/rules_kotlin/tree/master/examples/jetpack_compose
