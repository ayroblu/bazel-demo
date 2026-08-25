Language App
============

A shared SwiftUI app for iOS and macOS that studies CSV language decks with an
FSRS spaced-repetition schedule.

The home screen lists every CSV bundled from `decks/`. Two Japanese decks hold a
thousand phrases each, ordered from the most common vocabulary down, every phrase
introducing one new noun or verb: `japanese.csv` teaches general polite Japanese,
while `anime.csv` teaches the plain casual speech of anime dialogue and weights
its later cards towards emotion, conflict and genre vocabulary instead of news
and business. The Spanish deck is a ten card sample. The
first column header is a BCP 47 language code used by Apple's speech synthesizer, such as `ja` or `es`; the
second column is the answer. Japanese furigana uses
`word[reading]` notation, for example `日本語[にほんご]`. The app displays the
reading above the word and speaks the reading instead of the annotation. For
Japanese decks the answer side also shows romaji derived from those readings, so
no extra CSV column is needed.

The gear menu lists every installed voice that speaks the deck's language, with
its gender and quality tier, and remembers the choice per language. Without a
choice the app picks the best sounding voice it can find, preferring male and
higher quality. Compact voices sound robotic; enhanced and premium voices are
downloaded through the system's Spoken Content settings. Each card
starts speaking its prompt automatically and repeats it with a one second pause
between repeats, so the toolbar button starts on Stop; pressing Play after Stop
restarts the phrase from the beginning.

Long pressing a deck on the home screen offers "Reset progress", which asks for
confirmation and then makes every card in that deck new again. The same action is
available from the gear menu while studying a deck.

## Daily queue

Each deck introduces up to a set number of unseen cards a day, 20 by default,
changed in the gear menu. Reviews are never capped. The header counts today's
work as new, again (cards on a same-day step) and review.

Finishing everything the day holds shows "Day completed!" with a number field
and a button that releases extra cards for today only; leaving the deck and
coming back shows it again until the next day resets the count.

## Scheduling

Scheduling follows Anki's setup: new cards walk fixed learning steps of 1m and
10m, lapsed cards walk a 10m relearning step, and FSRS-5 tracks stability and
difficulty to pick every interval of a day or longer at 90% requested retention.
Again returns a card to the first step, Hard repeats the current step (the
average of the first two steps on step one), Good advances a step and then
graduates, and Easy graduates immediately.

## Building

```sh
bazel test //language-app/content:content-tests
bazel build //language-app
bazel build //language-app:macos-app
bazel run //language-app:macos
bazel run //language-app:xcodeproj && xed language-app.xcodeproj
```
