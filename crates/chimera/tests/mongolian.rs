//! Mongolian spelling → segments (`phonetics::mongolian`), khālkha citation style.
use chimera::phonetics::mongolian;

fn ipa(segs: &[chimera::phonetics::Segment]) -> String {
    segs.iter().map(|s| s.ipa.as_str()).collect::<Vec<_>>().join(" ")
}
/// as spoken: unstressed non-initial vowels are very weak
fn said(w: &str) -> String {
    ipa(&mongolian::word(w, true))
}

#[test]
fn vowels_and_consonants() {
    assert_eq!(ipa(&mongolian::word("аоуыэи", false)), "a o u i e i");
    assert_eq!(said("эр"), "e ɾ");
    // сайн (good) and байна (are), the words every Khalkha greeting uses
    assert_eq!(said("сайн"), "s aɪ ŋ");
    assert_eq!(said("байна"), "p aɪ n ɐ");
    assert_eq!(said("уу"), "u");
}

#[test]
fn iotated_vowels_and_diphthongs() {
    // я е ё ю are /j/ + vowel; ай эй ой уй өй үй are one nucleus
    assert_eq!(said("мянга"), "m j a ŋ g ɐ");
    assert_eq!(ipa(&mongolian::word("баяр", false)), "p a j a ɾ");
    assert_eq!(said("ой"), "ɔɪ");
    // written long vowels: the same vowel with twice the length
    let uu = mongolian::word("уу", true);
    assert_eq!(uu[0].dur, Some(0.28));
    assert_eq!(uu[0].stress, Some(1));
    let aa = mongolian::word("аах", true);
    assert_eq!(ipa(&aa), "a x");
    assert_eq!(aa[0].dur, Some(0.28));
    // ий is the long и
    let ii = mongolian::word("хий", true);
    assert_eq!(ipa(&ii), "x i");
    assert_eq!(ii[0].dur, Some(0.28));
}

#[test]
fn non_initial_short_vowels_are_weak() {
    // qan: the unstressed /o/ is barely said; the stressed one is not
    assert_eq!(said("монгол"), "m o ŋ g ɐ l");
    assert_eq!(said("дөрөв"), "t ø ɾ ø w");
    // ...but never deleted, and singing keeps them full
    assert_eq!(ipa(&mongolian::word("монгол", false)), "m o ŋ g o l");
}

#[test]
fn n_is_ng_at_the_end_and_before_a_consonant() {
    assert_eq!(said("хүн"), "x y ŋ");
    assert_eq!(said("монгол"), "m o ŋ g ɐ l");
    // but n stays n before a vowel (сайн has н before a word boundary only)
    assert_eq!(said("мянга"), "m j a ŋ g ɐ");
    let first = mongolian::word("хүн", true);
    assert_eq!(first[first.len() - 1].ipa, "ŋ");
}

#[test]
fn citation_numbers() {
    assert_eq!(mongolian::number_words(0), "тэг");
    assert_eq!(mongolian::number_words(1), "нэг");
    assert_eq!(mongolian::number_words(10), "арав");
    assert_eq!(mongolian::number_words(11), "арван нэг");
    assert_eq!(mongolian::number_words(19), "арван ес");
    assert_eq!(mongolian::number_words(20), "хорь");
    assert_eq!(mongolian::number_words(21), "хорин нэг");
    assert_eq!(mongolian::number_words(45), "дөчин тав");
    assert_eq!(mongolian::number_words(99), "ерэн ес");
    assert_eq!(mongolian::number_words(100), "зуу");
    assert_eq!(mongolian::number_words(101), "зуу нэг");
    assert_eq!(mongolian::number_words(203), "хоёр зуу гурав");
    assert_eq!(mongolian::number_words(1000), "мянга");
    assert_eq!(mongolian::number_words(2000), "хоёр мянга");
    assert_eq!(mongolian::number_words(2500), "хоёр мянга таван зуу");
    assert_eq!(mongolian::number_words(5555), "таван мянга таван зуу тавин тав");
    assert_eq!(mongolian::number_words(9999), "есөн мянга есөн зуу ерэн ес");
    // out of 0–9999: read digit by digit (the speech path warns about this)
    assert_eq!(mongolian::number_words(10_000), "нэг тэг тэг тэг тэг");
}

#[test]
fn stress_is_the_first_syllable() {
    let s = mongolian::word("монгол", true);
    assert_eq!(s.iter().map(|s| s.stress).collect::<Vec<_>>(), [None, Some(1), None, None, Some(0), None]);
}
