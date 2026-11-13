# Russian speech (Speak)

Speak reads Russian with the speech rules of `phonetics::russian` — vowel reduction, Russian
vowel lengths, voicing assimilation, prepositions leaning on the next word — driven through the
shared speech path (`phonetics::speech`). It is the spoken sibling of the Sing front end; the two
share the spelling rules, and this document covers the speech half. How it plugs into the UI and
CLI, with what works where, is in [ru-mn-report.md](ru-mn-report.md).

## Writing Russian for it

- **Write words as usual.** Stress resolution, in order: a combining acute after the vowel
  (`молоко́`), then ё, then a short table of frequent words and numerals (`STRESS`), then the
  first vowel — a guess, and the reader says so (see Warnings).
- **Mark the stress** on anything not in the table. The transcription shows it (`ˈ`), and the CLI
  prints it too.
- **Numbers 0–9999** are read as words (masculine nominative): `42` → сорок два, `2000` → две
  тысячи. Bigger numbers are read digit by digit with a `numberOutOfRange` warning; ordinals,
  dates, sums and fractions are out of scope.
- Digits mixed with words work anywhere (`Мне 42 года` → Мне сорок два года).
- `?` makes the phrase a question (final rise). `. ! ; : ,` end the breath group (`.!?` → 0.35 s
  pause, `,;:` → 0.18 s).
- Apostrophes and quotes are silent and end a word, as spaces do.
- IPA input mode is unchanged and language-independent; this front end is bypassed there.

## What it does

Everything in [russian.md](russian.md) — that table is the phonology, and the speech path is the
same reader with `reduce`. In particular, for speech:

| | |
|---|---|
| Reduction | unstressed о а → /ɐ/; е э and pre-final/final я → /ɪ/; а after ч щ → /ɪ/ |
| Vowel lengths | unstressed vowels get Russian lengths (0.07 s, 0.09 pretonic or open final, 0.12 phrase-final); stressed ы is 0.19/0.12, not English's 110 ms |
| -тся, -ться | one long /ts/ (≈ ×1.5 the calibrated length), an unstressed vowel |
| Voicing | final devoicing; backwards assimilation through a cluster; в doesn't start it; a preposition (в, с, к, из, над, под…) takes the next word's voicing — including vowel-less prepositions, which ride the next word's first syllable |
| -ого / -его | /v/ (его, сего́дня, кра́сного, ничего́); `много` and friends keep /g/ |
| Frequent words | `тебя, его́, была́`… and the numerals have their stress in the table |

## Warnings (the diagnostics contract)

The reader never guesses silently. Everything imperfect comes out of the CLI on stderr as
`warning: …` and out of the WASM call as `warnings` (the Speak panel prints them under the
transcription). Kinds:

| kind | when |
|---|---|
| `guessedStress` | a word was neither marked, nor ё, nor in the table: the first vowel was stressed. Fix: mark it (`молоко́`) |
| `unsupportedCharacter` | a letter or mark it has no rule for (Latin letters, Ukrainian і/ї/є/ґ, a stray symbol) — reported, the rest is still said |
| `mongolianLettersInRussian` | the text has «ө» or «ү», which Russian does not have; switch the language to Монгол |
| `numberOutOfRange` | a number above 9999: read digit by digit |
| `emptyText` | only alphabetic characters it could not read: nothing was said |

## What is approximate (not new here)

- Soft consonants are a 25 ms /j/ glide, not a palatalised articulation (л is the exception:
  dark /ɫ/ hard, clear /l/ soft).
- р is a tap /ɾ/.
- Stress and reduction are the spelling rules' best effort, not a dictionary (this is why the
  guess is a warning, not silence).
- The Klatt timings are English's, tempered for Russian where they were audibly wrong (see the
  table above); they have not been validated by a native listening pass.
- Final devoicing is by rule across the word, and proclitics lean forward; voicing does not cross
  other boundaries.

## Testing it

`crates/chimera/tests/russian.rs` (the reader), `crates/chimera/tests/speech.rs` (the speech
path: phrases, warnings, numerals). Run `cargo test --workspace` — see the report for the build
status of this branch.
