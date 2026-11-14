#!/usr/bin/env python3
"""Russian text normalization for forced alignment (MFA).

Converts digits/symbols in sentences.tsv into spoken Russian words, so the
pronunciation dictionary can actually look the words up. Writes a SEPARATE
sentences.mfa.tsv — your hand-readable sentences.tsv is never touched.

usage:  python tools/ru/normalize.py --corpus I:\\path\\corpus\\ru   (writes sentences.mfa.tsv)
        python tools/ru/normalize.py --corpus ... --check           (audit only, no writes)

Notes: ordinal agreement is approximate in the rarer corners of Russian grammar;
rows with more Latin than Cyrillic letters are EXCLUDED from the .mfa.tsv and
listed (non-Russian material has no business in this alignment).
"""

import argparse
import re
import sys
from pathlib import Path

ONES_M = ["", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"]
ONES_F = ["", "одна", "две", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"]
TEENS = ["десять", "одиннадцать", "двенадцать", "тринадцать", "четырнадцать", "пятнадцать",
         "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать"]
TENS = ["", "", "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят",
        "семьдесят", "восемьдесят", "девяносто"]
HUNDS = ["", "сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот",
         "семьсот", "восемьсот", "девятьсот"]

ORD_M = ["", "первый", "второй", "третий", "четвёртый", "пятый", "шестой",
         "седьмой", "восьмой", "девятый"]
TEENS_ORD = ["десятый", "одиннадцатый", "двенадцатый", "тринадцатый", "четырнадцатый",
             "пятнадцатый", "шестнадцатый", "семнадцатый", "восемнадцатый", "девятнадцатый"]
TENS_ORD = ["", "", "двадцатый", "тридцатый", "сороковой", "пятидесятый", "шестидесятый",
            "семидесятый", "восьмидесятый", "девяностый"]
HUNDS_ORD = ["", "сотый", "двухсотый", "трёхсотый", "четырёхсотый", "пятисотый",
             "шестисотый", "семисотый", "восьмисотый", "девятисотый"]
SCALE_FORMS = [(10**9, ("миллиард", "миллиарда", "миллиардов"), False),
               (10**6, ("миллион", "миллиона", "миллионов"), False),
               (10**3, ("тысяча", "тысячи", "тысяч"), True)]
MONTHS_GEN = ("января", "февраля", "марта", "апреля", "мая", "июня",
              "июля", "августа", "сентября", "октября", "ноября", "декабря")
DEN = {1: ("десятая", "десятых"), 2: ("сотая", "сотых"),
       3: ("тысячная", "тысячных"), 4: ("десятитысячная", "десятитысячных")}

# common abbreviations expanded as words (case-insensitive whole-word match)
ABBREVS = [("мм", "миллиметров"), ("см", "сантиметров"), ("км", "километров"),
           ("кг", "килограммов"), ("гр", "грамм"), ("руб", "рублей"),
           ("коп", "копеек"), ("млн", "миллионов"), ("млрд", "миллиардов"),
           ("тыс", "тысяч"), ("гб", "гигабайт"), ("мб", "мегабайт")]
ABBREV_RE = re.compile(r"\b(" + "|".join(a for a, _ in ABBREVS) + r")\b", re.IGNORECASE)
ABBREV_MAP = dict(ABBREVS)


def plural_ru(n, forms):
    n = abs(int(n)) % 100
    if 11 <= n <= 14:
        return forms[2]
    d = n % 10
    if d == 1:
        return forms[0]
    if 2 <= d <= 4:
        return forms[1]
    return forms[2]


def _ones(n, fem):
    return (ONES_F if fem else ONES_M)[n]


def _three_digits(n, fem):
    parts = []
    h, rem = divmod(n, 100)
    if h:
        parts.append(HUNDS[h])
    t, u = divmod(rem, 10)
    if t == 1:
        parts.append(TEENS[u])
    else:
        if t:
            parts.append(TENS[t])
        if u:
            parts.append(_ones(u, fem))
    return " ".join(parts)


def cardinal(n, fem=False):
    n = int(n)
    if n == 0:
        return "ноль"
    words = []
    rest = n
    for scale_val, forms, scale_fem in SCALE_FORMS:
        q, rest = divmod(rest, scale_val)
        if q:
            words.append(cardinal(q, fem=scale_fem) + " " + plural_ru(q, forms))
    if rest:
        words.append(_three_digits(rest, fem))
    return " ".join(words)


THOUSANDS_ORD = ["", "тысячный", "двухтысячный", "трёхтысячный", "четырёхтысячный",
                 "пятитысячный", "шеститысячный", "семитысячный", "восьмитысячный",
                 "девятитысячный"]


def ordinal_masc(n):
    n = int(n)
    if n >= 1000:
        q, r = divmod(n, 1000)
        if r == 0:
            return THOUSANDS_ORD[q] if q <= 9 else _num_plain(q) + "тысячный"
        prefix = "тысяча" if q == 1 else cardinal(q, fem=True) + " " + \
            plural_ru(q, ("тысяча", "тысячи", "тысяч"))
        return prefix + " " + ordinal_masc(r)
    h, rem = divmod(n, 100)
    if h:
        hun = h * 100
        if rem == 0:
            return HUNDS_ORD[h]
        return _num_plain(hun) + " " + ordinal_masc(rem)
    t, u = divmod(n, 10)
    if t == 1:
        return TEENS_ORD[u]
    if n < 10:
        return ORD_M[n]
    if u == 0:
        return TENS_ORD[t]
    return TENS[t] + " " + ORD_M[u]


def _num_plain(n):
    return cardinal(n, fem=False)


def to_genitive(word):
    if word.endswith("ий"):
        return word[:-2] + "ьего"
    if word.endswith(("ый", "ой")):
        return word[:-2] + "ого"
    return word


def to_prepositional(word):
    if word.endswith("ий"):
        return word[:-2] + "ем"
    if word.endswith(("ый", "ой")):
        return word[:-2] + "ом"
    return word


def ordinal_gen(n):
    words = ordinal_masc(n).split()
    words[-1] = to_genitive(words[-1])
    return " ".join(words)


def ordinal_prep(n):
    words = ordinal_masc(n).split()
    words[-1] = to_prepositional(words[-1])
    return " ".join(words)


def decimal_words(whole_s, frac_s):
    frac = frac_s.rstrip("0")
    whole = int(whole_s)
    if not frac:
        return _num_plain(whole) + " " + ("целая" if whole % 10 == 1 and whole % 100 != 11 else "целых")
    denom_len = len(frac)
    if denom_len > 4:
        frac = frac[:4]
        denom_len = 4
    frac_val = int(frac)
    if whole % 10 == 1 and whole % 100 != 11:
        whole_word = cardinal(whole, fem=True) + " целая"
    else:
        whole_word = cardinal(whole) + " целых"
    ones = frac_val % 10
    frac_word = cardinal(frac_val, fem=ones in (1, 2))
    sg, pl = DEN[denom_len]
    return f"{whole_word} {frac_word} {sg if frac_val == 1 else pl}"


def year_words(n):
    hi, rest = divmod(n, 1000)
    if hi == 1:
        prefix = "тысяча"
    elif hi:
        prefix = cardinal(hi, fem=True) + " " + plural_ru(hi, ("тысяча", "тысячи", "тысяч"))
    else:
        prefix = ""
    if rest == 0:
        if n == 2000:
            return "двухтысячный"
        return prefix.strip()
    body = ordinal_masc(rest)
    return (prefix + " " + body).strip()


def percent_words(m):
    num_s = m.group(1).replace(",", ".")
    n = float(num_s)
    if "." in num_s:
        word = decimal_words(num_s.split(".")[0], num_s.split(".")[1])
        form = "процента"
    else:
        word = cardinal(int(num_s))
        form = plural_ru(int(num_s), ("процент", "процента", "процентов"))
    return f" {word} {form} "


def normalize_text(text):
    s = text
    s = s.replace("№", " номер ")
    s = ABBREV_RE.sub(lambda m: " " + ABBREV_MAP[m.group(1).lower()] + " ", s)
    s = re.sub(r"(\d+(?:[.,]\d+)?)\s*%", percent_words, s)
    s = re.sub(r"(\d{1,2})\s+(" + "|".join(MONTHS_GEN) + r")",
               lambda m: f" {ordinal_gen(int(m.group(1)))} {m.group(2)} ", s)
    s = re.sub(r"\b(\d{3,4})\s+году\b",
               lambda m: f" {ordinal_prep(int(m.group(1)))} году ", s)
    s = re.sub(r"\b(\d{3,4})\s+год\b",
               lambda m: f" {year_words(int(m.group(1)))} год ", s)
    s = re.sub(r"\b(\d+)[.,](\d+)\b", lambda m: f" {decimal_words(m.group(1), m.group(2))} ", s)
    s = re.sub(r"\d+", lambda m: f" {cardinal(int(m.group()))} ", s)
    s = re.sub(r"[^0-9A-Za-zА-Яа-яЁё ]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def cyrillic_ratio(text):
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return 0.0
    cyr = sum(1 for c in letters if "а" <= c.lower() <= "я" or c.lower() == "ё")
    return cyr / len(letters)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", required=True, help="corpus dir with sentences.tsv")
    ap.add_argument("--check", action="store_true", help="audit only, do not write sentences.mfa.tsv")
    args = ap.parse_args()

    corpus = Path(args.corpus)
    tsv = corpus / "sentences.tsv"
    if not tsv.is_file():
        sys.exit(f"no sentences.tsv in {corpus}")

    rows = []
    for line in tsv.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t", 1)
        rid = parts[0].strip()
        if rid:
            rows.append((rid, parts[1].strip() if len(parts) > 1 else ""))

    written, skipped_empty, excluded_latin, changed, long_digits = [], [], [], 0, []
    for rid, text in rows:
        if not text:
            skipped_empty.append(rid)
            continue
        norm = normalize_text(text)
        ratio = cyrillic_ratio(text)
        if ratio < 0.5:
            excluded_latin.append((rid, ratio))
            continue
        if re.search(r"\d{5,}", text):
            long_digits.append(rid)
        if norm != re.sub(r"\s+", " ", text).strip():
            changed += 1
        written.append((rid, norm))

    print(f"rows: {len(rows)}, to write: {len(written)}, changed by normalization: {changed}")
    if skipped_empty:
        print(f"skipped (empty text): {', '.join(skipped_empty)}")
    if excluded_latin:
        print("excluded (more Latin than Cyrillic letters):")
        for rid, ratio in excluded_latin:
            print(f"  {rid}  (cyrillic ratio {ratio:.2f})")
    if long_digits:
        print("long digit runs (phone numbers read per-digit? eyeball these rows):")
        for rid in long_digits:
            print(f"  {rid}")

    if args.check:
        print("--check: nothing written")
        return

    out = corpus / "sentences.mfa.tsv"
    out.write_text("".join(f"{rid}\t{text}\n" for rid, text in written), encoding="utf-8")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
