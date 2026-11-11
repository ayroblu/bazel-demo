# AltTab (modified fork)

This directory is a modified copy of [AltTab](https://github.com/lwouis/alt-tab-macos) by Louis Pontoise, based on upstream release [v11.10.1](https://github.com/lwouis/alt-tab-macos/releases/tag/v11.10.1).

It was modified on 11 November 2026. It is not the official AltTab and is not supported by the upstream project.

## Licence

Like upstream, this fork is licensed under the GNU General Public License v3.0. The full text is in [`LICENCE.md`](LICENCE.md).

## What was changed

- The licensing code is removed (licence checks, trial, upgrade prompts and screens), so the features upstream sells as AltTab Pro are always available. If you find them useful, consider [buying AltTab Pro](https://alt-tab.app/pricing) to support the author.
- The search hint that upstream shows during the trial is removed.
- The Sparkle auto-updater and all update settings are removed.
- The AppCenter crash reporter and its setting are removed.
- The Cancel shortcut may share its key with a shortcut that opens the switcher. For example, ⌘Esc can open it while Esc closes it.
- The app is built with Bazel instead of Xcode, under its own bundle ID (`com.ayroblu.alt-tab`).
- Only the app sources and bundled resources were copied. Upstream's release scripts, website, Xcode project and vendored libraries are left out.

## Build and install

Run these from the repository root:

```sh
bazel build -c opt //alt-tab-app
bazel run -c opt //alt-tab-app:install
```

The install command copies the app to `~/Applications/AltTab.app`, signs it, stops any running AltTab, and opens the new one. On first launch, grant it Accessibility and Screen Recording permissions.

The only third-party library is [ShortcutRecorder](https://github.com/lwouis/ShortcutRecorder), the control used to record keyboard shortcuts. Bazel fetches the AltTab author's fork of it at a pinned commit (`shortcut_recorder` in the root `MODULE.bazel`) and applies [`shortcut-recorder.patch`](shortcut-recorder.patch), which makes it load its images and translations from `ShortcutRecorder.bundle` inside the app.
