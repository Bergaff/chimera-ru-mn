#!/usr/bin/env python3
"""Fill in the empty texts in corpus sentences.tsv with faster-whisper.

Usage:  python tools/ru/transcribe.py --corpus I:\\path\\corpus\\ru [--model medium] [--all]
        (--model: small | medium | large-v3; default medium)
        (--all re-transcribes rows that already have text; default: only empty rows)

The model downloads once from HuggingFace (HF_HOME or <repo>/.tools/hf) and
lands in the project folder. Raw audio never leaves your machine otherwise.
"""

import argparse
import os
import re
import sys
from pathlib import Path

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

REPO = Path(__file__).resolve().parents[2]
os.environ.setdefault("HF_HOME", str(REPO / ".tools" / "hf"))

AUDIO_EXTS = (".wav", ".flac", ".mp3", ".m4a", ".ogg", ".aac", ".wma")


def decode_audio(path):
    """Decode to 16 kHz mono float32 numpy — same as faster-whisper's decode_audio
    but without the metadata_errors kwarg that older PyAV builds don't accept."""
    import av
    import numpy as np

    with av.open(str(path)) as container:
        stream = container.streams.audio[0]
        resampler = av.AudioResampler(format="flt", layout="mono", rate=16000)
        chunks = []
        for frame in container.decode(stream):
            for rf in resampler.resample(frame):
                chunks.append(rf.to_ndarray().reshape(1, -1))
        for rf in resampler.resample(None):  # flush
            chunks.append(rf.to_ndarray().reshape(1, -1))
    if not chunks:
        raise RuntimeError(f"no audio decoded from {path}")
    return np.concatenate(chunks, axis=1)[0].astype(np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", required=True, help="corpus dir with sentences.tsv and wav/")
    ap.add_argument("--model", default="medium", choices=["small", "medium", "large-v3"])
    ap.add_argument("--language", default="ru")
    ap.add_argument("--all", action="store_true", help="re-transcribe rows that already have text")
    args = ap.parse_args()

    corpus = Path(args.corpus)
    tsv = corpus / "sentences.tsv"
    wav_dir = corpus / "wav"
    if not tsv.is_file():
        sys.exit(f"no sentences.tsv in {corpus}")
    if not wav_dir.is_dir():
        sys.exit(f"no wav/ folder in {corpus}")

    rows = []
    for line in tsv.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t", 1)
        rid = parts[0].strip()
        if not rid:
            continue
        text = parts[1].strip() if len(parts) > 1 else ""
        rows.append([rid, text])

    todo = [i for i, (rid, text) in enumerate(rows) if args.all or not text]
    if not todo:
        print("nothing to do: every row already has a transcript (use --all to redo)")
        return

    from faster_whisper import WhisperModel

    print(f"loading faster-whisper model '{args.model}' (downloads on first run) ...")
    model = WhisperModel(args.model, device="cpu", compute_type="int8")

    tsv.with_suffix(".tsv.bak").write_text(
        "".join(f"{rid}\t{text}\n" for rid, text in rows), encoding="utf-8")

    done = 0
    for i in todo:
        rid, _ = rows[i]
        audio = next((wav_dir / f"{rid}{e}" for e in AUDIO_EXTS if (wav_dir / f"{rid}{e}").exists()), None)
        if audio is None:
            print(f"  [skip] {rid}: no audio file found in wav/")
            continue
        print(f"  [{done + 1}/{len(todo)}] transcribing {rid} ...", flush=True)
        segments, _ = model.transcribe(
            decode_audio(audio), language=args.language, beam_size=5, vad_filter=False)
        text = " ".join(seg.text.strip() for seg in segments)
        text = re.sub(r"\s+", " ", text).replace("\t", " ").strip()
        rows[i][1] = text
        done += 1
        # checkpoint after every file so Ctrl+C loses nothing
        tsv.write_text("".join(f"{r}\t{t}\n" for r, t in rows), encoding="utf-8")

    print()
    print(f"done: {done}/{len(todo)} transcribed; backup of the old file: {tsv}.bak")
    empty = sum(1 for _, t in rows if not t)
    if empty:
        print(f"still empty: {empty} (skipped files or silence)")
    print("review the auto-transcripts in sentences.tsv - clean AI narration transcribes well,")
    print("but eyeball rare words and punctuation; fix in place, then step 6 in tools/ru/README.md")


if __name__ == "__main__":
    main()
