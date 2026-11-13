# Russian and Mongolian speech: what shipped, what is verified

The state of this branch, honestly. The ТЗ asked for Speak to read Russian and Mongolian.
It does the reading; what is proven and what is not is below. Work was done on branch
`arena/e94f2cbe-chimera-ru-mn`, uncommitted (the tree is the deliverable; review the diff).

## What shipped

**The readers and the shared speech path (`crates/chimera/src/phonetics/`)**

- NEW `mongolian.rs` — Khalkha spelling → the existing inventory: short/long vowels
  (`Segment::dur`, same calibrated vowel), `ий` = long и, the diphthongs `ай эй ой уй өй үй`
  (one nucleus; `ʊɪ øɪ yɪ` added to the planner's `expand()` and the IPA tokenizer's `MULTI`),
  iotated `я е ё ю` (after a vowel/word-initial: /j/ + vowel; after a consonant: the consonant and a
  25 ms /j/ glide, as Russian), н → /ŋ/ at word end and before a consonant, the aspirated vs
  unaspirated stop/affricate contrast (`п т ц ч` aspirated, `б д з ж` unaspirated), žg/`г` as-is,
  non-initial short vowels very weak (0.07 s, never deleted), fixed first-syllable stress,
  citation numerals 0–9999.
- NEW `speech.rs` — the shared path both CLI and WASM call: `speech(language, text, &g2p) ->
  SpeechOutput { phrases, diagnostics }`. English goes through its unchanged `EnglishG2P::to_phrases`
  plus a diagnostics scan. Russian and Mongolian go through one skeleton: number expansion
  0–9999 (Russian: the table, masculine nominative; bigger numbers digit-by-digit with a
  `numberOutOfRange` warning), punctuation phrase splitting reusing the English tokenizer helpers,
  word punctuation/silence handling, `?` ⇒ question, pauses (0.35 s / 0.18 s / 0.3 s), and
  **diagnostics**: `guessedStress | unsupportedCharacter | mongolianLettersInRussian |
  numberOutOfRange | emptyText`. Bare-consonant prepositions (в, с, к …) merge into the next word —
  sound rides on its first syllable, voiced by it — and keep their own word end and their word in
  `words`, so the mouth display aligns word-for-word with the segments.
- `russian.rs` — the reader learned nothing new phonologically; the STRESS table gained the
  numerals (0–9999, vowel-indexed like the rest of the table) and `number_words()`; new
  `word_before_explain()` reports *how* stress was resolved (`Explicit | Yo | Dictionary |
  Fallback | None`) so the speech path can warn instead of guess silently. `word_before()` is
  unchanged for existing callers.
- `mod.rs` — `pub mod mongolian; pub mod speech;`.
- `ipa.rs`, `planner.rs`, `english.rs` — the three new diphthongs; `split_keeping`,
  `is_phrase_punct` → `pub(crate)` (visibility only).

**CLI (`crates/chimera-cli/`)**

- `render text <out> ["Text."] [body] [--language en|ru|mn]` (default `en`, as before; `-l ru` and
  `--language=ru` also accepted). Warnings → stderr as `warning: …`; the transcription to stdout;
  the WAV is written as before; an unknown language or no speakable phrases → stderr + exit 1.
- NEW `transcribe ["Text."] [--language en|ru|mn]` — the transcription and warnings, no WAV.
- Default example text per language (`Привет! Как твои дела?`, `Сайн байна уу?`). The English
  dictionary is only required for English — ru/mn render without it.

**Web (`src/`)**

- NEW wasm JSON call `textPhrases { language, text } -> { phrases, warnings }`;
  `speechPhrases(language, text)` on the facade; `SpeechDiagnostic` in `types.ts`; the Speak
  panel gained a **Language menu (English / Русский / Монгол)**, per-language examples, a
  Russian stress hint (`молоко́`), and the warnings print in the same notice area as the
  IPA-input skip list. The language switch keeps the text box; IPA mode is language-independent.
- The engine build predates this branch gracefully degrades: English still speaks through the
  dictionary, and the ru/mn switch shows a "rebuild the wasm" warning instead of dying
  silently (`src/ui/speech.ts`).

**Docs & tests** — `docs/russian-speech.md`, `docs/mongolian.md`, this file; `docs/russian.md`
and `docs/ru-mn-audit.md` (the pre-change audit) updated to match. Tests: `crates/chimera/tests/
mongolian.rs`, `crates/chimera/tests/speech.rs` (phrases, warnings, numerals, proclitics,
diagnostics kinds).

## What is verified — and what is not

**Not compiled.** This sandbox has no Rust toolchain (`cargo`, `rustc` unreachable), so every
`.rs` file in this branch is written against the existing patterns and **never type-checked,
never run, not one test executed**. What was done instead:

- `npx tsc --noEmit` — **clean** (TypeScript, including the new `textPhrases` facade path).
- tree-sitter parse of all `.rs` files — clean, except identical pre-existing false positives in
  `render.rs::notes()` (a parser gap; the same errors exist on untouched upstream code).
- Three reader bugs were found and fixed by re-reading, not by running: a missing `с` in the
  Mongolian consonant table (every word with с read as `?`), `ю` mapped to the wrong base vowel,
  and `я`/`е` missing from `base_vowel` (an `unreachable!()` on ordinary words like «нэг»).
- All test expectations in the two new test files were re-derived by hand from the code paths
  (number tables, diphthongs, weak vowels, voicing, proclitic merge). They have not been run.
- Both hand-computed tables were verified programmatically against the source itself: the number
  composition (a Python mirror of `number_words` transcribed from the Rust, checked 0–9999 in both
  languages plus a golden list) and the Russian `STRESS` numeral indices (bounds plus the expected
  stressed vowel for every numeral entry).
- A Python mirror of the Mongolian reader and of the shared `drive()` path was fuzzed over
  4000 random mixed-script inputs (no exceptions; Cyrillic alphabet fully readable; every word
  produced by the number tables reads clean; no reachable `?` phoneme; word-end/word-count
  alignment holds for the shipped example sentences in both languages).

**So this branch has no green test run.** On a machine with the toolchain, in order
(Windows: double-click `dev.bat`, or `dev.bat test` to run test 1 first):

1. `cargo test --workspace` — expects the new `mongolian.rs`/`speech.rs` suites plus the existing
   Russian suite to pass; any failure is a hand-trace bug to report, not a mystery — open an
   issue with the failing assertion.
2. `cargo build -p chimera-wasm --release --target wasm32-unknown-unknown && cp
   target/wasm32-unknown-unknown/release/chimera_wasm.wasm src/wasm/chimera.wasm` (this is
   `bun run wasm`; `src/wasm/chimera.wasm` is not in this checkout — it is gitignored).
3. `bun install && bun run test` (the TS suite also exercises the engine through the wasm).
4. `chimera transcribe --language ru "Привет! Как твои дела?"` and `--language mn "Сайн байна уу?"`
   — checks warnings and the transcription print; then `render text …` for the WAVs.
5. A native Khalkha listening pass. None of the Mongolian vowels/diphthongs/codas have been
   heard through the voice; the timings and the weak-vowel centring are first estimates.

## Deliberately out of scope / known limits

- Numbers only 0–9999, citation forms, no ordinals/dates/sums (per the ТЗ); past 9999 → digit
  reading + `numberOutOfRange`.
- Not a dictionary: Russian stress for words outside the table is a marked-word affair (the
  warning exists precisely for this); Mongolian stress is the fixed first-syllable rule.
- Prosody, breath and accent come from the phrase planner; no new contours were added.
- Sing is untouched; Mongolian Sing is a documented follow-up (the module keeps what it needs).
- `ː` from the IPA tokenizer stays ×1.7 and is global; the readers use explicit `dur` instead.
- Final devoicing and assimilation do not cross phrase punctuation, as in Russian speech generally.
- `package-lock.json` appeared untracked (an `npm install` ran next to the repo's `bun.lock`);
  harmless, delete or ignore it as you prefer.
- Diagnostics are the five kinds implemented in `speech.rs`; nothing else is reported.

## The ТЗ checklist

Texts in Russian and Mongolian go through Speak (CLI `--language`, web Language menu) — done in
code, unverified at runtime. Stress handling for Russian incl. ё and a frequent-word table — done.
Numbers in both languages, 0–9999 with a warning past it — done. Unknown characters and stress
guesses reported, never silent — done. Warnings on stderr (CLI) and next to the transcription
(web) — done. English untouched — expected by construction (its reader is reused unchanged; its
WASM surface and tests paths are unchanged) but unverified at runtime for the same reason as
everything here.
