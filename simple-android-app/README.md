Sipmle Android App
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

Build (:android is very important, otherwise jni will not work)

```
bazel build:android :simple-android-app
```

Install app on device:

```
# Doesn't work anymore?
# ./install
bazel mobile-install:android //simple-android-app -- --launch_activity=com.simple.bazel.MainActivity
```

## Info

For this commit: 2026-01-04, app with build:android:opt is 1.5MB and build:android is 11MB

## Helpful

Toggle dark mode:

```
adb shell "cmd uimode night yes"
adb shell "cmd uimode night no"
```

Setup Android Studio

> https://www.kodeco.com/31558158-building-with-bazel/lessons/16

1. Download and setup Android Studio
2. Android Studio -> Preferences -> plugins -> search "Bazel" -> install
3. Close project -> project selection -> three buttons next to the open button -> Import a Bazel Project
4. Select folder
5. Select import from BUILD and select your BUILD file
6. Enable kotlin (uncomment), and then done
7. In the Bazel menu, enable analysis for working set
8. menu -> Bazel -> Build -> Compile Project

## Source

Inspiration and reference for bazel config comes from: https://github.com/bazelbuild/rules_kotlin/tree/master/examples/jetpack_compose
