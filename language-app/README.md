Language App
============

A shared SwiftUI app for iOS and macOS that studies CSV language decks with Anki's
FSRS schedule.

Decks are CSV files. The first column header is a BCP 47 language code for Apple's
speech synthesizer, such as `ja` or `es`; the second column is the answer. Japanese
furigana uses `word[reading]` notation, for example `日本語[にほんご]`: the app shows
the reading above the word, speaks it instead of the annotation, and shows romaji on
the answer side. `japanese.csv` and `anime.csv` hold a thousand phrases each, ordered
from the most common vocabulary down and introducing one new noun or verb per phrase,
polite Japanese in the first and casual anime dialogue in the second. `spanish.csv`
is a ten card sample. Bundled decks are copied into the app's documents directory on
first launch, and refreshed from the bundle while the copy is unedited.

## Studying

Each card speaks its prompt on a loop, so the toolbar button starts on Stop. The gear
menu picks any installed voice for the deck's language and sets a speaking speed from
0.5× to 2×, both taking effect on the next playback. Compact voices sound robotic;
enhanced and premium voices are downloaded through the system's Spoken Content
settings.

Each deck introduces up to a set number of unseen cards a day, 20 by default. Reviews
are never capped. The header counts new, again (cards on a same-day step) and review.
Once the day is finished, "Day completed!" offers extra cards for today only.

## Editing decks

Long pressing a deck offers "Inspect deck", "Reset progress" and "Delete deck", and
swiping a deck deletes it too. The plus button uploads a CSV deck or creates an empty
one by hand.

Inside a deck, cards appear in queue order and new cards are introduced from the top
down. Unstudied cards can be reordered, edited, added and removed. A card's identity
is its text, so studied cards stay locked until the deck's progress is reset.

## Building

```sh
bazel test //language-app/...
bazel build //language-app
bazel build //language-app:macos-app
bazel run //language-app:macos
bazel run //language-app:xcodeproj && xed language-app.xcodeproj
```
