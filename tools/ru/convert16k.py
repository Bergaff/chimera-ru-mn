#!/usr/bin/env python3
"""16 kHz mono PCM WAV conversion for the RU corpus — without ffmpeg.

Uses PyAV (already present in .tools/whisper-venv) instead of the ffmpeg
download, which kept failing with 'Access is denied' on the user's machine.

usage:  python tools/ru/convert16k.py --corpus I:\\path\\corpus\\ru
        (reads <corpus>\\wav, writes <corpus>\\wav16k\\<id>.wav; skips existing)
"""

import argparse
import sys
from pathlib import Path

AUDIO_EXTS = (".wav", ".flac", ".mp3", ".m4a", ".ogg", ".aac", ".wma")
RATE = 16000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", required=True, help="corpus dir with a wav/ folder inside")
    ap.add_argument("--force", action="store_true", help="re-convert even if the output exists")
    args = ap.parse_args()

    corpus = Path(args.corpus)
    src, dst = corpus / "wav", corpus / "wav16k"
    if not src.is_dir():
        sys.exit(f"no wav/ folder in {corpus}")
    dst.mkdir(parents=True, exist_ok=True)

    import av

    files = sorted(p for p in src.iterdir() if p.suffix.lower() in AUDIO_EXTS)
    if not files:
        sys.exit(f"no audio files in {src}")

    done, skipped, failed = 0, 0, []
    for f in files:
        out = dst / (f.stem + ".wav")
        if out.exists() and not args.force:
            skipped += 1
            continue
        try:
            with av.open(str(f)) as inp:
                stream = inp.streams.audio[0]
                resampler = av.AudioResampler(format="s16", layout="mono", rate=RATE)
                with av.open(str(out), "w", format="wav") as outp:
                    enc = outp.add_stream("pcm_s16le", rate=RATE)
                    enc.layout = "mono"
                    for frame in inp.decode(stream):
                        for rf in resampler.resample(frame):
                            for packet in enc.encode(rf):
                                outp.mux(packet)
                    for rf in resampler.resample(None):  # flush
                        for packet in enc.encode(rf):
                            outp.mux(packet)
                    for packet in enc.encode(None):  # drain encoder
                        outp.mux(packet)
            done += 1
            print(f"  [ok] {f.name} -> {out.name}", flush=True)
        except Exception as e:  # keep going, report at the end
            failed.append((f.name, str(e)))
            print(f"  [fail] {f.name}: {e}", flush=True)

    print()
    print(f"converted: {done}, skipped (already done): {skipped}, failed: {len(failed)}")
    if failed:
        print("failed files:")
        for name, err in failed:
            print(f"  {name}: {err}")
        sys.exit(1)


if __name__ == "__main__":
    main()
