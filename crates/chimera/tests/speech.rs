//! The shared speech path (`phonetics::speech`): phrases, warnings and number words for the
//! Speak mode and the CLI. English keeps the dictionary-based reader; Russian and Mongolian
//! are read by their own rules.
use chimera::phonetics::english::EnglishG2P;
use chimera::phonetics::Intonation;
use chimera::phonetics::speech::{SpeechLanguage, SpeechOutput, shown_transcription, speech};

fn kinds(out: &SpeechOutput) -> Vec<&str> {
    out.diagnostics.iter().map(|d| d.kind.as_str()).collect()
}

fn words(out: &SpeechOutput) -> Vec<String> {
    out.phrases.iter().flat_map(|p| p.words.iter().cloned()).collect()
}

#[test]
fn a_russian_sentence_is_spoken() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::Russian, "Привет.", &g);
    assert_eq!(out.phrases.len(), 1);
    assert_eq!(words(&out), ["Привет"]);
    assert_eq!(out.phrases[0].intonation, Intonation::Statement);
    // "Привет" is in the frequent-words table: no stress guess is reported
    assert!(!kinds(&out).contains(&"guessedStress"), "{:?}", kinds(&out));
}

#[test]
fn a_question_rises() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::Russian, "Ты тут?", &g);
    assert_eq!(out.phrases.len(), 1);
    assert_eq!(out.phrases[0].intonation, Intonation::Question);
    assert_eq!(out.phrases[0].pause, 0.35);
    assert_eq!(words(&out), ["Ты", "тут"]);
}

#[test]
fn an_explicit_stress_mark_is_not_a_guess() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::Russian, "боро́нь", &g);
    assert!(!kinds(&out).contains(&"guessedStress"), "{:?}", kinds(&out));
}

#[test]
fn a_guessed_stress_is_a_warning_not_a_silence() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::Russian, "Табак", &g);
    assert_eq!(out.phrases.len(), 1);
    let guessed = out.diagnostics.iter().find(|d| d.kind == "guessedStress").expect("a stress guess is reported");
    assert_eq!(guessed.symbols, ["Табак"]);
}

#[test]
fn numbers_are_spoken_as_words() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::Russian, "Мне 42 года", &g);
    assert_eq!(words(&out), ["Мне", "сорок", "два", "года"]);
}

#[test]
fn a_number_out_of_the_table_is_reported() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::Russian, "10000", &g);
    assert!(kinds(&out).contains(&"numberOutOfRange"), "{:?}", kinds(&out));
    assert_eq!(out.phrases.len(), 1); // said digit by digit, with a warning
}

#[test]
fn unknown_letters_are_reported() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::Russian, "abc", &g);
    assert!(out.phrases.is_empty());
    assert!(kinds(&out).contains(&"unsupportedCharacter"), "{:?}", kinds(&out));
    assert!(kinds(&out).contains(&"emptyText"), "{:?}", kinds(&out));
}

#[test]
fn mongolian_letters_in_a_russian_text_are_called_out() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::Russian, "Сайн өссөн", &g);
    assert!(kinds(&out).contains(&"mongolianLettersInRussian"), "{:?}", kinds(&out));
}

#[test]
fn mongolian_end_to_end() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::Mongolian, "Сайн байна уу?", &g);
    assert_eq!(out.phrases.len(), 1);
    assert_eq!(out.phrases[0].intonation, Intonation::Question);
    assert_eq!(words(&out), ["Сайн", "байна", "уу"]);
    assert_eq!(out.diagnostics, Vec::new(), "{:?}", out.diagnostics);
}

#[test]
fn a_bare_preposition_leans_on_the_next_word() {
    let g = EnglishG2P::new();
    // в has no vowel of its own: said as part of лесу́, keeping its own word end and word
    let out = speech(SpeechLanguage::Russian, "в лесу́", &g);
    assert_eq!(out.phrases.len(), 1);
    assert_eq!(words(&out), ["в", "лесу́"]);
    let segs = &out.phrases[0].segments;
    assert_eq!(segs[0].ipa, "v");
    assert_eq!(segs.iter().filter(|s| s.word_end == Some(true)).count(), 2, "{segs:?}");
}

#[test]
fn a_trailing_preposition_is_kept() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::Russian, "я в", &g);
    assert_eq!(out.phrases.len(), 1);
    assert_eq!(words(&out), ["я", "в"]);
}

#[test]
fn english_falls_back_to_the_rules_without_a_dictionary() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::English, "Hello", &g);
    assert_eq!(out.phrases.len(), 1);
    assert_eq!(words(&out), ["Hello"]);
}

#[test]
fn the_transcription_marks_stress_and_length() {
    let g = EnglishG2P::new();
    let out = speech(SpeechLanguage::Mongolian, "уу?", &g);
    assert_eq!(shown_transcription(&out.phrases), "ˈuː?");
    let out = speech(SpeechLanguage::Russian, "Привет.", &g);
    assert!(shown_transcription(&out.phrases).contains('ˈ'));
}

#[test]
fn number_words_are_citation_form() {
    use chimera::phonetics::russian;
    assert_eq!(russian::number_words(0), "ноль");
    assert_eq!(russian::number_words(19), "девятнадцать");
    assert_eq!(russian::number_words(25), "двадцать пять");
    assert_eq!(russian::number_words(100), "сто");
    assert_eq!(russian::number_words(203), "двести три");
    assert_eq!(russian::number_words(2000), "две тысячи");
    assert_eq!(russian::number_words(4000), "четыре тысячи");
    assert_eq!(russian::number_words(5000), "пять тысяч");
    assert_eq!(russian::number_words(4523), "четыре тысячи пятьсот двадцать три");
    assert_eq!(russian::number_words(10_000), "один ноль ноль ноль ноль");
}
