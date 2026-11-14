# Plan: maximally realistic voice, articulation faithful to muscle work

Draft, 2026-11-13. Target: make CHIMERA's Russian and Mongolian speech as realistic as a
physically modelled voice can be, with the articulation consistent with how human muscles
actually move. This document supersedes the "someday" sections scattered across the ru-mn docs.

## 0. What "realism" means here — and what it does not

- CHIMERA is a physical model, not a neural codec. The ceiling is *a convincing, characterful
  synthetic voice that native speakers accept as speech made by a speaker*, not indistinguishable
  from a specific human. Any plan promising the latter is lying.
- **Measured, not felt.** Every change goes through the same gates as always:
  intelligibility (Whisper WER on benchmark sentences), phone-level acoustic distance against a
  reference corpus (the `chimera compare tsp` metric, ported), listening checks by native
  speakers, `cargo test --workspace`, real-time bench. Ear-only changes are not accepted.
- **"In accordance with muscle work"**, concretely and honestly: CHIMERA has no muscle layer —
  articulators are absolute head-frame targets (`HumanArtic`, 17 DOFs) with critically damped
  2nd-order dynamics. A full neuromechanical model (DIVA-style mapping or an ArtiSynth-style
  finite-element tongue under muscle activation) is a research programme, not a sprint. The
  engineering-fidelity version, which we commit to:
  1. **coupling constraints** that reproduce passive muscle linkages (jaw→tongue, jaw→lips,
     lip rounding ↔ jaw, velum vs oral/nasal segments, larynx↔f0 factor);
  2. **time constants** per articulator refit against EMA/MRI kinematics, not only the
     VocalTractLab range the code cites today;
  3. a **documented muscle mapping** (`docs/muscles.md`): every one of the 17 DOFs and every
     calibrated target, its muscle(s) of origin, the measured range, the kinematic trend
     (EMA/rtMRI) that constrains it;
  4. **plausibility audits** of rendered trajectories against published articulatory kinematics.
  This is muscle-faithful in the sense an articulatory synthesizer can be without becoming a
  neuromuscular simulator.

- **Anti-goals.** No samples or neural models in the engine (vision doc). No reference audio in
  git (TSP convention: derived tables and alignments only). No bulk recalibration in one
  commit. No shipping this branch claiming "human-like" before native speakers sign off.

## 1. Phase 0 — References and ground truth

1.1 **RU corpus (user's AI dictors)** — inventory: id, transcript, voice name, sample rate;
  convert to 16 kHz mono WAV; `tools/ru/` layout modelled on `tools/tsp` (`sentences.tsv` +
  `alignment.tsv.gz`). Audio stays outside git in `~/datasets/ru`.
1.2 **Auto-transcribe the untranscribed half** with faster-whisper (`medium`/`large-v3`,
  `--language ru`); AI-dictor speech is clean, so accuracy will be high; spot-check ~50 files
  by ear.
1.3 **Human anchor.** AI dictors are a *consistent synthetic ideal* — great targets for
  calibration, but they bias toward one style. Add ~50–100 clips from Common Voice Russian
  (CC0) as the "human" pole. Every evaluation reports both.
1.4 **MN corpus.** Later. Common Voice Mongolian is the likely source; initial evals stay
  sentence-level (no phone alignment) because there is no off-the-shelf Mongolian MFA model.
1.5 **Reference profiles per phone** (derived, commit-able):
  MFA Russian alignment → per-phone F1/F2/F3/B1–B3 (LPC, as `compare tsp` does), duration
  histograms, H1−H2, noise-to-harmonics for fricatives, phrase declination slope.
  Output: `docs/reference-ru.md` (+ `out/reference-ru/` locally).
1.6 **Articulatory references** for Phase 4 (literature-measured, never shipped):
  EMA/rtMRI corpora — USC XRMB (x-ray microbeam), USC-TIMIT, public rtMRI sets; tongue/EMA
  kinematics literature for co-movement trends (jaw–tongue coupling, lip protrusion with
  /u/, velum timing). Record exact citations in `docs/muscles.md`.

## 2. Phase 1 — Judges before knobs

2.1 Port `compare tsp` → `chimera compare ru <datadir> [--against …]`: same measures (formant
  distance, duration ratio, sibilant levels & centroids, H1−H2, voicing, MCD); replaces the
  ARPAbet mapping with an MFA-Russian-phoneset → IPA mapping. `compare tsp` stays untouched.
2.2 Extend `tools/asr/speech_wer.py` with `--language ru` and add a RU benchmark set (borrow the
  structure of `tools/asr/sentences.tsv`). Mongolian WER only after Phase 5, via `--language mn`
  with a large model; expect worse absolute numbers — use it for relative judgements only.
2.3 **Regression harness for the synth itself:** golden WAVs for en/ru/mn (male/female/child)
  plus spectral-distance gates vs stored references; runs in the normal test suite. This is
  distinct from the WER judge and catches silent degradations.
2.4 `chimera diagnose` grows RU/MN tilt-vs-Byrne-LTS reporting if evidence supports it.

## 3. Phase 2 — Voice source (the audible lever)

3.1 Fix the known English gaps first — they apply equally to RU/MN, and the TSP judge already
  ranks them: **female sibilant levels and centroids** (/ʃ/ −23 dB re her vowels vs women's −7;
  /s/ centroid 4.7 kHz vs 7.4; /z/ 4.0 vs 7.1), **short closures and affricates** (/k/ 0.7 of a
  mean phone vs 1.1–1.2; /dʒ/ 0.5 vs 1.2–1.3), **/ð/, /v/ too loud** (7–11 dB), **male /ʃ/
  centroid overshoot** (3.48 vs 3.13 kHz), **1–4 kHz presence gap** after batch 1 (female
  1–2 kHz −16.1 dB vs women's −10.8). One hill-climb experiment per item (log.md), female
  speakers first — they fail hardest.
3.2 **Aspiration & breathiness calibration** on the stops that actually carry it: RU word-initial
  п т к, Mongolian /pʰ tʰ kʰ tsʰ tʃʰ/. Engine already has an aspiration-at-release path and the
  IPA `ʰ` flag; measure against the AI-dictor spectrograms and set the noise gain/spectrum, not
  by taste.
3.3 **Voice quality per body:** H1−H2, jitter/shimmer, aspiration noise for breathy marked
  vowels (`ʱ` machinery exists). Check against the children/women's bodies especially.
3.4 **Spectral tilt re-validation** of the body mix against long-term average speech spectra
  (Byrne et al. metrics already in `diagnose`), not just formant means.

## 4. Phase 3 — Articulation faithful to muscle work

Current state: absolute head-frame targets, second-order critically damped articulators
(time constants only "checked against" VocalTractLab's 5–40 ms range), Öhman vowel-to-vowel
coarticulation, gesture overlay for consonants, contact clamping for closures. No muscles, no
couplings, no measured-kinematics validation.

4.1 **Passive coupling constraints** (engine, `control/articulators.rs` / `control/score.rs`):
  - jaw→tongue: tongue body rides passively on jaw closure unless actively compensated
    (bound on simultaneous low-jaw/high-dorsum states);
  - jaw→lower lip raise on closure; lower lip never static while jaw moves;
  - rounding↔jaw: lip protrusion/narrowing co-varies with mid jaw, never max-open/max-round;
  - velum: closure leads oral stop/fricative onset by ~50–100 ms and releases after oral
    segments; never open for oral obstruents mid-word (check proclitics в, с, к in RU);
  - larynx height↔f0 intrinsic factor (+stiffening) — optional, default off, measured before
    enabling.
4.2 **Time constants:** refit per articulator against EMA movement data; verify attack/release
  latencies; verify no articulator overshoots past its contact clamp except where measured to.
4.3 **`docs/muscles.md` — the muscle map** (deliverable, reviewed like code):
  - extrinsic tongue: genioglossus posterior (dorsum rise/fronting ↔ `tb_y`, front),
    genioglossus anterior (tip blade ↔ `tt_*`), styloglossus & palatoglossus (dorsum back/root
    ↔ `root`), hyoglossus (outer root depress);
  - intrinsic: verticalis (central groove ↔ `groove`), transversus (dorsum raising for /i/),
    inferior/longitudinal (tip curl ↔ `tt_curl`);
  - lips: orbicularis oris (aperture/protrusion compression), buccinator/risorius (spreading),
    mentalis/depressor (lower lip);
  - jaw: masseter/temporalis/medial pterygoid (close), anterior digastric (open);
  - velum: levator veli palatini (raise), palatoglossus/palatopharyngeus (lower);
  - each DOF gets: muscle(s), fibre direction, activation phase (agonist/antagonist), measured
    EMA range, engine range, deviations noted. Exceptions documented (e.g. `dorsum` clicks,
    retroflex `tt_curl` as position, not muscle).
4.4 **Kinematic plausibility audit:** render 5–8 reference sentences (RU + MN); extract engine
  trajectories; compare co-movement trends with published EMA/rtMRI data: jaw–tongue covariance,
  lip protrusion→/u/ F2 drop, velum lead time, tongue blade recovery after stops. Fix violations;
  record every accepted deviation in `docs/muscles.md` with its reason.
4.5 **Stretch (not scheduled):** ArtiSynth-style FE tongue to generate reference surfaces for
  /i a u s t l/ and compare against engine geometry. Reference study only, never a dependency.
4.6 **RU palatalization for real:** soft consonants currently get a 25 ms /j/ glide — note this
  misplaces the F2 locus and sounds wrong next to native speech. Use the existing `ʲ` machinery
  (dorsum fronting/rise held under the consonant) for the *entire* soft series instead of the
  glide; keep /lʲ/ clear-dark split.
4.7 **MN preaspiration:** medial/final stops in native Khalkha carry preaspiration/tensity, not
  the release-aspiration the engine models. Add a glottal-opening gesture *before* closure for
  final/medial obstruents (the same flag path, pre-closure phase); validate by spectrogram vs
  dictor recordings. This alone will make words like "хүүхэд", "бүс" stop sounding Russian.

## 5. Phase 4 — Language completion

5.1 **RU:** replace English (Hillenbrand 1995) vowel calibration with RU native formant means for
  the RU vowel set (and MN means later for MN); reduction realizations (ɐ/ɪ) measured against
  corpus; STRESS table grown from corpus frequencies; Russian consonant timing measured (not
  tempered English Klatt); question intonation variants checked (руб. `Куда ты идёшь?` vs
  `Ты идёшь?`).
5.2 **MN:** weak non-initial vowels merge to [ɪ]/[ə] (never deleted); long vowels get the measured
  duration ratio; first-syllable stress contour (fall across the word) — check what the engine's
  declination can express; if nothing, add a per-word declination gesture; loanword rudiments.
5.3 **Prosody from data:** fit declination slope, pre-final lengthening, pause means from the
  dictor corpus (consistent speaker → stable estimates); question rise stays as-is.
5.4 Sing is out of scope, but nothing in this plan may degrade it (guard: existing sing guards
  and golden tests).

## 6. Phase 5 — Human validation and the sign-off

6.1 **Native listening panel** (the critical path — recruit now, not at the end): RU and MN
  native speakers; ≥20 sentences × {CHIMERA, AI dictor, real human}; ABX + MOS naturalness.
  Report both dictor-anchored and human-anchored gaps — they differ.
6.2 **Intelligibility gates:** WER per file vs dictor anchor and human anchor; accept the
  residual gap only after the panel agrees it is not confusing.
6.3 **Regression sign-off:** full suite green; spectral gates committed; `docs/ru-mn-report.md`
  rewritten to the final state; hill-climb log shows at least one complete RU batch and one MN
  batch.
6.4 **Ship criteria (this goal):** native RU MOS ≥ 3.0 with an audible, named improvement list;
  RU WER within a stated delta of the dictor anchor; MN with at least weak-vowel and
  long-vowel contrasts correctly realised (both confirmed by ear); muscles doc complete and
  audit passed; zero functional regressions vs current branch.

## 7. Phase 6 — UI support (small, optional, after the engine)

7.1 A/B player in Speak: same text rendered in EN/RU/MN back-to-back (also useful for panels).
7.2 Reference-overlay comparison: spectrogram of current render vs corpus phone (extends
  `tools/spectrogram.ts`), for hill-climb sessions.
7.3 Optionally, in the posture/anatomy view, hovering an articulator shows its muscle(s) from
  `docs/muscles.md`. Cosmetic; only if the owner wants it.

## 8. Order of work and rough effort

Part-time (~10 h/week). Effort excludes data negotiation and panel recruitment, which are the
real schedule risk.

| Milestone | Contents | Gate |
|---|---|---|
| M1 (wk 1–2) | Phases 0, 1: corpus intake, MFA RU alignment, `compare ru`, WER judge, regression harness | alignment spot-checks pass; judges print sensible numbers |
| M2 (wk 2–4) | Phase 2/3.1: sibilants, closures, /ð /v/, 1–4 kHz presence | each step: measured delta + no golden regressions; native spot-check |
| M3 (wk 4–6) | Phase 3 couplings, time constants, `docs/muscles.md`, RU palatalization, MN preaspiration | kinematic audit checklist; native listening on 10 sentences |
| M4 (wk 6–7) | RU re-calibration + prosody; MN weak vowels/long vowels/contour | panel scores RU; MN contrasts confirmed by ear |
| M5 (wk 7–8) | Phase 6: panel, sign-off, UI A/B, docs final | ship criteria §6.4 |

Stretch, unscheduled: ArtiSynth reference study; MN alignment via aeneas; singing realism.
Russian and Mongolian only — no other languages in this goal.

## 9. Risks

- **AI-dictor bias** → every eval reports the human (Common Voice/native) anchor alongside.
- **MN data scarcity** → sentence-level eval first; no alignment until an MFA/aeneas route exists;
  recruit MN community early.
- **Native listener availability** → the critical path; book them before M2 ends.
- **Calibration ceilings** → some contrasts may stay weak; document as known-limits (the way
  `russian-speech.md` does), don't ship silent approximations.
- **Determinism / real-time regressions** → bench gate on every hill-climb step; the
  `.gitignore`-safe golden harness must run before any merge.
- **Scope creep into neural audio** → not allowed by the vision doc; if the owner wants a
  human-indistinguishable voice, that is a different product (XTTS-class), to be decided
  explicitly, not to creep in.

## Definition of done

All milestones' gates pass; `docs/ru-mn-report.md` reflects the final measured state;
hill-climb log records at least one RU batch and one MN batch; `docs/muscles.md` complete with
the audit results; panel MOS and WER numbers published in the docs; no open critical
regressions; branch ready for the owner's review and merge.
