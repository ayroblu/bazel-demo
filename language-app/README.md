Language App
============

A shared SwiftUI app for iOS and macOS that studies CSV language decks with Anki's
FSRS schedule.

Decks are CSV files. The first column header is a BCP 47 language code for Apple's
speech synthesizer, such as `ja` or `es`; the second column is the answer. Japanese
furigana uses `word[reading]` notation, for example `日本語[にほんご]`: the app shows
the reading above the word, speaks it instead of the annotation, and shows romaji on
the answer side. Wrapping part of a prompt in `**` marks the word the card teaches, as
in `俺[おれ]は**強[つよ]い**`; the app shows it bold and underlined and drops the
asterisks everywhere else. Bundled decks are copied into the app's documents directory
on first launch, and refreshed from the bundle while the copy is unedited.

## Included decks

`slime.csv` is a thousand phrases of casual anime dialogue from *That Time I Got
Reincarnated as a Slime*; `spanish.csv` is a thousand beginner Spanish phrases.
`spanish.csv` is the better model to copy. Both follow the same recipe:

- Start from a frequency-ordered wordlist of a thousand words, counted over a corpus
  that matches the deck: the show's own subtitles for `slime.csv`, Spanish subtitles at
  large for `spanish.csv`. Most common first.
- One card per word, in that order: card *i* teaches word *i*, so the deck is a
  thousand lines plus the header.
- A word is a form, not a dictionary entry. Every conjugation is its own card.
- i+1: apart from the one new word, every content word in the phrase must already have
  been taught on an earlier line. Grammar is free — particles, articles, pronouns,
  prepositions, the copula, and conjugation endings never count as vocabulary.
- The prompt is a real phrase or short sentence someone would say, 2–6 words, never a
  bare word. Vary the shape: questions, replies, exclamations. The first cards have
  almost no vocabulary to lean on, so keep them very short.
- Exactly one `**bold**` span per line, marking the new word as it is spelled in the
  wordlist, conjugation and furigana included.
- The answer field is `translation; note`. The translation is natural English for the
  whole phrase, not word by word.
- The note is one sentence of at most 16 words: what kind of word it is, then what it
  means, then the nuance the translation loses — register, how wide the meaning is,
  what a compound literally says, how this show uses it. It must never restate the
  translation, compare the word to one the learner has not met, or discuss spelling or
  pronunciation.
- Exactly one comma per line, the field separator. Any comma inside a field forces the
  whole field to be quoted, so reword instead. No tabs, no duplicate prompts.
- Japanese lines annotate every kanji run with a hiragana reading in square brackets,
  including inside the bold span: `落[お]ち着[つ]く`.
- Validate before shipping: the authoring briefs and their `check_deck.py` /
  `check_notes.py` validators live in `.tmp/japanese` and `.tmp/spanish`, which is
  untracked scratch, not part of the build.

## Studying

Each card speaks its prompt on a loop, and the Play/Stop button sits above the answer
buttons. The gear menu picks installed voices for the question and answer languages
and sets a speaking speed from 0.5× to 2×, all taking effect on the next playback. Compact voices sound robotic;
enhanced and premium voices are downloaded through the system's Spoken Content
settings.

Each deck introduces up to a set number of unseen cards a day, 20 by default. Reviews
are never capped. The header counts new, again (cards on a same-day step) and review.
Once the day is finished, "Day completed!" offers extra cards for today only.

## Editing decks

Long pressing a deck offers "Browse deck", "Inspect deck", "Reset progress" and
"Delete deck", and swiping a deck deletes it too. The plus button uploads a CSV deck
or creates an empty one by hand.

Browsing reads a deck in file order and leaves the schedule alone: the arrows at the
bottom step back and forward, and forward reveals the answer before moving on. The
Auto button on the right plays a card hands free: the question three times, then the
answer and question alternating three times, then the next card. The gear picks the
question and answer voices, the answer voice coming from the deck's answer column
name.

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
