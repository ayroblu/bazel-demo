Sherlock
========

An Alfred-style launcher for macOS. Press ⌘Space to show the search bar, type to
find apps, settings, commands, bookmarks and files, and press ↩ to run the
selected result. ⌥⌘C opens your clipboard history.

Results are listed in this order:

1. **Quick links**: a keyword and your search, like `npm react` or `gh swift
   yaml`, opens that site's search (see [Quick links](#quick-links)).
2. **Calculator and conversions**, ↩ copies the result:
   - Maths: `24*7`, `15% * 80`, `sqrt(16) + 2^3`, `=1/3`. Supports
     `+ - * × / ÷ ^ %`, brackets, `pi`, `e` and `sqrt abs sin cos tan asin acos
     atan ln log log2 exp round floor ceil`.
   - Units: `5 km in mi`, `100 f to c`, `3 cups to ml`, `70 mph in km/h`,
     `1.5 gb in mb`, `2 days in hours` (length, mass, volume, temperature,
     speed, time, data, area, energy, angle).
   - Currency: `10 usd in gbp`, `£20 to eur`. Daily ECB rates from
     [Frankfurter](https://frankfurter.dev), cached for 12 hours in
     `~/Library/Caches/com.ayroblu.sherlock/rates.json`.
   - Time zones: `time in tokyo`, `nyc time`, `3pm pst in london`,
     `9:30 london to tokyo`. Places are city names, abbreviations (`pst`, `cet`)
     or a few aliases (`sf`, `nyc`, `uk`, `japan`, …).
3. **Apps, System Settings pages and system commands**, ranked together:
   - Apps come from `/Applications`, `/System/Applications`, `~/Applications`,
     `/System/Library/CoreServices/Applications`, Finder, and any other app
     Spotlight knows about (for example `~/ws/deps/apps`). Copies of the same app
     (same bundle ID) are listed once.
   - Settings pages (Bluetooth, Wi‑Fi, Displays, …) are read from
     `/System/Library/ExtensionKit/Extensions` and open straight to that page.
   - Safari and Chrome bookmarks.
   - Commands: Lock, Sleep, Restart, Shut Down, Log Out, Empty Trash and Eject
     All. Restart, Shut Down and Log Out show the macOS confirmation; Empty Trash
     asks first. macOS asks once for permission to control Finder (Empty Trash)
     and the login window (Restart, Shut Down, Log Out).
4. **Files** from Spotlight (`MDQuery`), searched in your home folder (and
   iCloud Drive) once the query has 2 or more characters. They arrive
   asynchronously, usually within about 100 ms. Files with unknown types
   (`dyn.*`, mostly build output), `~/Library`, hidden folders and
   `node_modules` are skipped. Files you have opened before rank higher.
   macOS hides Desktop, Documents and Downloads (the folders and everything in
   them) from Spotlight results until Sherlock has Full Disk Access; Settings
   warns about this and links to System Settings > Privacy & Security > Full
   Disk Access.
5. **Fallback quick links** (Google by default), when nothing in 1–3 matches.

### Keywords

Start the query with a keyword and a space to search one thing:

| Keyword | Searches | ↩ |
| --- | --- | --- |
| `clip …` (or ⌥⌘C) | Clipboard history, newest first | Copies the item |
| `snip …` | Snippets, by name or keyword | Copies the snippet |
| `h …` | Safari and Chrome history, newest first | Opens the page |
| `e …` | Emoji, by name, keyword or Slack shortcode (`e tada`) | Pastes the emoji |
| `u …` | Unicode symbols, by name (`u em dash`, `u e acute`, `u cmd`) | Pastes the symbol |

Change the `clip` and `snip` keywords in Settings > Clipboard and Settings >
Snippets (one word, case-insensitive); the clipboard hotkey uses the clipboard
keyword. Typing `clipboard`, `snippets`, `history`, `emoji` or `unicode` also
shows an item that fills in the keyword (↩ or ⇥).

**Emoji** come from [emojibase](https://emojibase.dev) (`emojibase-data`,
fetched by Bazel and bundled in the app), with Slack shortcodes; skin tone
variants are left out. **Symbols** are the Unicode symbols, punctuation and
Latin, Greek and Cyrillic letters, named by Swift's built-in Unicode data;
keyboard symbols (`⌘ ⌥ ⇧ ⌃ ↩ ⌫ ⎋ ⇥`) can also be found by key name and are
listed first. Both are loaded once at launch and searched in memory.

**Clipboard history** records what you copy (checked twice a second, plus
whatever is on the clipboard when Sherlock starts), with the app it came from:
text, rich text (RTF, RTFD and HTML are kept alongside the plain text), images
(stored as PNG, shown with a thumbnail and size) and copied files. ↩ puts the
item back with all of its formats, so rich text keeps its formatting. Search by
text, or `image`, `rich text` or `file`. It skips copies that password managers
mark as concealed or transient, and formats over 20 MB. History is kept for 7
days by default (1, 7 or 30 in Settings), up to 500 items and 100 images, in
`~/Library/Application Support/Sherlock/clipboard.json` with the images and
other formats in `Clipboard/` next to it.

**Snippets** are stored in `snippets.yaml` in the config folder (see
[Config](#config)), a list like:

```yaml
- keyword: ::sig
  name: Signature
  text: |-
    Thanks,
    {clipboard}
```

Settings > Snippets > Edit… opens the file. Snippet text can use `{clipboard}`,
`{date}`, `{time}`, `{datetime}`, `{date:yyyy-MM-dd}` (any date format),
`{random:UUID}` and `{snippet:keyword}`. With "Expand snippet keywords as you
type" on, typing a keyword anywhere replaces it with the snippet.

Turn on Settings > Clipboard > "Paste into the front app" to have ↩ paste
clipboard items, snippets, emoji and symbols straight into the app you were
using; otherwise ↩ copies them. Pasting and expanding snippets need Accessibility access
(Settings > Permissions); without it, Sherlock copies the text instead.
Safari bookmarks and history need Full Disk Access.

Apps, Settings pages and commands are kept in memory and rebuilt in the
background when the bar opens (at most every 30 seconds), so matching them takes
about 1.5 ms per keystroke. Matching works like Alfred: exact name, then name
prefix, word prefix (`set` → System Settings), initials (`am` → Activity
Monitor), substring, then a loose in-order match (`safri` → Safari). Sherlock
remembers what you pick: the result you chose for a query moves to the top the
next time you type that query, and often-used items rank higher.

## Keys

| Key | Action |
| --- | --- |
| ⌘Space | Show or hide the bar (change it in Settings) |
| ⌥⌘C | Show clipboard history (change it in Settings) |
| ⇥ | Fill in the selected keyword item |
| ↑ ↓, ⌃P ⌃N, scroll | Move the selection |
| ↩ | Run the selected result |
| ⌘1 … ⌘9 | Open the result with that number |
| ⌘↩ | Reveal the selected result in Finder |
| ⌘, | Open Settings |
| ⎋ | Close the bar |

## Settings

Open Settings with ⌘, in the bar, or from the magnifying glass in the menu bar.
You can:

- record different hotkeys for the bar and clipboard history (click the
  shortcut, then press the new keys; ⎋ cancels)
- turn Spotlight file results on or off
- turn clipboard history on or off, choose how long it's kept, or clear it
- edit the snippets file and turn on expansion as you
  type
- grant Accessibility access (for pasting and snippet expansion)
- choose the config folder
- hide the menu bar icon
- launch Sherlock at login

### Quick links

`quicklinks.yaml` in the config folder lists sites to search by keyword. Typing
the keyword, a space and your search opens `url` with `{query}` replaced by your
search, percent-encoded:

```yaml
- keyword: npm
  title: Search npm for ‘{query}’
  url: https://www.npmjs.com/search?q={query}
- keyword: gh
  spaces: +
  title: Search GitHub for ‘{query}’
  url: https://github.com/search?q={query}
- fallback: true
  keyword: g
  title: Search Google for ‘{query}’
  url: https://www.google.com/search?q={query}
- keyword: youtube
  title: Open YouTube
  url: https://youtube.com
```

- `title` is shown in the results, with `{query}` replaced by your search.
- `spaces` (optional) replaces the spaces between words, for sites that expect
  `+`; otherwise spaces become `%20`.
- `fallback: true` (optional) shows the link when nothing else matches.
- A `url` without `{query}` just opens that URL.
- Typing a keyword or words from a title also lists the quick link; ↩ or ⇥ fills
  in the keyword.
- Web quick links show the site's favicon (its Apple touch icon or `<link rel="icon">`,
  else `/favicon.ico`), fetched directly from the site and cached in
  `~/Library/Caches/com.ayroblu.sherlock/Favicons` for 30 days. Until it arrives,
  or if the site has none (retried daily), the browser icon is shown.

The first time Sherlock runs it writes Google, YouTube, Wikipedia, GitHub and
Maps quick links. Settings > Quick Links > Edit… opens the file.

### Hotkeys

`hotkeys.yaml` in the config folder binds global hotkeys:

```yaml
- hotkey: hyper+t
  app: Alacritty            # app name, bundle ID or path; focuses or launches it
- hotkey: hyper+b
  app: default browser      # your default browser at the time you press it
- hotkey: hyper+v
  search: "clip "           # opens the bar with this text
- hotkey: hyper+m
  applescript: tell application "Music" to playpause
```

`hyper` is ⌃⌥⇧⌘; the other modifiers are `cmd`, `ctrl`, `alt` (or `opt`) and
`shift`. Keys are letters, digits, `f1`–`f20`, `space`, `return`, `tab`, `esc`,
`delete`, arrow keys (`left`, …) and punctuation. Every hotkey needs a modifier
other than `shift` (except `f1`–`f20`), so it can't take over normal typing.
Settings > Hotkeys lists each
hotkey and any problem (an unknown key, an app it can't find, or a shortcut
that's already taken). The first time an AppleScript controls another app,
macOS asks you to allow it.

### Extensions

An extension is a folder in `extensions/` inside the config folder, with an
`extension.yaml`:

```yaml
name: Process Tools                 # optional, defaults to the folder name
setup: yarn install && yarn build   # optional
commands:
  - keyword: kill
    title: Kill Process
    script: node dist/filter.js "$1"   # runs as you type
    action: kill "$1"                  # optional, runs on ↩ with the item's arg
```

Typing a command's keyword and a space runs its `script` with your search as
`$1` (and `$SHERLOCK_QUERY`), cancelling any run still in progress. The script
prints the results as JSON:

```json
{"items": [
  {"title": "node", "subtitle": "pid 4321", "arg": "4321"},
  {"title": "Docs", "url": "https://nodejs.org"},
  {"title": "Copy pid", "copy": "4321", "icon": "sf:doc.on.doc"}
]}
```

↩ on an item opens its `url`, copies its `copy`, or runs the command's
`action` with its `arg`, in that order. An item with only `autocomplete` fills
in the search instead. `icon` is a file in the extension or `sf:` plus an SF
Symbol name; an `icon.png` in the extension folder is the default.

Extensions run in two steps:

1. **Setup.** Sherlock copies the extension (without `.git`, `node_modules`
   and `data`) to `~/Library/Caches/com.ayroblu.sherlock/Extensions/<folder>`
   and runs `setup` there, unsandboxed, so it can install dependencies and
   build. Whenever a file in the extension changes (other than those three
   folders at its top level), Sherlock makes a fresh copy and runs setup
   again. Removing an extension removes its copy. Setup output is saved in `.sherlock-setup.log` in the
   copy, and failures show in Settings > Extensions and in the bar.
2. **Running.** Scripts and actions run in that copy under `sandbox-exec`: they
   can read files and use the network, but can only write files in the
   extension's data folder,
   `~/Library/Application Support/Sherlock/Extension Data/<folder>` (reachable
   as `./data` or `$SHERLOCK_EXTENSION_DATA`), and the temporary folders.
   Writing a file anywhere else fails with "Operation not permitted". This
   keeps scripts from changing their own code or your files by accident; it
   isn't a security boundary, since scripts can still ask other programs to
   make changes (for example with AppleScript or `defaults write`).

A script that runs too long is stopped along with anything it started: after
15 seconds for searches, 60 for actions and 10 minutes for setup.

Scripts get the `PATH` from your login shell, so tools like `node` and Homebrew
commands are found. `sandbox-exec` is deprecated by Apple but still works; if
it is ever removed, scripts run without the write restriction.

### Config

Your config lives in one folder, by default `~/Library/Application Support/Sherlock`.
Change it in Settings > Config (for example to keep it in your dotfiles):

- `settings.yaml`: hotkeys and options. Missing keys use their defaults, so a
  hand-edited file can list only what it changes.
- `snippets.yaml`: your snippets.
- `quicklinks.yaml`: your quick links.
- `hotkeys.yaml`: your hotkeys.
- `extensions/`: your extensions.

Sherlock watches the folder, so edits apply as soon as you save. If
`settings.yaml`, `snippets.yaml`, `quicklinks.yaml` or `hotkeys.yaml` doesn't
parse, Sherlock keeps using its last good contents until you fix it, and
doesn't save over a broken `settings.yaml`. An `extension.yaml` that doesn't
parse shows as an error in Settings > Extensions.

Choosing a new folder moves the files there. If the new folder already has its
own copy of a file, Sherlock uses that one and leaves the old one where it was.

Other state stays on this Mac:

- clipboard history: `~/Library/Application Support/Sherlock/clipboard.json`
  and `Clipboard/`
- learned picks and the config folder location: the `com.ayroblu.sherlock` user
  defaults
- exchange rates: `~/Library/Caches/com.ayroblu.sherlock/rates.json`
- extension copies: `~/Library/Caches/com.ayroblu.sherlock/Extensions/`
- extension data: `~/Library/Application Support/Sherlock/Extension Data/`

### Using ⌘Space

macOS gives ⌘Space to Spotlight by default, and other launchers often take it
too. Sherlock's Settings warn you when:

- Spotlight still has ⌘Space. Turn it off in System Settings > Keyboard >
  Keyboard Shortcuts > Spotlight.
- Raycast or Alfred is running. Change their hotkey (Raycast: Settings >
  General > Raycast Hotkey) or quit them.

## Code

| Folder | Contents |
| --- | --- |
| `MainApp.swift` | App entry point: hotkey, menu bar icon, menus |
| `bar/` | The search bar window, result rows and icon cache |
| `search/` | Matching, ranking and every result source (apps, Settings pages, commands, calculator, web, files, keyword modes) |
| `calculator/` | The arithmetic expression parser |
| `conversion/` | Unit, currency and time zone conversions |
| `clipboard/` | Clipboard history and pasting into the front app |
| `snippets/` | Snippet storage, placeholders and expansion as you type |
| `browser/` | Safari and Chrome bookmarks and history |
| `characters/` | Emoji and Unicode symbol data |
| `extensions/` | Extension setup, sandboxed script runs and status |
| `hotkey/` | Global hotkey registration and the shortcut model |
| `bindings/` | Hotkeys from `hotkeys.yaml`: focusing apps, searches, AppleScript |
| `preferences/` | Saved settings |
| `settings/` | The Settings window and shortcut recorder |

## Building

```sh
bazel build //sherlock-app
bazel run -c opt //sherlock-app:install
bazel run //sherlock-app:xcodeproj && xed sherlock-app/sherlock-app.xcodeproj
```

Install with `-c opt`: the default debug build is unoptimised and searches
about 10 times slower. `//sherlock-app:install` copies the app to `~/Applications/Sherlock.app`, signs it
with your first Apple Development certificate (ad-hoc if there is none) so macOS
keeps its permissions and login item across reinstalls, then restarts it.
