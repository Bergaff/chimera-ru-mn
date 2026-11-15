# Russian reference corpus

Raw audio is **never committed** (same convention as tools/tsp: derived tables only).

On Windows you can skip the command line: drag your audio folder onto `ru-corpus.bat` in the
repo root (the corpus goes to `corpus\ru`; pass a different destination as the second argument:
`ru-corpus.bat "D:\dictors" "G:\datasets\ru"`). Double-clicking the bat shows the usage help.
It sets up a portable Python/ffmpeg in .tools when needed and runs step 3 for you.

## Workflow

1. Put the audio anywhere (any nesting, any of .wav/.flac/.mp3/.m4a/.ogg/.aac/.wma).
2. If a recording has a transcript, drop a sidecar next to the audio with the same stem:
   `take01.txt` (plain text), `.srt` (subtitles — indices/timings stripped automatically) or
   `.json` (a `text`/`transcript`/`sentence` field, one level deep is fine).
3. Run the intake:

   ```sh
   python tools/ru/intake.py --src "D:\\dictors" --dst "G:\\datasets\\ru" --convert
   ```

   (`--dst` defaults to `<repo>/corpus/ru`, which is gitignored; use a big drive if the corpus
   is GBs — the repo should stay light. `--convert` needs ffmpeg on PATH:
   `winget install Gyan.FFmpeg`.)

4. Result: `wav/<id>.<ext>` (raw, untouched), `wav16k/<id>.wav` (16 kHz mono, for MFA),
   `sentences.tsv` (`id <TAB> text`), `intake-report.txt`.
5. Recordings without transcripts appear with empty text in sentences.tsv. On Windows, drag
   the corpus folder (the one with sentences.tsv) onto `ru-transcribe.bat` in the repo root —
   it creates .tools\whisper-venv with faster-whisper, asks for a model size
   (S/M/L, default M; the download goes into .tools\hf), transcribes the empty rows and
   checkpoints after every file. CLI equivalent:

   ```sh
   python tools/ru/transcribe.py --corpus "G:\datasets\ru" --model medium
   ```

   (clean AI-dictor speech transcribes very well; eyeball the results and fix rare words
   in place — the previous sentences.tsv is kept as sentences.tsv.bak)
6. Then prepare for alignment (drag the corpus folder onto `ru-prepare.bat` in the repo root,
   or):

   ```sh
   python tools/ru/convert16k.py --corpus "G:\datasets\ru"   # 16 kHz mono, PyAV — no ffmpeg needed
   python tools/ru/normalize.py   --corpus "G:\datasets\ru"   # sentences.mfa.tsv (numbers/symbols → words)
   ```

   The normalizer writes a separate `sentences.mfa.tsv` (your `sentences.tsv` is untouched),
   expands digits to Russian words (`690` → «шестьсот девяносто», `197,60` → «сто девяносто
   семь целых шесть десятых», `2024 год` → «две тысячи двадцать четвёртый год», `19 января`
   → «девятнадцатого января», `70%` → «семьдесят процентов»), and lists rows that look
   non-Russian (excluded — e.g. the English Raid-sponsor take) or contain long digit runs
   (check whether a phone number is meant to be read digit-by-digit).
7. MFA alignment (Windows). Double-click `setup-ru.bat` once: it installs micromamba +
   montreal-forced-aligner 3.4.3 into `.tools\mfa` (nothing on drive C:) and downloads the
   Russian MFA acoustic model v3.1.0 + dictionary v3.1.0 (CC BY 4.0; v3.1.0 G2P for
   out-of-dictionary words like brand names, best effort). The conda-forge channel is
   tried in order — upstream (conda.anaconda.org), the official https://prefix.dev/conda-forge
   mirror, and the tuna.tsinghua.edu.cn one. Each attempt starts with a wiped repodata
   cache (.tools\mfa\root\pkgs\cache) — a poisoned cache from a broken first run makes
   every channel look empty. A probe summary prints the actual first bytes each host
   returns, so if everything fails the window tells you which host serves what
   (proxy/captive portal?). Then drag the corpus folder onto `align-ru.bat`:

   ```sh
   # or:  align-ru.bat "I:\path\corpus\ru"
   ```

   It builds `mfa\corpus\<id>\` (hardlinked 16 kHz WAV + lowercased `<id>.lab`), runs
   `mfa align` with `tools/ru/mfa.yaml` (dither 0, no speaker adaptation — same convention
   as tools/tsp), and writes `tools/ru/alignment.tsv.gz` (id, tier=word|phone, start, end,
   label; sil/sp/<eps> dropped; mtime 0, so re-runs with the same result are byte-identical).
   Derived table, no audio — intended to be committed, like tools/tsp/alignment.tsv.gz.
   Utterances MFA can't align are listed at the end (OOV brand names; the English take was
   already excluded from sentences.mfa.tsv).
   If conda-forge hosts are unreachable/stubbed on your network (the error shows an empty
   channel: "python does not exist" on all mirrors), use the GitHub route instead —
   double-click `setup-ru-pixi.bat`: pixi v0.84.2 from GitHub releases installs MFA from the
   conda-forge OCI mirror on ghcr.io (`.tools\pixi`, nothing on drive C:). Diagnostics:
   double-click `ru-mfa-probe.bat` (deep byte-range probes + micromamba's own view via a
   verbose dry-run) and paste the output. `align-ru.bat` auto-detects whichever route is
   installed. Either way `MFA_ROOT_DIR=.tools\mfa\cache` keeps the model cache in-project.
   Note: if your repo lives under a non-ASCII path (e.g. `I:\химера`) and kaldi crashes
   with strange file errors, map a pure-ASCII drive once with `subst X: I:\химера` and run
   everything from `X:\` instead.
8. Next: reference profiles per phone (F1/F2/F3, durations, H1-H2, sibilant levels) and
   `chimera compare ru`. See docs/realism-plan.md (Phases 0–1).

Ids are Latin slugs (filenames transliterated from Cyrillic), unique with `-2`, `-3` suffixes.
