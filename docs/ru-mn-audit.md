# Russian and Mongolian speech: architecture audit and plan

Audit of upstream `main` @ `e1e489b` (merged as this branch's base), written before any code
changed. The questions the ТЗ asks, answered from the code as it is, not as the README implies it
is. "Speak" is CHIMERA's spoken mode; "Sing" assigns one note per vowel.

## 1. How Speak works today

**Web (`src/ui/`)**

- `components/SpeakPanel.tsx` renders the Speak column: the text box (or IPA box with the "Text is
  IPA" chip), a rate slider, and the read-outs under the chin. `speakText()` is called from
  `ui/speech.ts`.
- `ui/speech.ts`: English text → `EnglishG2P.toPhrases()` (the **wasm** engine, JSON call
  `g2pPhrases`), giving phrases of `Segment[]` with `intonation` (`?` ⇒ `question`, else
  `statement`), a post-phrase `pause` (0.35 s `.!?`, 0.18 s `,;:`, else 0.3 s) and `word` spans for
  highlighting. The phrases go to `planPhrases` (wasm `planPhrases`) which produces the gestural
  score; the worklet plays it. IPA mode bypasses G2P: `tokenizeIpa` splits on
  `.?!`/`|`, every chunk is one flat-`statement` phrase with a fixed 0.3 s pause.
- `src/wasm/engine.ts` + `chimera-wasm/src/api.rs`: `g2pPhrases`, `tokenizeIpa`, `skippedIpa`,
  `planPhrases` … — JSON in, JSON out, off the audio thread. The CMU dictionary is fetched once
  from `public/data/cmudict.txt.gz` (`g2pLoad`).

**CLI (`crates/chimera-cli/`)**

- `render text <out> ["text"] [body]` → `render::say()`: CMUdict `EnglishG2P::to_phrases()` →
  `plan_phrases()` → renders WAV; prints the transcription (`words` + stress) to stdout, warnings
  (there are none today) would go to stderr. `render speech <out> "ˈɑpɑ"` takes raw IPA. Exit code
  is 1 only when the command returns `Err`.
- `english.rs::to_phrases()` is the reference for what a "speech path" is: expand numbers, split on
  phrase punctuation keeping the delimiters, one token per word, last segment of every word gets
  `word_end`, `apply_allophones` (flapping, dark l), intonation from the delimiter, `pause` from
  the delimiter.

**Why Speak can't read Cyrillic today:** `to_phrases()` tokenises words as
`[a-z'][a-z'-]*`, so Cyrillic input yields **zero words → zero phrases → `speakText` silently
returns `null`**. Nothing plays, nothing is shown, no error. That is the gap this work closes.

## 2. What the language front ends do, and what can be reused

CHIMERA already has a **language front-end design** shared by Sing: `phonetics/syllables.rs`
routes each word to the front end whose script it is in (English → CMUdict/letter-to-sound, Korean
→ Hangul rules, **Russian → `phonetics/russian.rs`**). A front end maps spelling → IPA segments in
the shared inventory. `Russian::word(word, reduce)` **already implements the speech rules**
(unstressed vowel reduction, voicing assimilation and final devoicing, proclitics lean on the next
word, `-ого` → /vo/, `что` → /ʂto/, …) and `word_before(w, next, reduce)` even voices a
preposition by the *next* word. `docs/russian.md` says so explicitly: *"The reader already has the
speech rules … Russian Speak comes back through the shared speech path, with the same front-end
list as Sing."*

Reusable as-is (no or minimal changes):

- `russian::word_before(w, next, reduce)`: Cyrillic word → segments, with reduction
  (`reduce=true`), stress resolution (explicit `´` combining acute > ё > built-in frequent-word
  table > first-vowel fallback), voicing assimilation across a cluster and final devoicing.
- `Segment` carries everything the planner needs for speech: `dur`, `stress`, `word_end`;
  `Intonation::{Statement, Question, Flat}` and per-phrase `pause` already exist.
- The phrase planner `plan_phrases` needs no language-specific code: it applies the accents and a
  final rise for `Question`, falls for `Statement`, per-phrase breath groups and pauses.
- IPA tokenizer supports `ː` (length, ×1.7), stress marks, word gaps and comma pauses — Speak's
  IPA mode can already "speak" Russian and Mongolian if the user types IPA.

Not reusable / not enough:

- **Text → phrases** exists only for English (`G2P::to_phrases` is English-specific: CMUdict,
  function-word reduction, English allophones, English number expansion). Russian needs the same
  pipeline with Russian rules; Mongolian needs one from scratch. Neither exists.
- The Russian reader returns no **diagnostics** (unknown letters are silently `continue`d; the
  stress fallback is silent). Speak's contract demands warnings.
- **Mongolian does not exist at all**: no module, no numbers, no vowel treatment, no long vowels
  (Russian is unreduced in Sing; Mongolian's length is phonemic and must reach `Segment.dur`).
- `apply_allophones` is American English and must not run on ru/mn.
- `is_vowel` in the planner looks up the calibrated vowel table; our languages stay inside it
  (Russian: a e i o u ɨ ɐ ɪ; Mongolian adds `ø` and `y`, both present and calibrated) — but the
  Mongolian **diphthongs** need planner `expand()` entries (see §4).

## 3. Inventory check: what exists vs what each language needs

Checked in `phonetics/inventory.rs` and `vowelTargets.generated.json` (calibrated vowels per body:
`a e i o u y æ ø œ ɐ ɑ ɒ ɔ ə ɛ ɝ ɤ ɨ ɪ ɯ ʊ ʌ`). **A vowel in the IPA tokenizer is not the same as a
sound the voice has** — everything below is verified against the calibrated table and the planner.

| Sound | In table? | Used for |
|---|---|---|
| а /a/, о /o/, у /u/, э /e/, и /i/, ы /ɨ/ | yes | ru, mn |
| ɐ, ɪ (reduced) | yes | ru reduction (already used), mn weak vowels |
| ө → /ø/, ү → /y/ | **yes** | mn — both calibrated, no new vowel needed |
| iː, eː, aː … (long vowels) | n/a — a mark of *duration* | mn: same vowel with `Segment::dur` ≈ 1.9–2× (see §5); `ː` in IPA mode multiplies 1.7× |
| Diphthongs aɪ eɪ ɔɪ | yes (`expand()`) | mn ай, эй, ой |
| Diphthongs **ʊɪ øɪ yɪ** (үй, өй, үй) | **no** | added to `expand()` + IPA tokenizer's MULTI (additive, no behaviour change) |
| Palatalized consonants | `Segment.palatalized` → `ʲ`, tongue-body gesture | exists; Russian uses the 25 ms `j` glide instead (documented approximation) — kept |
| ts dz tʃ dʒ tsʰ … | yes | mn affricates (aspirated: ц ч; unaspirated: з ж) |
| х /x/, нг /ŋ/, л, р | yes (р as /ɾ/ tap, documented) | ru, mn |
| Final devoicing, voicing assimilation | code, not inventory | ru (exists), mn (not applicable, no final devoicing in mn) |

**Mongolian stops/affricates:** Khalkha has an *aspirated vs unaspirated* contrast (п т ц ч vs б
д з ж), not a voiced/voiceless one (Svantesson). \[ŋ\] assimilates н before consonants and at the
end of words. Both are handled in the front end (aspiration flags, consonant rules) — not a gap in
the engine.

**Russian soft consonants** remain the documented approximation (plain consonant + 25 ms /j/); see
`docs/russian.md`. Making palatalization a first-class articulation for everything is Phase-4 work
and is deliberately out of scope.

## 4. Consequences for Rust, WASM, UI, CLI

**Rust (`crates/chimera`)**

- New `phonetics/mongolian.rs`: letters, spelling→segments (long/short vowels, diphthongs,
  iotated е ё ю я, н→ŋ, aspirated/unaspirated stops, stress on the first syllable, weak-vowel
  reduction in non-initial syllables), number words 0–9999, and the front end for Sing (a follow-up;
  the module must not preclude it).
- New `phonetics/speech.rs`: the shared speech path — `SpeechLanguage::{En, Ru, Mn}`, phrase
  splitting (extracted from English's `to_phrases`, via its helper made `pub(crate)`), per-language
  number expansion 0–9999 (digit-by-digit + warning past it), word tokenisation with word-end
  marking, `?`⇒Question and delimiter-based pauses for ru/mn, and **diagnostics** (`guessedStress`,
  `unsupportedCharacter`, `numberOutOfRange`, `emptyText`). English goes through its unchanged
  `G2P::to_phrases` plus a diagnostics-only scan; its behaviour is untouched.
- `russian.rs`: add `number_words` + diagnostics-aware phrase builder helpers; expose a
  `word_before_explain` that also reports *how* stress was resolved (explicit / ё / dictionary /
  fallback) so the speech path can warn on guessed stress. No change to what `word_before` returns.
- `planner.rs::expand` and `ipa.rs::MULTI`: add `ʊɪ`, `øɪ`, `yɪ` (additive constants).
- Small helpers shared (`split_keeping`, `is_phrase_punct`) made `pub(crate)` — visibility only.

**WASM / UI**

- New `textPhrases { language, text }` JSON call returning `{ phrases, warnings }` (English stays
  on `g2pPhrases`-compatible output; warnings are additive). `src/wasm/engine.ts` exposes
  `speechPhrases(language, text)`; `types.ts` gains `SpeechDiagnostic`.
- `ui/speech.ts::speakText(text, { …, language })` — when `language !== "en"` the CMU dictionary is
  not loaded; the phrases and warnings come from `textPhrases`. `SpokenPlan` gains `warnings:
  string[]`. English path unchanged.
- `SpeakPanel.tsx`: a Language menu (**English / Русский / Монгол**), per-language examples,
  warnings rendered in the existing skipped-notice area, a one-line stress hint for Russian
  (`молоко́`). Language switch does not clear the text box; IPA mode is language-independent.

**CLI (`crates/chimera-cli`)**

- `render text <out> ["text"] [body] [--language en|ru|mn]` (English default, existing positional
  order kept; `--language ru|--language=ru` both accepted, and `-l` as a short form).
  Warnings → stderr; `Err` (no speakable phrases, unknown language) → exit 1 (unchanged behaviour:
  errors go to stderr and the process exits non-zero).
- New `transcribe [--language …] "text"`: prints the transcription and diagnostics without
  rendering a WAV (spec §12: get the transcription without listening to the file).

## 5. Mongolian length, and why not a new IPA symbol

`Segment::dur` is the duration override the planner already honours; `klatt_durations` would only
be bypassed for the long vowels. A long vowel is the same calibrated vowel with `dur` ≈ 1.9× the
Klatt length (compare the IPA tokenizer's `ː` = ×1.7 on its default). The internal representation
keeps `ipa: "a"` so `is_vowel` and the vowel table hit unchanged; the *displayed* transcription
appends `ː`. `ː` typed by a user in IPA mode already works (×1.7). No new phonemes, no engine
changes.

## 6. Risks (from §5.2 of the ТЗ, after the audit)

1. **Physical model, not phonology.** English voice quality on ru/mn is unproven; some sounds will
   come out wrong no matter how good the spelling rules are (Russian /ɾ/ is a documented upstream
   approximation; Mongolian /ø ʊ y ɑ/ all ride on roughly-calibrated English-vowel targets).
   Mitigation: `docs/mongolian.md` lists every approximation; native-speaker pass is a required,
   separately-tracked step (not done here).
2. **No cargo/rustup in this build sandbox** (registry + static.rust-lang.org unreachable): the
   Rust code in this branch is written against the existing patterns but is **not compiled here**;
   the TypeScript is type-checked. Running `bun run test` (or `cargo test --workspace`) on a
   machine with the toolchain is a required acceptance step, and CI should be the backstop.
3. **Warnings vs noise.** Guessing-stress warnings on every unknown word are noisy on Mongolian
   (no dictionary); Mongolian relies on its fixed first-syllable rule and stays silent, Russian
   warns. Documented, tunable.
4. **Numbers** are 0–9999 as specified, digit-by-digit (with a warning) past it; no dates,
   currencies, formulas — as the ТЗ allows for v1.
5. **Sing paths are untouched** (Russian Sing already shipped; Mongolian Sing is a follow-up that
   the module layout does not preclude).
