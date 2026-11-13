//! The shared speech path: text → phrases of segments for the Speak mode and the CLI, through
//! the language's own rules. English keeps its CMUdict-based `G2P::to_phrases` (untouched);
//! Russian and Mongolian use [`drive`]: the shared skeleton (numbers, phrase punctuation, pauses,
//! intonation, diagnostics) with the language's letters, word reader and number words plugged in.
//!
//! Nothing here replaces or merges with the Sing front ends (`syllables.rs`); this is the speech
//! sibling. The pipeline per the architecture note (docs/ru-mn-audit.md):
//!
//! text → language → number expansion → phrase splitting → words → segments (with stress and
//! word ends) → pauses and intonation per phrase → `Phrase` (with the words said) → planner.

use super::english::{EnglishG2P, Phrase, is_phrase_punct, js_is_space, split_keeping};
use super::mongolian;
use super::russian::{self, StressSource};
use super::{Intonation, Segment};
use serde::{Deserialize, Serialize};

/// The language Speak speaks, set by the user (never auto-detected: ru and mn share Cyrillic).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum SpeechLanguage {
    English,
    Russian,
    Mongolian,
}

impl SpeechLanguage {
    pub fn as_str(self) -> &'static str {
        match self {
            SpeechLanguage::English => "en",
            SpeechLanguage::Russian => "ru",
            SpeechLanguage::Mongolian => "mn",
        }
    }
    /// `en` | `ru` | `mn` (also the full names, for the CLI). None for anything else.
    pub fn parse(s: &str) -> Option<SpeechLanguage> {
        Some(match s.to_lowercase().as_str() {
            "en" | "eng" | "english" => SpeechLanguage::English,
            "ru" | "rus" | "russian" | "русский" => SpeechLanguage::Russian,
            "mn" | "mon" | "mongolian" | "монгол" => SpeechLanguage::Mongolian,
            _ => return None,
        })
    }
}

/// One diagnostic. Serializable for the WASM JSON call; the UI prints `message`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpeechDiagnostic {
    /// machine-readable kind: `unsupportedCharacter` | `guessedStress` | `numberOutOfRange` |
    /// `emptyText` | `mongolianLettersInRussian`
    pub kind: String,
    /// the offending characters or words (empty for `emptyText`)
    pub symbols: Vec<String>,
    /// a ready-to-show sentence
    pub message: String,
}

fn diag(kind: &str, symbols: Vec<String>, message: String) -> SpeechDiagnostic {
    SpeechDiagnostic { kind: kind.to_string(), symbols, message }
}

/// What a text read produces: the phrases to plan, and what went imperfectly along the way.
#[derive(Clone, Debug, Default)]
pub struct SpeechOutput {
    pub phrases: Vec<Phrase>,
    pub diagnostics: Vec<SpeechDiagnostic>,
}

/// Transcription as `render text` and the Speak panel show it: `ˈ` before a primary-stressed
/// vowel, `ː` on segments the reader stretched, phrases joined by ` | `, `?` for a question.
pub fn shown_transcription(phrases: &[Phrase]) -> String {
    phrases
        .iter()
        .map(|p| {
            let mut s: String = p
                .segments
                .iter()
                .map(|s| {
                    let mut t = String::new();
                    if s.stress == Some(1) {
                        t.push('ˈ');
                    } else if s.stress == Some(2) {
                        t.push('ˌ');
                    }
                    t.push_str(&s.ipa);
                    // the readers mark length with an explicit duration (mn vowels, long ts in
                    // -тся); the Klatt-timed segments stay unmarked
                    if s.dur.is_some_and(|d| d >= 0.2) {
                        t.push('ː');
                    }
                    t
                })
                .collect();
            if p.intonation == Intonation::Question {
                s.push('?');
            }
            s
        })
        .collect::<Vec<_>>()
        .join(" | ")
}

/// A character that is meaningful for every language's reader but is nobody's letter: apostrophes,
/// guillemets, dashes, and friends. They end a word silently, as whitespace does.
fn is_silent_symbol(c: char) -> bool {
    matches!(
        c,
        '«' | '»' | '“' | '”' | '„' | '‟' | '‘' | '’' | '\'' | '"' | '(' | ')' | '[' | ']' | '{' | '}'
            | '…' | '—' | '–' | '―' | '‐' | '‑' | '&' | '/' | '\\'
    )
}

/// `text` with its numbers spelled out into `number_words` (0–9999); bigger ones are read digit
/// by digit and produce a `numberOutOfRange` diagnostic.
fn expand_numbers(text: &str, name: &str, number_words: fn(u64) -> String) -> (String, Vec<SpeechDiagnostic>) {
    let mut out = String::with_capacity(text.len() * 2);
    let mut diagnostics = Vec::new();
    let mut digits = String::new();
    let mut flush = |out: &mut String, digits: &mut String, diagnostics: &mut Vec<SpeechDiagnostic>| {
        if digits.is_empty() {
            return;
        }
        let run = std::mem::take(digits);
        match run.parse::<u64>() {
            Ok(n) if n <= 9999 => out.push_str(&number_words(n)),
            _ => {
                out.push_str(&run.chars().map(|d| number_words(d.to_digit(10).unwrap_or(0) as u64)).collect::<Vec<_>>().join(" "));
                diagnostics.push(diag(
                    "numberOutOfRange",
                    vec![run.clone()],
                    format!("{name}: «{run}» is out of 0–9999; read digit by digit"),
                ));
            }
        }
        out.push(' ');
    };
    for c in text.chars() {
        if c.is_ascii_digit() {
            digits.push(c);
        } else {
            flush(&mut out, &mut digits, &mut diagnostics);
            out.push(c);
        }
    }
    flush(&mut out, &mut digits, &mut diagnostics);
    (out, diagnostics)
}

/// The per-language knobs [`drive`] needs: the letters it speaks, how to read one word (and how
/// its stress was resolved — `Some(true)`: guessed), its number words, and whether it merges a
/// bare-consonant word (a Russian preposition) into the next word.
struct LangSpec {
    name: &'static str,
    letter: fn(char) -> bool,
    /// one word and the word said after it (for prepositions) → segments, last of it is the
    /// word's end unless the caller needs the unstressed final form; plus whether stress fell
    /// back to a guess (Russian only; Mongolian returns false — its first-syllable rule is the
    /// rule, not a guess)
    word: fn(&str, Option<&str>) -> (Vec<Segment>, bool),
    number_words: fn(u64) -> String,
    proclitics: bool,
    has_vowel: fn(&str) -> bool,
}

/// One word's segments and whether its stress was a guess (Russian) — wired into [`LangSpec`].
fn russian_word(w: &str, next: Option<&str>) -> (Vec<Segment>, bool) {
    let (segs, source) = russian::word_before_explain(w, next, true);
    (segs, source == StressSource::Fallback)
}

fn mongolian_word(w: &str, next: Option<&str>) -> (Vec<Segment>, bool) {
    let (segs, _) = mongolian::word_before_explain(w, next, true);
    (segs, false)
}

const RU: LangSpec = LangSpec {
    name: "Russian",
    letter: russian::is_letter,
    word: russian_word,
    number_words: russian::number_words,
    proclitics: true,
    has_vowel: russian::has_vowel,
};

const MN: LangSpec = LangSpec {
    name: "Mongolian",
    letter: mongolian::is_letter,
    word: mongolian_word,
    number_words: mongolian::number_words,
    proclitics: false,
    has_vowel: mongolian::has_vowel,
};

/// Text → phrases for a language with no dictionary, on the shared skeleton.
fn drive(spec: &LangSpec, text: &str) -> SpeechOutput {
    let mut diagnostics = Vec::new();
    // accents people actually type: a grave or an acute accent becomes the combining acute the
    // Russian reader reads as a stress mark
    let normalized = text.replace('\u{0300}', "\u{301}").replace('\u{00B4}', "\u{301}");
    // «ө»/«ү» in a Russian text are a Mongolian letter: say so instead of silently dropping them
    if spec.name == "Russian" && contains_mongolian_letters(&normalized) {
        diagnostics.push(diag(
            "mongolianLettersInRussian",
            mongolian_letters(&normalized),
            "The text has «ө» or «ү», which Russian does not have; switch the language to Монгол to say it".to_string(),
        ));
    }
    let (expanded, number_diags) = expand_numbers(&normalized, spec.name, spec.number_words);
    diagnostics.extend(number_diags);

    let mut phrases: Vec<Phrase> = Vec::new();
    let mut words: Vec<String> = Vec::new();
    let mut unsupported: Vec<String> = Vec::new();
    let mut guessed: Vec<String> = Vec::new();

    let mut flush = |delim: &str, words: &mut Vec<String>, phrases: &mut Vec<Phrase>, guessed: &mut Vec<String>| {
        if words.is_empty() {
            return;
        }
        let mut segs: Vec<Segment> = Vec::new();
        let mut said: Vec<String> = Vec::new();
        let word_segs: Vec<(String, Vec<Segment>)> = words
            .iter()
            .enumerate()
            .map(|(i, w)| {
                let next = words.get(i + 1).map(String::as_str);
                let (mut ws, guess) = (spec.word)(w, next);
                if guess {
                    guessed.push(w.clone());
                }
                (w.clone(), std::mem::take(&mut ws))
            })
            .collect();
        // merge a bare-consonant proclitic (в, с, к…) into the next word, voiced by it: its
        // sound rides on the next word's first syllable (as in Sing). The proclitic keeps its
        // own word end and its word in `said`, so the mouth words line up one-to-one with the
        // word ends of the run.
        let mut merged: Vec<(Vec<String>, Vec<Segment>)> = Vec::with_capacity(word_segs.len());
        let mut carry: Vec<Segment> = Vec::new();
        let mut carry_words: Vec<String> = Vec::new();
        for (w, mut ws) in word_segs {
            if !carry.is_empty() {
                let mut on = std::mem::take(&mut carry);
                on.append(&mut ws);
                ws = on;
            }
            if spec.proclitics && !(spec.has_vowel)(&w) {
                // a word with no vowel cannot carry a syllable: keep its sound for the next word
                if let Some(last) = ws.last_mut() {
                    last.word_end = Some(true);
                }
                carry = ws;
                carry_words.push(w);
            } else {
                let mut words = std::mem::take(&mut carry_words);
                words.push(w);
                merged.push((words, ws));
            }
        }
        // a phrase-final proclitic has nothing to lean on: keep it on its own
        if !carry.is_empty() {
            merged.push((carry_words, carry));
        }
        for (words, mut ws) in merged {
            let Some(last) = ws.last_mut() else { continue };
            last.word_end = Some(true);
            segs.append(&mut ws);
            said.extend(words);
        }
        words.clear();
        if segs.is_empty() {
            return;
        }
        let q = delim.contains('?');
        let pause = if delim.contains(['.', '!', '?']) {
            0.35
        } else if !delim.is_empty() {
            0.18
        } else {
            0.3
        };
        phrases.push(Phrase {
            segments: segs,
            intonation: if q { Intonation::Question } else { Intonation::Statement },
            pause,
            words: said,
        });
    };

    for part in split_keeping(&expanded, is_phrase_punct) {
        if part.is_empty() {
            continue;
        }
        if part.chars().all(is_phrase_punct) {
            flush(&part, &mut words, &mut phrases, &mut guessed);
            continue;
        }
        // tokenise the part into words: letters, the combining stress mark and hyphens between
        // letters; other letters the reader does not know are collected as a diagnostic
        let mut cur = String::new();
        let mut end_word = |cur: &mut String, words: &mut Vec<String>| {
            let w = cur.trim_matches('-').to_string();
            if !w.is_empty() {
                words.push(w);
            }
            cur.clear();
        };
        for c in part.chars() {
            if (spec.letter)(c) || c == '\u{301}' || c == '-' {
                cur.push(c);
            } else if js_is_space(c) || is_silent_symbol(c) {
                end_word(&mut cur, &mut words);
            } else {
                // any alphabetic character the reader does not know is a word the reader skips:
                // report it, don't silently drop it
                if c.is_alphabetic() && !unsupported.contains(&c.to_string()) {
                    unsupported.push(c.to_string());
                }
                end_word(&mut cur, &mut words);
            }
        }
        end_word(&mut cur, &mut words);
    }
    flush("", &mut words, &mut phrases, &mut guessed);

    if !unsupported.is_empty() {
        diagnostics.push(diag(
            "unsupportedCharacter",
            unsupported.clone(),
            format!("{}: not a letter this reader knows: {}", spec.name, unsupported.join(" ")),
        ));
    }
    guessed.sort();
    guessed.dedup();
    if !guessed.is_empty() {
        diagnostics.push(diag(
            "guessedStress",
            guessed.clone(),
            format!(
                "{}: stress is not known for: {} — guessed (first vowel); mark it with a combining acute (молоко́)",
                spec.name,
                guessed.join(", ")
            ),
        ));
    }
    if phrases.is_empty() && normalized.chars().any(char::is_alphabetic) {
        diagnostics.push(diag(
            "emptyText",
            Vec::new(),
            format!("{}: nothing to say — the text has no words this reader knows", spec.name),
        ));
    }
    SpeechOutput { phrases, diagnostics }
}

fn contains_mongolian_letters(text: &str) -> bool {
    text.chars().any(|c| matches!(c, 'ө' | 'Ө' | 'ү' | 'Ү'))
}
fn mongolian_letters(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    for c in text.chars() {
        if matches!(c, 'ө' | 'Ө' | 'ү' | 'Ү') && !out.contains(&c.to_string()) {
            out.push(c.to_string());
        }
    }
    out
}

/// Text → phrases and diagnostics for `lang`. English goes through the dictionary-based reader
/// (unchanged); Russian and Mongolian through [`drive`]. Never panics, never fails silently: if
/// nothing speakable is found, `diagnostics` carries `emptyText` and `phrases` is empty.
pub fn speech(lang: SpeechLanguage, text: &str, g2p: &EnglishG2P) -> SpeechOutput {
    match lang {
        SpeechLanguage::English => {
            let normalized = text.replace('\u{0300}', "\u{301}").replace('\u{00B4}', "\u{301}");
            let phrases = g2p.to_phrases(&normalized);
            let mut unsupported: Vec<String> = Vec::new();
            for c in normalized.chars() {
                // what the English reader splits on but does not speak: non-Latin letters
                if c.is_alphabetic() && !c.is_ascii() && !unsupported.contains(&c.to_string()) {
                    unsupported.push(c.to_string());
                }
            }
            let mut diagnostics = Vec::new();
            if !unsupported.is_empty() {
                diagnostics.push(diag(
                    "unsupportedCharacter",
                    unsupported.clone(),
                    format!("English: characters it skipped: {}", unsupported.join(" ")),
                ));
            }
            if phrases.is_empty() && normalized.chars().any(char::is_alphabetic) {
                diagnostics.push(diag("emptyText", Vec::new(), "English: nothing to say — the text has no words".to_string()));
            }
            SpeechOutput { phrases, diagnostics }
        }
        SpeechLanguage::Russian => drive(&RU, text),
        SpeechLanguage::Mongolian => drive(&MN, text),
    }
}
