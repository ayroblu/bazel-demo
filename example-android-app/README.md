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

Build (:android is very important, otherwise jni will not work)

```
bazel build:android :example-android-app
```

Install app on device:

```
# Doesn't work anymore?
# ./install
bazel mobile-install:android //example-android-app -- --launch_activity=com.example.bazel.MainActivity
```

View logs:

```
# -c to clear logs
# adb logcat -c
adb logcat | grep --line-buffered "Bazel"
```

View crash logs:

```
adb logcat --buffer=crash
```

## Info

For this commit: 2026-01-04, apk with build:android:opt is 18MB and build:android is 21MB

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

### JNI

Note that the JNI (especially by uniffi) is done by placing the libexample.so in the apk under lib/arm64-v8a/libjnidispatch.so and lib/arm64-v8a/libexample_lib.so

## Source

Inspiration and reference for bazel config comes from: https://github.com/bazelbuild/rules_kotlin/tree/master/examples/jetpack_compose
