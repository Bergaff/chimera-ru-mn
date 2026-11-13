/** Main-thread speech planning: text/IPA → phrases → gestural plan → worklet. */
import type { BodyMix } from "../wasm/types.ts";
import { EnglishG2P, type Phrase, type SpeechLanguage } from "../wasm/engine.ts";
import { tokenizeIpa, speechPhrases } from "../wasm/engine.ts";
import { planPhrases, type Plan, type Segment } from "../wasm/engine.ts";
import { engine } from "../audio/AudioEngine.ts";
import type { Gesture } from "../wasm/types.ts";
import { ipaPhraseTexts } from "./skipped.ts";
import { wordSpans, type WordSpan } from "./words.ts";

export const g2p = new EnglishG2P();

export interface SpokenPlan {
  plan: Plan;
  /** worklet-clock offset of the plan's time 0 (set when the worklet confirms) */
  offset: number | null;
  id: number;
  transcription: string;
  /** each word's span in the plan */
  words: WordSpan[];
  /** ready-to-show lines about what the readers could not say or had to guess */
  warnings: string[];
}

let current: SpokenPlan | null = null;
/** the plan a stop cut short: its words are no longer being said */
let cutId = -1;
const listeners = new Set<(p: SpokenPlan | null) => void>();
engine.onPlanned((m) => {
  if (current && m.id === current.id) {
    current = { ...current, offset: m.t0 };
    for (const l of listeners) l(current);
  }
});

export function onPlan(l: (p: SpokenPlan | null) => void): () => void {
  listeners.add(l);
  return () => listeners.delete(l);
}

export function currentPlan(): SpokenPlan | null {
  return current;
}

export function ipaToPhrases(text: string): Phrase[] {
  return ipaPhraseTexts(text).map((p) => ({ segments: tokenizeIpa(p), intonation: "statement" as const, pause: 0.3, words: [] }));
}

export function transcribe(phrases: { segments: Segment[]; intonation?: string }[]): string {
  return phrases.map((p) => p.segments.map((s) => (s.stress === 1 ? "ˈ" : s.stress === 2 ? "ˌ" : "") + s.ipa + (s.wordEnd ? " " : "")).join("").trim() + (p.intonation === "question" ? "?" : "")).join(" | ");
}

export function speakPhrases(phrases: { segments: Segment[]; intonation?: "statement" | "question" | "flat"; pause?: number; words?: string[] }[], o: { body: BodyMix; rate: number; f0: number }, warnings: string[] = []): SpokenPlan {
  const plan = planPhrases(phrases, { body: o.body, t0: 0, rate: o.rate, f0: o.f0 });
  const id = engine.schedule({ gestures: plan.gestures.map((g: Gesture) => ({ ...g, targets: { ...g.targets } })), segments: plan.segments, end: plan.end });
  current = { plan, offset: null, id, transcription: transcribe(phrases), words: wordSpans(phrases, plan), warnings };
  for (const l of listeners) l(current);
  return current;
}

export async function speakText(text: string, o: { ipa: boolean; body: BodyMix; rate: number; f0: number; language?: SpeechLanguage }): Promise<SpokenPlan | null> {
  if (!text.trim()) return null;
  const language = o.language ?? "en";
  let phrases: Phrase[];
  let warnings: string[] = [];
  if (o.ipa) phrases = ipaToPhrases(text);
  else {
    if (language === "en") {
      try {
        await g2p.load();
      } catch {
        // dictionary unavailable: the letter-to-sound rules still work
      }
    }
    try {
      const out = speechPhrases(language, text);
      phrases = out.phrases;
      warnings = out.warnings.map((w) => w.message);
    } catch (e) {
      // the wasm build predates `textPhrases` (the whole JSON dispatch is one match there): an
      // old engine throws on an unknown name, so let English fall back to the dictionary and
      // tell the user to rebuild for the rest
      const msg = e instanceof Error ? e.message : String(e);
      if (language === "en") {
        phrases = g2p.toPhrases(text);
        warnings = [`This engine build is older than the Speak languages: English only. Rebuild the wasm (bun run wasm) for Russian and Mongolian. (${msg})`];
      } else {
        phrases = [];
        warnings = [`Speaking ${language} needs a wasm rebuilt with this branch (bun run wasm). (${msg})`];
      }
    }
  }
  if (!phrases.length) {
    // nothing speakable: no plan to play, but the warnings belong on screen, so publish an
    // already-confirmed shell (offset 0, zero length: `speakingNow` is false from the start)
    if (!warnings.length) return null;
    current = { plan: { gestures: [], segments: [], end: 0 }, offset: 0, id: -1, transcription: "", words: [], warnings };
    for (const l of listeners) l(current);
    return current;
  }
  return speakPhrases(phrases, o, warnings);
}

export function stopSpeaking(): void {
  engine.stopSpeech();
  if (current) cutId = current.id;
}

/** Whether an utterance is sounding: scheduled (or waiting for the worklet) and not over or stopped. */
export function speakingNow(): boolean {
  const p = current;
  if (!p || p.id === cutId) return false;
  const t = engine.voiceClock();
  if (p.offset === null || t === null) return true;
  return t - p.offset < p.plan.end;
}

/** The word being spoken now (null between words and once the speech is over or stopped). */
export function spokenWordNow(): { key: string; text: string } | null {
  const p = current;
  const t = engine.voiceClock();
  if (!p || p.offset === null || t === null || p.id === cutId) return null;
  const pt = t - p.offset;
  const i = p.words.findIndex((w) => pt >= w.t0 && pt < w.t1 + 0.05);
  return i < 0 ? null : { key: `${p.id}:${i}`, text: p.words[i].text };
}
