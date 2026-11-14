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
5. Recordings without transcripts appear with empty text in sentences.tsv — transcribe them
   with `faster-whisper --language ru` (clean AI-dictor speech transcribes very well) and
   paste the text in, then eyeball a few lines.
6. Next: MFA alignment with the Russian acoustic model (same pattern as tools/tsp/setup.sh +
   align.sh, but with the GlobalPhone-based Russian model) → `alignment.tsv.gz` →
   `chimera compare ru`. See docs/realism-plan.md (Phases 0–1).

Ids are Latin slugs (filenames transliterated from Cyrillic), unique with `-2`, `-3` suffixes.
