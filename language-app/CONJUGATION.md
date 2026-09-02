Conjugation deck
================

This explains `decks/conjugation.csv` for someone who has never studied Japanese. Japanese
words are written here in romaji, the spelling with Latin letters, so you can read it
before you can read Japanese script.

## Why the deck exists

English changes a verb a handful of ways: go, goes, going, went, gone. Japanese changes a
verb far more, but always by swapping the ending, and never for who is speaking. *Iku* is
go, and it is the same word whether I go, you go, or they go. What the ending does carry
is tense, negation, politeness, permission, obligation, guessing, and about twenty other
jobs English handles with extra words.

Because the endings are regular, the word decks (`slime.csv`) list plain dictionary words
only, and this deck teaches the endings once. It is 196 cards covering seventy named
forms, and between them they let you build any form of any word in the other decks.

Each card shows one form, and the `**bold**` part is the piece that changed:

```
食[た]べ**ました**,ate; Polite past of an -eru verb.
```

The prompt is *tabemashita*, the answer is the English plus a one-line label saying which
form it is and which kind of word it belongs to. `[た]` is a pronunciation hint the app
displays above the kanji.

## Step 1: which kind of word are you holding

Endings attach differently depending on the word, so before conjugating anything you have
to know which of six kinds you have. The deck labels every card with one of these.

| Kind | Example | How you recognise it |
| --- | --- | --- |
| Consonant verb | *iku* (go), *kaku* (write), *nomu* (drink) | The dictionary form ends in any -u sound |
| Vowel verb | *taberu* (eat), *miru* (see) | The dictionary form ends in -eru or -iru |
| *suru* | *suru* (do) | Irregular, and hides in hundreds of compounds like *benkyou suru* |
| *kuru* | *kuru* (come) | Irregular, and the only one of its kind |
| i-adjective | *tsuyoi* (strong) | Ends in -i, and inflects for tense like a verb |
| Noun or na-adjective | *maou* (demon lord), *daijoubu* (all right) | Does not inflect; the word *da* after it does |

The cards name consonant verbs by their exact ending — a -ku verb, a -mu verb, a -su verb
— because the te form, explained below, differs for each one. Vowel verbs are labelled
"-eru verb" after the example *taberu*.

Warning: *kaeru* (go home) ends in -eru but is a consonant verb, and so are *hashiru*
(run) and *hairu* (enter). The spelling does not always tell you, so the deck teaches
*kaeru* explicitly.

## Step 2: cut the ending off

Take the dictionary form, cut the last sound off, and you have a stub that endings attach
to. For a consonant verb you then choose which vowel to put back, and the vowel you choose
decides which endings are allowed. A vowel verb has just the one stub.

*Iku* (go) cut back to *ik-*, then:

| Stub | Ending you would add | Result |
| --- | --- | --- |
| *ika-* | *-nai* | *ikanai*, does not go |
| *iki-* | *-masu* | *ikimasu*, goes (polite) |
| *iku* (uncut) | *-na* | *ikuna*, do not go |
| *ike-* | *-ba* | *ikeba*, if one goes |
| *iko-* | *-u* | *ikou*, let us go |

*Taberu* (eat) cut back to *tabe-* and stays there: *tabenai*, *tabemasu*, *tabereba*,
*tabeyou*. This is why vowel verbs are the easy group and why the deck spends most of its
cards on the consonant ones.

*Suru* and *kuru* change shape instead of just shedding a vowel — *shinai*, *shimasu*,
*konai*, *kimasu* — so they get their own card in nearly every section.

## Step 3: the te form, which everything else is built on

One stub is important enough to be a form in its own right. It is called the te form, it
ends in *-te* or *-de*, and on its own it means "…and then". *Itte kudasai* is please go;
*tabete miru* is try eating; *tabeta* is ate. Nearly half the cards in this deck (88 of
196) are built on it.

For vowel verbs it is easy: cut *-ru*, add *-te*. For consonant verbs the dictionary
ending decides which sound you get, and this is the one table worth memorising outright.

| If the verb ends in | The te form ends in | And the past ends in | Example |
| --- | --- | --- | --- |
| -ku | -ite | -ita | *kaku* → *kaite*, *kaita* (write) |
| -gu | -ide | -ida | *oyogu* → *oyoide*, *oyoida* (swim) |
| -u, -tsu, -ru | -tte | -tta | *kau* → *katte*; *matsu* → *matte*; *toru* → *totte* |
| -mu, -bu, -nu | -nde | -nda | *yomu* → *yonde*; *yobu* → *yonde*; *shinu* → *shinde* |
| -su | -shite | -shita | *hanasu* → *hanashite*, *hanashita* |
| -eru (vowel verb) | -te | -ta | *taberu* → *tabete*, *tabeta* |

Two things make this cheap to learn. The past tense is the te form with the last vowel
changed to *-a*, so *katte* → *katta* and *yonde* → *yonda*; you learn one column and get
the other free. And *iku* is the only verb that breaks the pattern: by the -ku row it
should give *iite*, but it actually gives *itte*, *itta*.

i-adjectives and nouns have their own version: *tsuyoi* → *tsuyokute* (strong and…),
*maou* → *maou de* (being the demon lord and…).

## Step 4: the sections

From here the deck is one section per job. The early sections spell each form out for a
consonant verb, a vowel verb, *suru*, *kuru*, and where it applies an adjective and a
noun. Later sections use one or two example verbs, because by then the ending attaches the
same way for everything.

### Plain tense and negation

The four combinations of past/non-past and positive/negative. This is the base register:
what you say to friends, and what you see in subtitles.

| | *iku* (go) | *taberu* (eat) | *tsuyoi* (strong) | *maou* (demon lord) |
| --- | --- | --- | --- | --- |
| is | *iku* | *taberu* | *tsuyoi* | *maou da* |
| was | *itta* | *tabeta* | *tsuyokatta* | *maou datta* |
| is not | *ikanai* | *tabenai* | *tsuyokunai* | *maou ja nai* |
| was not | *ikanakatta* | *tabenakatta* | *tsuyokunakatta* | *maou ja nakatta* |

There is no future tense: *iku* covers both go and will go. Notice that the negative
*-nai* itself ends in -i and then behaves like *tsuyoi*, which is why the past negative is
just *-nai* turned into *-nakatta*. Japanese stacks endings like this constantly.

### Polite forms

Japanese marks politeness in the verb rather than in word choice. Swap *-masu* onto the
*-i* stub and the sentence becomes appropriate for strangers, shops and work.

| Plain | Polite |
| --- | --- |
| *iku* | *ikimasu* |
| *ikanai* | *ikimasen* |
| *itta* | *ikimashita* |
| *ikanakatta* | *ikimasen deshita* |
| *ikou* (let us go) | *ikimashou* |

Nouns and na-adjectives use *desu* and *deshita*: *maou desu*, *maou deshita*.
i-adjectives keep their own past and add *desu* on top: *tsuyokatta desu*.

### Telling someone what to do

Ordered from rudest to politest. Register matters more here than anywhere else: the blunt
command is normal in anime and close to unusable in real life.

| Form | Force |
| --- | --- |
| *ike*, *tabero*, *shiro*, *koi* | Bare order, rude |
| *tabenasai* | Firm, an adult to a child |
| *itte kure* | Blunt favour asked of a friend |
| *itte kudasai* | Please go |
| *ikuna* | Do not go, barked |
| *itte wa ikenai* | You must not go, as a rule |
| *ikanaide kudasai* | Please do not go |

### Wanting, trying, being able

- Want to: *-tai* on the *-i* stub — *ikitai* (want to go). It then behaves like an
  i-adjective: *ikitakunai* (do not want to go), *ikitakatta* (wanted to go).
- Let us: *ikou*, *tabeyou*, polite *ikimashou*.
- Can: consonant verbs use the *-e* stub, *ikeru* (can go); vowel verbs add *-rareru*,
  *taberareru*; *suru* becomes *dekiru*. Negative is regular: *ikenai* (cannot go).
- Intend to: *iku tsumori*.

### Having it done to you, and making others do it

Endings that stack on the *-a* stub, each one longer than the last.

| Meaning | Consonant verb | Vowel verb |
| --- | --- | --- |
| It is done to me | *ikareru* | *taberareta* (was eaten) |
| I make or let someone do it | *ikaseru* | *tabesaseru* |
| I am made to do it | *ikaserareru* | *tabesaserareru* |
| Same, shortened in speech | *ikasareru* | — |

For vowel verbs "can eat" and "is eaten" come out identically as *taberareru*; only the
sentence tells you which. That is why the deck teaches the passive through its past form
*taberareta*. Separately, *-reru* doubles as a respectful form, so *ikareru* can mean that
someone you respect went.

### If, when, and even if

Japanese splits "if" into several endings that are not interchangeable.

| Form | Use it for |
| --- | --- |
| *ikeba* | Plain if, typically giving advice |
| *ikanakereba* | If not — and the base of the obligation forms below |
| *ittara* | Once this has happened, then the next thing |
| *maou nara* | If it is the case that it is the demon lord |
| *iku to* | Whenever this happens, the same result always follows |
| *itte mo* | Even if |

### Permission and obligation

Both are built by wrapping forms you already have, which is why they look long.

- *itte mo ii* — te form plus *mo ii*: it is fine to go.
- *ikanakereba naranai* — "if I do not go, it will not do": I have to go.
- *ikanai to ikenai* — same meaning, more conversational.
- *ikanakya* — the same phrase clipped short, casual.

### Three ways to say "not doing"

*Ikanakute* gives a reason (not going, so…). *Ikanaide* describes how something is done
without going, and is also how you ask someone not to do it. *Ikazu ni* is the same idea
in stiff, written Japanese.

### Time and experience

- *ikinagara* — while going, doing two things at once.
- *itta koto ga aru* — has been there at least once in one's life.
- *itte kara* — after going.
- *tabeta bakari* — has only just eaten.
- *taberu tokoro* — is just about to eat.

### Guessing, and repeating what you heard

These all translate to something like "seems" or "apparently", and differ by where the
speaker's confidence comes from.

| Form | The speaker is going on |
| --- | --- |
| *ikisou* | How it looks right now |
| *iku sou da* | What someone else said |
| *tsuyoi rashii* | Reputation or second-hand report |
| *iku mitai* | Their own impression |
| *iku kamoshirenai* | Bare possibility |
| *iku deshou* / *maou darou* | Probability, polite and plain |
| *iku hazu da* | It was arranged or it stands to reason |

### Verbs bolted onto the te form

A second verb after the te form adds a shade of meaning rather than a tense. This is where
Japanese puts much of what English does with adverbs.

| Form | Adds |
| --- | --- |
| *tabete shimau*, casual *tabechau* | Finishing it off, often with regret |
| *tabete oku* | Doing it now to be ready later |
| *tabete miru* | Trying it and seeing |
| *kaite aru* | It stands written — someone did it and the result remains |
| *itte kuru* | Going and coming back |
| *itte iku* | Carrying on from here |
| *tabete ageru* | Doing it for someone else |
| *tabete kureru* | Someone doing it for me |
| *tabete morau* | Getting someone to do it for me |

The last three track who the favour flows to. Japanese requires this; English usually
leaves it out.

### Being in the middle of something

*Te iru* is the te form plus the verb *iru* (to be), and it covers what English calls the
progressive: *tabete iru*, is eating. Since *iru* is itself a verb, it takes all the
endings you already know: *tabete imasu* (polite), *tabete ita* (was eating), *tabete
inai* (is not eating), *tabeteru* (casual).

With verbs of movement or change it describes the state left behind rather than an action
in progress, so *itte iru* means has gone, not is going.

### Making other words out of a verb

The *-i* stub acts like a noun, so other words attach to it: *tabesugiru* (eat too much),
*tabeyasui* (easy to eat), *tabenikui* (hard to eat), *tabehajimeru* (start eating),
*ikikata* (the way to go somewhere). i-adjectives do the same with *-sa*: *tsuyosa*,
strength.

### Formal speech

Japanese has a register above *-masu* for customers, bosses and strangers you want to
flatter. Two patterns, both on the *-i* stub: *omachi ni naru* lifts the person you are
talking about, *omachi suru* lowers you in front of them. Both mean "wait". Verbs that
have their own irregular formal words, like *irassharu*, are vocabulary and live in the
word decks.

### Adjectives as adverbs

*Tsuyoku* is strongly. *Daijoubu ni* is the same trick for a na-adjective. And a
na-adjective needs *na* before a noun: *daijoubu na hito*, a person who is all right.

## What the deck skips

Forms you can work out yourself once you know the pattern (*kite mo ii*, *konakereba
naranai*), irregular formal vocabulary (*irassharu*, *meshiagaru*), and the bookish
copulas *de aru* and *de gozaimasu*.
