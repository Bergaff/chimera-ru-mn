# Mongolian (Khalkha, Cyrillic)

Speak reads Mongolian with its own front end (`phonetics::mongolian`) on the shared speech path
(`phonetics::speech`). There is no Sing front end yet — the module keeps the word reader and the
number tables Sing will need, and the syllabifier entry points exist, but Mongolian singing is a
follow-up. Both are documented at the bottom.

Sources for the phonology: J.-O. Svantesson, A. Janhunen & L. Karlsson, *The Phonology of
Mongolian* (Oxford University Press, 2005), and the standard modern Cyrillic orthography.

## Writing Mongolian for it

- **Write as usual.** No marks are needed: stress is fixed on the first syllable of the word, so
  there is nothing to guess (the reader never warns about stress — see Warnings).
- **Long vowels** are written doubled — `аа ээ оо уу өө үү` — and read as one vowel at about
  twice the short length. `ий` is the long и. (`ый` works too, a Russian spelling habit.)
- **Diphthongs** are vowel + `й`: `ай эй ой уй өй үй`, one nucleus.
- **Numbers 0–9999** are read as words: `11` → арван нэг, `21` → хорин нэг, `100` → зуу,
  `1000` → мянга, `3000` → гурван мянга. Above 9999 the digits are read one by one with a
  `numberOutOfRange` warning. Ordinals, fractions and sums are out of scope.
- `?` = question; `. ! ; : ,` end the breath group (0.35 s after `.!?`, 0.18 s after `,;:`).
- `е э у ө о` written with a diaeresis (`ё ӱ ӧ`, as Russian spellers type `ё ү ө`) are
  normalised to `ё ү ө`.
- Singing note: this is the speech half only; see "Sing" below.

## Letters and sounds

| | Mongolian | Read as |
|---|---|---|
| Vowels, short | а э и о у ө ү | /a e i o ʊ ø y/ |
| Vowels, long (×2 length) | аа ээ оо уу өө үү, ий | the same, `Segment::dur` ≈ 2× |
| Weak short vowels | any non-initial short а о are /ɐ/, э е are /ɪ/; the rest stay but are very short | `Segment::dur` 0.07 s |
| Diphthongs | ай эй ой уй өй үй | /aɪ eɪ ɔɪ ʊɪ øɪ yɪ/ (one nucleus) |
| Iotated vowels | я е ё ю = /j/ + vowel | word-initially and after a vowel: /j/ + vowel; after a consonant: the consonant and a short /j/ glide (25 ms), as in Russian |
| Consonants | х /x/; ц /ts/; ч /tʃ/; ш щ /ʃ/; л /ɫ/; р /ɾ/ (one tap); м /m/; ф /f/ (loans) |
| Stops and affricates | п т ц ч = aspirated; б д з ж = voiceless **unaspirated** (not voiced); г = "voiced" /g/ | aspiration is a front-end decision (`Segment::aspirated`), as Korean/Mandarin do it |
| н | /ŋ/ at the end of a word and before a consonant; /n/ otherwise | with one exception: before й (й is the diphthong's offglide) |
| Doubled consonants | one consonant; long between vowels (loans) | 0.16 s |
| Soft sign, hard sign | ь palatalizes the previous consonant; ъ is silent | as in Russian |

Stress is on the first syllable; an explicit combining acute overrides it (loanwords). Every
non-initial short vowel is very weak in speech — never deleted (Khalkha keeps them to the ear);
unreduced singing uses them full.

## Warnings (the diagnostics contract)

| kind | when |
|---|---|
| `unsupportedCharacter` | a letter the front end has no rule for — reported, the rest is said |
| `mongolianLettersInRussian` | (Russian texts only) the text has «ө» or «ү» |
| `numberOutOfRange` | a number above 9999: read digit by digit |
| `emptyText` | only alphabetic characters it could not read: nothing was said |

There is no `guessedStress` for Mongolian on purpose: stress is the fixed first-syllable rule, not
a guess, so the reader stays silent about it.

## What is approximate

- Khalkha stops are not voiced/voiceless in the Russian sense; the front end models them as
  aspirated vs unaspirated. Aspiration is attached to the release (the engine's
  aspiration/breathy-voice model), not the Khalkha
  *preaspiration/tensity* of medial and final stops — medial stops will sound plainer than in
  native speech.
- Weak non-initial vowels keep the base vowel with a short duration rather than merging to a
  uniform lax vowel (Khalkha realises them as very central [ɪ]/[ə]); never deleted.
- Vowel length is `Segment::dur` on the same calibrated vowel, not a separate phoneme; `ː` typed
  in IPA mode works too (×1.7).
- Consonant lengths are English Klatt timings; only doubled consonants and the 25 ms glide carry
  explicit Russian-style lengths.
- Loanwords (`в`, `ф`, `щ`, `ё` in Russianisms, doubled consonants) are handled minimally.
- п gets aspirated word-initially in native Khālkha; the front end marks it aspirated everywhere
  — the same simplification Korean and Mandarin accept.
- Ukrainian/Russian spellers' `ё` and `у`/`о` with diaeresis are accepted and normalised.
- **Native speaker pass is required and not done here.** Everything above is spelling-rule
  phonology, unlistened. That is the biggest risk in this document.

## Sing (not done)

`phonetics::mongolian` has the word reader and `is_onset` (open syllables, sonorant coda rule)
and `number_words`; wiring a `FrontEnd` for the lyrics router is a follow-up. Sung syllables
should stay open except sonorant codas (the Russian split rule is a good starting point), and a
long vowel should hold the note of its two written letters.

## Testing it

`crates/chimera/tests/mongolian.rs` — letters, long vowels, diphthongs, weak vowels, н→ŋ, the
number tables. `crates/chimera/tests/speech.rs` — the speech path (phases, warnings, numerals,
the proclitic merge). Run `cargo test --workspace`; see [ru-mn-report.md](ru-mn-report.md) for
what this branch has actually been run through.
