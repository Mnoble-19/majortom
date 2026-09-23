"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";

/* ── Demo material ────────────────────────────────────────────────────────── */

type DemoCue = {
  de: string;
  en: string;
  /** Word → gloss, keyed lowercase and unpunctuated. */
  gloss: Record<string, string>;
};

const CUES: DemoCue[] = [
  {
    de: "Ich habe die ganze Nacht kein Auge zugetan.",
    en: "I didn't sleep a wink all night.",
    gloss: {
      ich: "I",
      habe: "have",
      die: "the",
      ganze: "whole, entire",
      nacht: "night",
      kein: "no, not a",
      auge: "eye",
      zugetan: "closed — kein Auge zutun: not sleep a wink",
    },
  },
  {
    de: "Der Zug fährt in zwei Minuten ab.",
    en: "The train leaves in two minutes.",
    gloss: {
      der: "the",
      zug: "train",
      fährt: "goes, departs",
      in: "in",
      zwei: "two",
      minuten: "minutes",
      ab: "off, away — separable prefix of abfahren",
    },
  },
  {
    de: "Das hätte ich mir denken können.",
    en: "I should have known.",
    gloss: {
      das: "that",
      hätte: "would have",
      ich: "I",
      mir: "to myself",
      denken: "to think",
      können: "to be able to",
    },
  },
  {
    de: "Wir sehen uns morgen früh am Bahnhof.",
    en: "We'll see each other tomorrow morning at the station.",
    gloss: {
      wir: "we",
      sehen: "see",
      uns: "each other",
      morgen: "tomorrow",
      früh: "early",
      am: "at the",
      bahnhof: "station",
    },
  },
];

const CUE_MS = 5200;
const NOISE =
  "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='3'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")";

/** Split into words and the punctuation between them, keeping both. */
function tokenize(line: string) {
  return line.match(/[\p{L}\p{N}]+(?:['’-][\p{L}\p{N}]+)*|[^\p{L}\p{N}]+/gu) ?? [];
}

const isWord = (t: string) => /[\p{L}\p{N}]/u.test(t);
const key = (t: string) => t.toLowerCase().replace(/[^\p{L}\p{N}'’-]/gu, "");

/* ── Component ────────────────────────────────────────────────────────────── */

type CardState = { word: string; gloss: string; x: number } | null;

export function SubtitleStage() {
  const [index, setIndex] = useState(0);
  const [saved, setSaved] = useState<Set<string>>(new Set());
  const [card, setCard] = useState<CardState>(null);
  const [blur, setBlur] = useState(false);
  const [autoPause, setAutoPause] = useState(false);
  const [progress, setProgress] = useState(0);

  const lineRef = useRef<HTMLParagraphElement | null>(null);
  const cue = CUES[index];

  /* The reel only runs while nothing is being inspected — opening a lookup card
     is the user taking over, and yanking the line away under them would be
     rude. */
  const held = card !== null;

  useEffect(() => {
    if (held) return;
    const started = performance.now() - progress * CUE_MS;
    let raf = 0;

    const step = (now: number) => {
      const p = Math.min(1, (now - started) / CUE_MS);
      setProgress(p);
      if (p >= 1) {
        setIndex((i) => (i + 1) % CUES.length);
        setProgress(0);
        return;
      }
      raf = requestAnimationFrame(step);
    };

    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
    // `progress` is intentionally read once, at the moment the reel resumes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [held, index]);

  const go = useCallback((delta: number) => {
    setCard(null);
    setProgress(0);
    setIndex((i) => (i + delta + CUES.length) % CUES.length);
  }, []);

  const openCard = useCallback((el: HTMLElement, word: string, gloss: string) => {
    const line = lineRef.current;
    if (!line) return;
    const a = el.getBoundingClientRect();
    const b = line.getBoundingClientRect();
    setCard({ word, gloss, x: a.left - b.left + a.width / 2 });
  }, []);

  const toggleSave = useCallback((word: string) => {
    setSaved((prev) => {
      const next = new Set(prev);
      if (next.has(word)) next.delete(word);
      else next.add(word);
      return next;
    });
  }, []);

  // Escape closes the card, as it does in the extension.
  useEffect(() => {
    if (!card) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setCard(null);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [card]);

  const elapsed = ((index + progress) / CUES.length) * 184 + 540;

  return (
    <figure className="m-0">
      <div className="relative overflow-hidden rounded-[1.25rem] border border-line-strong bg-black shadow-[0_40px_120px_-40px_rgba(0,0,0,0.9)]">
        {/* Stand-in for the video itself: a lit night interior, in gradients. */}
        <div className="relative aspect-[16/9] w-full">
          <div
            aria-hidden
            className="absolute inset-0 bg-[linear-gradient(158deg,#191922_0%,#0e0e13_48%,#08080a_100%)]"
          />
          <div
            aria-hidden
            className="absolute -top-[18%] -left-[6%] h-[62%] w-[52%] rounded-full opacity-55 blur-[80px]"
            style={{ background: "radial-gradient(circle, #2f5f78 0%, transparent 68%)" }}
          />
          <div
            aria-hidden
            className="absolute -right-[10%] bottom-[6%] h-[70%] w-[46%] rounded-full opacity-40 blur-[90px]"
            style={{ background: "radial-gradient(circle, #7a5322 0%, transparent 70%)" }}
          />
          <div
            aria-hidden
            className="absolute inset-0 opacity-[0.16] mix-blend-overlay"
            style={{ backgroundImage: NOISE }}
          />
          <div
            aria-hidden
            className="absolute inset-0"
            style={{
              background:
                "radial-gradient(ellipse at 50% 45%, transparent 38%, rgba(0,0,0,0.62) 100%)",
            }}
          />

          {/* ── The overlay, as the extension draws it ───────────────────── */}
          <div className="group absolute inset-x-0 bottom-[13%] flex flex-col items-center gap-2 px-[4%]">
            {/* Toolbar: hidden until the player is hovered, exactly like the real one. */}
            <div className="mb-1 flex items-center gap-0.5 rounded-[0.7rem] bg-[rgba(16,16,22,0.82)] p-[3px] opacity-0 shadow-lg backdrop-blur-md transition-opacity duration-200 group-hover:opacity-100 focus-within:opacity-100">
              <ToolButton label="Previous line" onClick={() => go(-1)}>
                [
              </ToolButton>
              <ToolButton label="Replay line" onClick={() => setProgress(0)}>
                \
              </ToolButton>
              <ToolButton label="Next line" onClick={() => go(1)}>
                ]
              </ToolButton>
              <span className="mx-[3px] h-[15px] w-px bg-white/15" />
              <ToolButton
                label="Auto-pause at the end of each line"
                pressed={autoPause}
                onClick={() => setAutoPause((v) => !v)}
              >
                P
              </ToolButton>
              <ToolButton
                label="Blur the translation"
                pressed={blur}
                onClick={() => setBlur((v) => !v)}
              >
                H
              </ToolButton>
            </div>

            {/* Primary line */}
            <p
              ref={lineRef}
              className="relative max-w-full rounded-lg bg-[rgba(8,8,10,0.76)] px-[0.6em] py-[0.18em] text-center font-medium text-white backdrop-blur-[3px] [text-wrap:balance] text-[clamp(0.9rem,2.15vw,1.6rem)] leading-[1.34]"
            >
              {tokenize(cue.de).map((tok, i) => {
                if (!isWord(tok)) return <span key={i}>{tok}</span>;
                const k = key(tok);
                const gloss = cue.gloss[k] ?? "";
                const isSaved = saved.has(k);
                const isActive = card?.word === tok;
                return (
                  <button
                    key={i}
                    type="button"
                    onMouseEnter={(e) => openCard(e.currentTarget, tok, gloss)}
                    onFocus={(e) => openCard(e.currentTarget, tok, gloss)}
                    onClick={() => toggleSave(k)}
                    className={`cursor-pointer rounded px-[0.04em] transition-colors duration-100 ${
                      isSaved
                        ? "text-amber shadow-[inset_0_-2px_0_rgba(255,212,121,0.55)]"
                        : "text-white"
                    } ${
                      isActive
                        ? "bg-[rgba(126,200,227,0.4)]"
                        : "hover:bg-[rgba(126,200,227,0.28)] hover:text-[#cfefff]"
                    }`}
                  >
                    {tok}
                  </button>
                );
              })}

              {card ? (
                <LookupCard
                  card={card}
                  saved={saved.has(key(card.word))}
                  onSave={() => toggleSave(key(card.word))}
                  onClose={() => setCard(null)}
                />
              ) : null}
            </p>

            {/* Secondary line */}
            <p
              onClick={() => blur && setBlur(false)}
              className={`max-w-full rounded-lg bg-[rgba(8,8,10,0.6)] px-[0.6em] py-[0.18em] text-center text-[#b9bdcb] backdrop-blur-[3px] [text-wrap:balance] text-[clamp(0.66rem,1.46vw,1.09rem)] leading-[1.34] transition-[filter] duration-150 ${
                blur ? "cursor-pointer blur-[7px] hover:blur-none" : ""
              }`}
            >
              {cue.en}
            </p>
          </div>

          {/* Player chrome */}
          <div
            aria-hidden
            className="absolute inset-x-0 bottom-0 flex items-center gap-3 px-[4%] pb-[3.2%]"
          >
            <span className="flex h-4 w-4 shrink-0 items-center justify-center">
              <span className="h-2.5 w-[3px] bg-white/60" />
              <span className="ml-[3px] h-2.5 w-[3px] bg-white/60" />
            </span>
            <span className="relative h-[3px] flex-1 overflow-hidden rounded-full bg-white/15">
              <span
                className="absolute inset-y-0 left-0 rounded-full bg-white/70"
                style={{ width: `${((index + progress) / CUES.length) * 62 + 14}%` }}
              />
            </span>
            <span className="shrink-0 font-mono text-[0.6rem] tracking-wider text-white/55 tabular-nums">
              {Math.floor(elapsed / 60)}:{String(Math.floor(elapsed % 60)).padStart(2, "0")}
            </span>
          </div>
        </div>
      </div>

      <figcaption className="mt-4 flex flex-wrap items-center justify-between gap-x-6 gap-y-2">
        <p className="micro normal-case tracking-[0.06em] text-faint">
          Hover a word in the top line, click to keep it. The toolbar works too.
        </p>
        <p className="micro tracking-[0.1em]">
          <span className={saved.size ? "text-amber" : "text-faint"}>
            {String(saved.size).padStart(2, "0")}
          </span>{" "}
          saved
        </p>
      </figcaption>
    </figure>
  );
}

/* ── Pieces ───────────────────────────────────────────────────────────────── */

function ToolButton({
  children,
  label,
  onClick,
  pressed,
}: {
  children: React.ReactNode;
  label: string;
  onClick: () => void;
  pressed?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      title={label}
      aria-label={label}
      aria-pressed={pressed}
      className={`grid h-[26px] w-[28px] cursor-pointer place-items-center rounded-[7px] font-mono text-[13px] leading-none transition-colors duration-150 ${
        pressed
          ? "bg-[rgba(126,200,227,0.26)] text-[#9fe0f5]"
          : "text-[#cfd2dc] hover:bg-white/15 hover:text-white"
      }`}
    >
      {children}
    </button>
  );
}

function LookupCard({
  card,
  saved,
  onSave,
  onClose,
}: {
  card: NonNullable<CardState>;
  saved: boolean;
  onSave: () => void;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDivElement | null>(null);
  const [shift, setShift] = useState(0);

  // Keep the card inside the frame when the word sits near either edge.
  useLayoutEffect(() => {
    const el = ref.current;
    const frame = el?.offsetParent as HTMLElement | null;
    if (!el || !frame) return;
    const a = el.getBoundingClientRect();
    const b = frame.getBoundingClientRect();
    const pad = 10;
    if (a.left < b.left + pad) setShift(b.left + pad - a.left);
    else if (a.right > b.right - pad) setShift(b.right - pad - a.right);
    else setShift(0);
  }, [card.x, card.word]);

  return (
    <div
      ref={ref}
      onMouseLeave={onClose}
      style={{ left: card.x, transform: `translateX(calc(-50% + ${shift}px))` }}
      className="absolute bottom-[calc(100%+10px)] z-10 w-[min(20rem,72vw)] min-w-[11.5rem] rounded-xl border border-white/10 bg-[rgba(20,20,28,0.97)] p-[11px_13px] text-left shadow-[0_10px_34px_rgba(0,0,0,0.55)]"
    >
      <p className="mb-[3px] font-display text-[16px] font-semibold break-words text-amber">
        {card.word}
      </p>
      <p
        className={`mb-[9px] min-h-[1.2em] text-[13px] leading-[1.4] ${
          card.gloss ? "text-[#dfe3ee]" : "text-[#7f8598] italic"
        }`}
      >
        {card.gloss || "no entry"}
      </p>
      <div className="flex gap-[7px]">
        <button
          type="button"
          onClick={onSave}
          className={`cursor-pointer rounded-[7px] px-[11px] py-[5px] text-[12px] font-semibold transition-colors duration-150 ${
            saved ? "bg-[#6b5a20] text-amber" : "bg-[#2f6f8f] text-[#eaf7ff] hover:bg-[#3b87ac]"
          }`}
        >
          {saved ? "Saved" : "Save word"}
        </button>
        <button
          type="button"
          onClick={onClose}
          className="cursor-pointer rounded-[7px] px-[11px] py-[5px] text-[12px] font-semibold text-[#9aa0b0] transition-colors duration-150 hover:bg-white/10 hover:text-white"
        >
          Close
        </button>
      </div>
    </div>
  );
}
