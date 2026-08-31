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
on first launch, and refreshed from the bundle while the copy is unedited. A Japanese
row may leave the answer empty, as `きゃ,`, and the app fills it in with the romaji of
the prompt.

## Making a deck

`spanish.csv` is the model to copy. It and `slime.csv` follow the same recipe:

- Start from a frequency-ordered wordlist of a thousand words, counted over a corpus
  that matches the deck: the show's own subtitles for `slime.csv`, Spanish subtitles at
  large for `spanish.csv`. Most common first.
- One card per word, in that order: card *i* teaches word *i*, so the file is the
  wordlist plus a header.
- In Spanish a word is a form, so every conjugation is its own card. In Japanese the
  endings are regular and person-free, so the wordlist holds dictionary words and
  `conjugation.csv` teaches the endings once. Only forms no rule predicts — 来[き]た,
  行[い]った, しろ, 来[こ]い, よかった — get their own wordlist entry, placed at the
  frequency of that form in the corpus.
- i+1: apart from the one new word, every content word in the phrase must already have
  been taught on an earlier line. Grammar is free — particles, articles, pronouns,
  prepositions, the copula, and conjugation endings never count as vocabulary.
- The prompt is a real phrase or short sentence someone would say, 2–6 words, never a
  bare word. Vary the shape: questions, replies, exclamations. The first cards have
  almost no vocabulary to lean on, so keep them very short.
- Exactly one `**bold**` span per line, marking the new word as it is spelled in the
  wordlist, conjugation and furigana included. Pick the form the source actually uses
  most, and one that cannot be read as a different word.
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
  untracked scratch, not part of the build. `bazel test //language-app/content` also
  loads every deck in `decks/` and fails on a malformed or duplicated card.

## Studying

Each card speaks its prompt on a loop, and the Play/Stop button sits above the answer
buttons. The gear menu picks installed voices for the question and answer languages
and sets a speaking speed from 0.5× to 2×, all taking effect on the next playback. Compact voices sound robotic;
enhanced and premium voices are downloaded through the system's Spoken Content
settings.

Each deck introduces up to a set number of unseen cards a day, 20 by default. Reviews
are never capped. The header counts new, again (cards on a same-day step) and review.
Once the day is finished, "Day completed!" offers extra cards for today only.

The queue is read only when a card is taken up — on opening the deck and after each
grade — so the card on screen never changes on its own. With nothing else waiting, a
learning step due within twenty minutes is shown early, Anki's learn-ahead limit.

Undo in the toolbar, ⌘Z, takes back the last grades one by one, up to thirty, and
brings each card back on its answer to be graded again.

## Editing decks

Long pressing a deck offers "Browse deck", "Browse randomly", "Inspect deck",
"Reset progress" and "Delete deck", and swiping a deck deletes it too. "Browse
randomly" shuffles the deck once for that browse session. The plus button uploads a CSV deck
or creates an empty one by hand.

Browsing reads a deck in file order and leaves the schedule alone: the arrows at the
bottom step back and forward, forward reveals the answer before moving on, and back
returns to the question. The
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
