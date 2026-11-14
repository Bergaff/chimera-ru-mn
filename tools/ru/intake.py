#!/usr/bin/env python3
"""Intake for the Russian reference corpus: audio files + their transcripts.

Finds audio under --src (any nesting), pairs each with a sidecar transcript
(same file stem, one of .txt/.srt/.md/.json), copies everything into the corpus
layout one folder, and writes sentences.tsv for the MFA step:

    <dst>/wav/<id>.<ext>          raw audio, as provided (never committed to git)
    <dst>/sentences.tsv           id <TAB> text   (empty text = needs transcription)
    <dst>/intake-report.txt       counts, failures, next steps

With --convert and ffmpeg on PATH, also produces <dst>/wav16k/<id>.wav
(16 kHz mono PCM16, what MFA and parselmouth expect).

Usage:  python tools/ru/intake.py --src "D:\\dictors" [--dst "G:\\datasets\\ru"] [--convert]
        (defaults: --dst = <repo>/corpus/ru)
"""
import argparse, json, os, re, shutil, subprocess, sys
from pathlib import Path

AUDIO = {".wav", ".flac", ".mp3", ".m4a", ".ogg", ".aac", ".wma"}
TEXT = (".txt", ".srt", ".md", ".json")

_RU = {
    "а":"a","б":"b","в":"v","г":"g","д":"d","е":"e","ё":"yo","ж":"zh","з":"z",
    "и":"i","й":"y","к":"k","л":"l","м":"m","н":"n","о":"o","п":"p","р":"r",
    "с":"s","т":"t","у":"u","ф":"f","х":"h","ц":"ts","ч":"ch","ш":"sh",
    "щ":"shch","ъ":"","ы":"y","ь":"","э":"e","ю":"yu","я":"ya",
}

def clean_id(stem: str) -> str:
    s = "".join(_RU.get(ch, ch) for ch in stem.lower())
    s = re.sub(r"[^a-z0-9_-]+", "-", s).strip("-")
    return s or "row"

def srt_to_text(raw: str) -> str:
    lines = []
    for line in raw.splitlines():
        s = line.strip()
        if not s:
            continue
        if re.fullmatch(r"\d+", s):            # cue index
            continue
        if re.search(r"-->", s):               # timestamps
            continue
        lines.append(s)
    return " ".join(lines)

def json_to_text(raw: str):
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if isinstance(data, str):
        return data.strip()
    if isinstance(data, dict):
        for key in ("text", "transcript", "transcription", "sentence", "content", "words"):
            v = data.get(key)
            if isinstance(v, str) and v.strip():
                return v.strip()
        # shallow nested: one level of dicts
        for v in data.values():
            if isinstance(v, dict):
                got = json_to_text(json.dumps(v))
                if got:
                    return got
    return None

def sidecar_text(audio: Path):
    for ext in TEXT:
        f = audio.with_suffix(ext)
        if not f.exists():
            continue
        raw = f.read_text(encoding="utf-8", errors="replace").strip()
        if not raw:
            continue
        if ext == ".srt":
            return srt_to_text(raw)
        if ext == ".json":
            got = json_to_text(raw)
            return got or ""
        return re.sub(r"\s+", " ", raw)
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="folder with the audio (searched recursively)")
    ap.add_argument("--dst", default=None, help="corpus root (default: <repo>/corpus/ru)")
    ap.add_argument("--convert", action="store_true", help="also make 16 kHz mono PCM WAVs via ffmpeg")
    args = ap.parse_args()

    src = Path(args.src)
    if not src.is_dir():
        sys.exit(f"not a folder: {src}")
    repo = Path(__file__).resolve().parents[2]
    dst = Path(args.dst) if args.dst else repo / "corpus" / "ru"
    src_r, dst_r = src.resolve(), dst.resolve()
    try:
        inside = src_r == dst_r or dst_r.is_relative_to(src_r)
    except AttributeError:  # python < 3.9
        inside = src_r == dst_r or str(dst_r).startswith(str(src_r) + os.sep)
    if inside:
        sys.exit(f"refusing to write the corpus inside the source folder ({dst_r}); "
                 "pass --dst somewhere else or omit it (default: <repo>/corpus/ru)")

    files = sorted(p for p in src.rglob("*") if p.is_file() and p.suffix.lower() in AUDIO)
    if not files:
        sys.exit(f"no audio found under {src} (extensions: {', '.join(sorted(AUDIO))})")

    wav_dir = dst / "wav"
    wav_dir.mkdir(parents=True, exist_ok=True)
    rows, used, report = [], {}, []
    needs, failures = 0, []
    for f in files:
        base = clean_id(f.stem)
        n = used.get(base, 0) + 1
        used[base] = n
        rid = base if n == 1 else f"{base}-{n}"
        try:
            out = wav_dir / f"{rid}{f.suffix.lower()}"
            shutil.copy2(f, out)
            text = sidecar_text(f)
            rows.append((rid, text if text else ""))
            if not text:
                needs += 1
        except OSError as e:
            failures.append((str(f), str(e)))

    (dst / "sentences.tsv").write_text(
        "".join(f"{rid}\t{text}\n" for rid, text in rows), encoding="utf-8")

    if args.convert:
        w16 = dst / "wav16k"
        w16.mkdir(parents=True, exist_ok=True)
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            print("[warn] ffmpeg not found; skipping 16 kHz conversion "
                  "(winget install Gyan.FFmpeg, then re-run with --convert)")
        else:
            for rid, _ in rows:
                # original extension is whatever was copied; find it
                cand = next((p for p in wav_dir.iterdir() if p.stem == rid), None)
                if cand:
                    subprocess.run([ffmpeg, "-loglevel", "error", "-y", "-i", str(cand),
                                    "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
                                    str(w16 / f"{rid}.wav")], check=False)
            print(f"[ok] 16 kHz mono WAVs written to {w16}")

    summary = [
        f"audio files found : {len(files)}",
        f"copied into       : {wav_dir}",
        f"with transcript   : {len(rows) - needs}",
        f"needs transcribe  : {needs}  (run faster-whisper --language ru over sentences.tsv)",
        f"failures          : {len(failures)}",
        f"sentences.tsv     : {dst / 'sentences.tsv'}",
        "",
        "next steps: 1) eyeball sentences.tsv and fix wrong auto-transcripts",
        "            2) python tools/ru/intake.py --src <src> --dst <dst> --convert",
        "            3) MFA align with the Russian model (see tools/tsp for the pattern)",
    ]
    if failures:
        summary += ["", "failures:"] + [f"  {a}: {b}" for a, b in failures]
    (dst / "intake-report.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print("\n".join(summary))

if __name__ == "__main__":
    main()
