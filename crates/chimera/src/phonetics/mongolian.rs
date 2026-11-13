//! Mongolian spelling (Khalkha, Cyrillic) → the existing inventory. See docs/mongolian.md for the
//! rules, the sources and what is approximate.
//!
//! Literary Khalkha as reflected in modern Cyrillic: seven vowels with phonemic length
//! (и э а о ө у ү, written double when long, ий for long и), four+two diphthongs written with й
//! (ай эй ой уй өй үй), initial syllable stress, long vowels in every syllable but usually the
//! first, and non-initial short vowels that are very weak. Consonants contrast an aspirated
//! (п т ц ч к, written without a voice-mark difference) and a voiceless unaspirated series (б д з
//! ж), plus г which is functionally voiced. н is [ŋ] at the end of a word and before a consonant.
//!
//! Approximations (docs/mongolian.md has the full list): the aspiration is modelled as post-release
//! aspiration, not the Khalkha preaspiration/tensity of medial and final stops; р is one tap;
//! softness before яеёю and ь is the Russian-style 25 ms /j/ glide; a long vowel is the same
//! calibrated vowel with `dur` ≈ 1.9× the base, not a second vowel; unstressed non-initial vowels
//! are shortened and centred, never deleted.
use super::Segment;

/// a long vowel is roughly twice a short one
const LONG_VOWEL: f64 = 0.28;
/// a non-initial short vowel is barely said in running speech
const WEAK_VOWEL: f64 = 0.07;

pub fn is_letter(c: char) -> bool {
    matches!(c, 'а'..='я' | 'А'..='Я' | 'ё' | 'Ё' | 'ө' | 'Ө' | 'ү' | 'Ү')
}
pub fn contains_mongolian(s: &str) -> bool {
    s.chars().any(|c| matches!(c, 'ө' | 'Ө' | 'ү' | 'Ү'))
}
fn vowel(c: char) -> bool {
    "аэиоуөүяеёиюы".contains(c)
}
pub fn has_vowel(s: &str) -> bool {
    s.chars().any(|c| c.to_lowercase().any(vowel))
}

/// Onsets for the lyric syllabifier (not wired up yet; Sing for Mongolian is a follow-up).
/// Onsets keep the whole cluster, except a leading sonorant stays on the previous syllable.
pub fn is_onset(cluster: &[Segment]) -> bool {
    let first = cluster.first().map(|s| s.ipa.as_str());
    let consonants = cluster.iter().enumerate().filter(|(i, s)| *i == 0 || s.ipa != "j").count();
    consonants == 1 || first.is_some_and(|c| !["ɾ", "l", "n", "m", "j"].contains(&c))
}

/// The diphthong written vowel + й (а́й, э́й, о́й, у́й, ө́й, ү́й); the nucleus is one segment.
fn diphthong(first: char) -> Option<&'static str> {
    Some(match first {
        'а' | 'я' => "aɪ",
        'э' | 'е' => "eɪ",
        'о' | 'ё' => "ɔɪ",
        'у' | 'ю' => "ʊɪ",
        'ө' => "øɪ",
        'ү' => "yɪ",
        _ => return None,
    })
}

/// The monophthong behind a vowel letter, before length and reduction.
fn base_vowel(c: char) -> &'static str {
    match c {
            'а' | 'я' => "a",
        'э' | 'е' => "e",
        'и' | 'ы' => "i",
        'о' | 'ё' => "o",
        'ө' => "ø",
        'у' | 'ю' => "u",
        'ү' => "y",
        _ => unreachable!(),
    }
}

/// The reduced (weak) counterpart of a short vowel in a non-initial syllable.
fn weak_vowel(c: char) -> &'static str {
    match c {
        'а' | 'я' | 'о' | 'ё' => "ɐ",
        'э' | 'е' => "ɪ",
        _ => base_vowel(c), // и ы у ү ө ю: the tongue hardly moves, the vowel is short instead
    }
}

/// One word → segments. `next` is the word said after it (unused for now; Mongolian has no
/// enclitics that voice across the boundary — kept for symmetry with the Russian reader and a
/// future weak-vowel-drop rule).
pub fn word(input: &str, reduce: bool) -> Vec<Segment> {
    word_before(input, None, reduce)
}

/// [`word`], and whether the stress guess had to intervene (never for Mongolian: stress is fixed
/// on the first syllable, so `StressNote::Fixed` is returned — reported so the speech path knows
/// it did not guess).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum StressNote {
    /// explicit mark (loanwords, dictionary overrides)
    Explicit,
    /// the fixed first-syllable stress (correct for native Khalkha words)
    Fixed,
}

pub fn word_before(input: &str, next: Option<&str>, reduce: bool) -> Vec<Segment> {
    word_before_explain(input, next, reduce).0
}

/// [`word_before`], and how the stress was resolved.
pub fn word_before_explain(input: &str, _next: Option<&str>, reduce: bool) -> (Vec<Segment>, StressNote) {
    if input.contains('-') {
        let parts: Vec<&str> = input.split('-').filter(|p| !p.is_empty()).collect();
        let mut out = Vec::new();
        let mut note = StressNote::Fixed;
        for p in &parts {
            let (segs, n) = word_before_explain(p, _next, reduce);
            if n == StressNote::Explicit {
                note = StressNote::Explicit;
            }
            out.extend(segs);
        }
        return (out, note);
    }
    let lower = input.to_lowercase().replace("е\u{308}", "ё").replace("у\u{308}", "ү").replace("о\u{308}", "ө");
    let mut letters = Vec::new();
    let mut explicit = None;
    for c in lower.chars() {
        if c == '\u{301}' {
            if letters.last().copied().is_some_and(vowel) {
                explicit = Some(letters.len() - 1);
            }
        } else if is_letter(c) {
            letters.push(c);
        }
    }
    let n = letters.len();
    let stress = explicit.or_else(|| letters.iter().position(|&c| vowel(c)));
    let note = if explicit.is_some() { StressNote::Explicit } else { StressNote::Fixed };

    let mut out: Vec<Segment> = Vec::new();
    let mut long_next = false; // the previous vowel was written doubled: handled at it, skip this letter
    let mut i = 0;
    while i < n {
        let at = i;
        let c = letters[i];
        let prev = i.checked_sub(1).map(|p| letters[p]);
        let next_c = letters.get(i + 1).copied();
        i += 1;
        // the second letter of a written long vowel (аа) or of ий: said with the first
        if long_next {
            long_next = false;
            continue;
        }
        if vowel(c) {
            // й carries the offglide: и + й is the long и, another vowel + й a diphthong
            // (ай эй ой уй өй үй). The й is consumed with its vowel.
            let followed_by_j = next_c == Some('й');
            // iotated letters at the start of a word, after a vowel or after ьъ are /j/ + vowel;
            // after a consonant they palatalize it (the soft glide is added there, as in Russian)
            let iotated = "яеёю".contains(c) && prev.is_none_or(|p| vowel(p) || "ьъй".contains(p));
            if iotated {
                out.push(Segment::new("j"));
            }
            let stressed = stress == Some(at);
            if followed_by_j {
                long_next = true; // the й belongs to this nucleus
                if c == 'и' || c == 'ы' {
                    // ий (and ый, a Russian spelling habit): the long и
                    out.push(Segment { stress: Some(u8::from(stressed)), dur: Some(LONG_VOWEL), ..Segment::new("i") });
                } else {
                    out.push(Segment { ipa: diphthong(c).unwrap_or("aɪ").to_string(), stress: Some(u8::from(stressed)), ..Default::default() });
                }
                continue;
            }
            // written double: long (аа оо уу ээ өө үү)
            let doubled = next_c == Some(c);
            if doubled {
                long_next = true;
            }
            let weak = reduce && !stressed && !doubled;
            let ipa = if weak { weak_vowel(c) } else { base_vowel(c) };
            let mut seg = Segment { stress: Some(u8::from(stressed)), ..Segment::new(ipa) };
            if doubled {
                seg.dur = Some(LONG_VOWEL);
            } else if weak {
                seg.dur = Some(WEAK_VOWEL);
            }
            out.push(seg);
            continue;
        }
        // consonants
        if c == 'ь' || c == 'ъ' {
            continue; // the palatalization is added with the consonant before it
        }
        if c == 'й' {
            // consumed as part of a diphthong or long и above; elsewhere a /j/ (loanwords)
            out.push(Segment::new("j"));
            continue;
        }
        // doubled consonant (loans): one consonant, long between vowels
        let doubled = next_c == Some(c) && !"ьъй".contains(c);
        if doubled {
            i += 1;
        }
        let after_vowel = prev.is_some_and(vowel);
        let next_vowel = next_c.is_some_and(vowel);
        // яеёю are iotated (and carry the glide themselves after a vowel); after a consonant the
        // glide is the whole of the softness (Mongolian consonants are not palatalized before и)
        let soft = next_c.is_some_and(|x| "яеёю".contains(x) || x == 'ь');
        let (ipa, aspirated): (&'static str, Option<bool>) = match c {
            'б' => ("p", Some(false)),
            'п' => ("p", Some(true)),
            'д' => ("t", Some(false)),
            'т' => ("t", Some(true)),
            'г' => ("g", None),
            'к' => ("k", Some(true)),
            'ц' => ("ts", Some(true)),
            'ч' => ("tʃ", Some(true)),
            'ж' => ("tʃ", Some(false)),
            'з' => ("ts", Some(false)),
            'с' => ("s", None),
            'в' => ("w", None),
            'ф' => ("f", None),
            'х' => ("x", None),
            'ш' | 'щ' => ("ʃ", None),
            'л' => ("l", None),
            'р' => ("ɾ", None),
            'м' => ("m", None),
            'н' => {
                // [ŋ] at a word's end and before a consonant — but not before й (ай stays [aɪ])
                let before_consonant = next_c.is_some_and(|x| is_letter(x) && !vowel(x) && x != 'й' && x != 'ь' && x != 'ъ');
                if next_c.is_none() || before_consonant {
                    ("ŋ", None)
                } else {
                    ("n", None)
                }
            }
            _ => ("?", None),
        };
        let mut seg = Segment { aspirated, ..Segment::new(ipa) };
        if doubled && after_vowel && next_vowel {
            // a long consonant between vowels (loans): absolute timing, as the readers use
            seg.dur = Some(0.16);
        }
        out.push(seg);
        // яеёю (and ь) palatalize the consonant before them: a short /j/ glide, as in Russian
        if soft {
            out.push(Segment { dur: Some(0.025), ..Segment::new("j") });
        }
    }
    (out, note)
}

const ONES: [&str; 10] = ["тэг", "нэг", "хоёр", "гурав", "дөрөв", "тав", "зургаа", "долоо", "найм", "ес"];
/// units as they stand before зуу and мянга (attributive -н)
const ATTR_ONES: [&str; 10] = ["", "нэг", "хоёр", "гурван", "дөрвөн", "таван", "зургаан", "долоон", "найман", "есөн"];
/// tens, attributive (хорин, гучин, дөчин…), as they stand before a unit
const ATTR_TENS: [&str; 10] = ["", "", "хорин", "гучин", "дөчин", "тавин", "жаран", "далан", "наян", "ерэн"];
/// tens alone (хорь, гуч, дөч…)
const TENS: [&str; 10] = ["", "", "хорь", "гуч", "дөч", "тавь", "жар", "дал", "ная", "ер"];

fn under_thousand(n: u64) -> String {
    if n < 10 {
        return ONES[n as usize].to_string();
    }
    if n == 10 {
        return "арав".to_string();
    }
    if n < 20 {
        return format!("арван {}", ONES[(n - 10) as usize]);
    }
    let (t, r) = ((n / 10) as usize, n % 10);
    if r == 0 {
        return TENS[t].to_string();
    }
    format!("{} {}", ATTR_TENS[t], ONES[r as usize])
}

/// A whole number 0–9999 as Mongolian words (citation; compound tens take the attributive -н,
/// e.g. «хорин нэг»). Larger numbers are read digit by digit by the speech path, with a warning.
pub fn number_words(n: u64) -> String {
    if n > 9999 {
        return n.to_string().chars().map(|d| ONES[d.to_digit(10).unwrap_or(0) as usize]).collect::<Vec<_>>().join(" ");
    }
    let (t, r) = (n / 1000, n % 1000);
    let mut out = String::new();
    if t > 0 {
        if t == 1 {
            out.push_str("мянга");
        } else {
            out.push_str(&format!("{} мянга", ATTR_ONES[t as usize]));
        }
        if r > 0 {
            out.push(' ');
        }
    }
    if r >= 100 {
        let h = (r / 100) as usize;
        if h == 1 {
            out.push_str("зуу");
        } else {
            out.push_str(&format!("{} зуу", ATTR_ONES[h]));
        }
        let rr = r % 100;
        if rr > 0 {
            out.push(' ');
            out.push_str(&under_thousand(rr));
        }
    } else if r > 0 {
        out.push_str(&under_thousand(r));
    }
    if out.is_empty() {
        "тэг".to_string()
    } else {
        out
    }
}
