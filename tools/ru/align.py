#!/usr/bin/env python3
"""Phone alignment of the RU reference corpus (the AI dictors), same shape as tools/tsp/align.py.

  align.py prepare <corpus-dir> <mfa-corpus-dir>   sentences.mfa.tsv + wav16k/ -> MFA corpus
                                                   (one directory per utterance)
  align.py collect <mfa-out-dir>                   MFA JSON -> tools/ru/alignment.tsv.gz

corpus/sentences.mfa.tsv: id \t text (digits already expanded to words by normalize.py).
wav16k/<id>.wav must exist (ru-prepare.bat). Text is lowercased in the .lab files:
the Russian MFA dictionary is lowercase.
alignment.tsv.gz: id, tier (word | phone), start (s), end (s), label; silences dropped;
mtime 0 and empty filename, so a rerun with the same result is byte-identical.
"""

import gzip
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def read_rows(corpus):
    rows = []
    with open(os.path.join(corpus, "sentences.mfa.tsv"), encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t", 1)
            rid = parts[0].strip()
            if rid:
                rows.append((rid, parts[1].strip() if len(parts) > 1 else ""))
    return rows


def prepare(corpus, out_corpus):
    rows = read_rows(corpus)
    src_dir = os.path.join(corpus, "wav16k")
    missing = [rid for rid, _ in rows
               if not os.path.isfile(os.path.join(src_dir, rid + ".wav"))]
    if missing:
        sys.exit(f"wav16k/ missing for {len(missing)} ids ({', '.join(missing)}); "
                 "run ru-prepare.bat first")
    for rid, text in rows:
        os.makedirs(os.path.join(out_corpus, rid), exist_ok=True)
        link = os.path.join(out_corpus, rid, rid + ".wav")
        src = os.path.join(src_dir, rid + ".wav")
        if not os.path.lexists(link):
            try:
                os.link(src, link)  # same volume, cheap
            except OSError:
                shutil.copy2(src, link)
        with open(os.path.join(out_corpus, rid, rid + ".lab"), "w", encoding="utf-8") as f:
            f.write(text.lower() + "\n")
    print(f"{len(rows)} utterances prepared in {out_corpus}")


def collect(out, corpus=None):
    jsons = []
    for dirpath, _, files in os.walk(out):
        for name in files:
            if name.endswith(".json"):
                jsons.append(os.path.join(dirpath, name))
    lines, failed = [], []
    seen = set()
    for path in sorted(jsons):
        utt = os.path.splitext(os.path.basename(path))[0]
        seen.add(utt)
        try:
            with open(path, encoding="utf-8") as f:
                tiers = json.load(f)["tiers"]
        except Exception as e:
            failed.append(f"{utt} ({e})")
            continue
        for tier, name in (("words", "word"), ("phones", "phone")):
            for entry in tiers.get(tier, {}).get("entries", []):
                if len(entry) != 3:
                    continue
                start, end, label = entry
                if label in ("", "sil", "sp", "<eps>"):
                    continue
                lines.append(f"{utt}\t{name}\t{float(start):.3f}\t{float(end):.3f}\t{label}")
    missing = []
    if corpus:
        want = [rid for rid, _ in read_rows(corpus)]
        missing = [u for u in want if u not in seen]
    with open(os.path.join(HERE, "alignment.tsv.gz"), "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0, filename="") as f:
            f.write(("\n".join(lines) + "\n").encode())
    report = f"aligned: {len(seen) - len(failed)}/{len(seen)} utterances; "
    report += f"failed json: {', '.join(failed) if failed else 'none'}; missing: "
    report += ", ".join(missing) if missing else "none"
    print(report)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "prepare":
        prepare(sys.argv[2], sys.argv[3])
    elif cmd == "collect":
        collect(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    else:
        raise SystemExit(__doc__)
