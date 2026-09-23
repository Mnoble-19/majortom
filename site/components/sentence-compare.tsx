import { Reveal } from "./ui/reveal";

const FRAGMENTS = [
  { de: "Und als er dann endlich", en: "And when he finally" },
  { de: "vor der Tür stand, war", en: "in front of the door, was" },
  { de: "niemand mehr da.", en: "nobody there anymore." },
];

const WHOLE = "And when he finally stood at the door, there was no one left.";

/**
 * The clearest possible statement of why cues get regrouped before they are
 * translated: the same three cues, translated both ways, side by side.
 */
export function SentenceCompare() {
  return (
    <div className="mt-14 grid gap-4 lg:grid-cols-2 lg:gap-5">
      <Reveal as="article" className="h-full">
        <Panel label="Cue by cue" tone="bad">
          <ul className="space-y-5">
            {FRAGMENTS.map((f) => (
              <li key={f.de}>
                <p className="font-display text-[1.0625rem] font-medium tracking-[-0.02em] text-ink">
                  {f.de}
                </p>
                <p className="mt-1 text-[0.9375rem] text-[#b9bdcb]">{f.en}</p>
              </li>
            ))}
          </ul>
          <Note>Each fragment translated blind. The grammar has nowhere to land.</Note>
        </Panel>
      </Reveal>

      <Reveal as="article" delay={90} className="h-full">
        <Panel label="Regrouped into sentences" tone="good">
          <ul className="space-y-5">
            {FRAGMENTS.map((f, i) => (
              <li key={f.de}>
                <p className="font-display text-[1.0625rem] font-medium tracking-[-0.02em] text-ink">
                  {f.de}
                </p>
                {i === 0 ? (
                  <p className="mt-1 text-[0.9375rem] text-[#b9bdcb]">{WHOLE}</p>
                ) : (
                  <p className="mt-1 flex items-center gap-2 font-mono text-[0.6875rem] tracking-[0.12em] text-faint uppercase">
                    <span className="h-px w-5 bg-line-strong" />
                    held
                  </p>
                )}
              </li>
            ))}
          </ul>
          <Note>
            One sentence, translated once, held steady across all three cues while the
            original advances through it.
          </Note>
        </Panel>
      </Reveal>
    </div>
  );
}

function Panel({
  label,
  tone,
  children,
}: {
  label: string;
  tone: "good" | "bad";
  children: React.ReactNode;
}) {
  return (
    <div
      className={`flex h-full flex-col rounded-2xl border p-7 sm:p-9 ${
        tone === "good"
          ? "border-amber/25 bg-amber/[0.035]"
          : "border-line bg-white/[0.015]"
      }`}
    >
      <p className={`micro mb-7 ${tone === "good" ? "text-amber" : ""}`}>{label}</p>
      <div className="flex-1">{children}</div>
    </div>
  );
}

function Note({ children }: { children: React.ReactNode }) {
  return (
    <p className="mt-8 border-t border-line pt-5 text-[0.875rem] leading-relaxed text-faint">
      {children}
    </p>
  );
}
