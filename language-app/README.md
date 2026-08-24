Language App
============

A shared SwiftUI app for iOS and macOS that studies CSV language decks with an
FSRS spaced-repetition schedule.

The home screen lists every CSV bundled from `decks/`. The sample Japanese and
Spanish decks each contain ten beginner cards. The first column header is a BCP
47 language code used by Apple's speech synthesizer, such as `ja` or `es`; the
second column is the answer. Japanese furigana uses
`word[reading]` notation, for example `日本語[にほんご]`. The app displays the
reading above the word and speaks the reading instead of the annotation.

Speech uses the system voice for the language code in the deck header.

## Building

```sh
bazel test //language-app/content:content-tests
bazel build //language-app
bazel build //language-app:macos-app
bazel run //language-app:macos
bazel run //language-app:xcodeproj && xed language-app.xcodeproj
```
