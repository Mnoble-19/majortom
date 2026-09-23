import Link from "next/link";
import { SubtitleStage } from "@/components/subtitle-stage";
import { CaptureStack } from "@/components/capture-stack";
import { SentenceCompare } from "@/components/sentence-compare";
import { ButtonLink } from "@/components/ui/button";
import { Reveal } from "@/components/ui/reveal";
import { Accent, Section, SectionHead, Wrap } from "@/components/ui/section";
import { principles, site } from "@/lib/site";

const worksOn = [
  "YouTube",
  "ARD Mediathek",
  "ZDF",
  "any player that ships text tracks",
  "anything that fetches a subtitle file",
];

export default function Home() {
  return (
    <>
      {/* ── Hero ──────────────────────────────────────────────────────────── */}
      <section className="pt-[clamp(4rem,11vw,8rem)] pb-[clamp(3rem,6vw,5rem)]">
        <Wrap>
          <Reveal>
            <p className="micro flex items-center gap-2.5">
              <span className="inline-block h-1.5 w-1.5 rounded-full bg-amber" />
              v{site.version}
              <span className="text-line-strong">/</span>
              Manifest V3
              <span className="text-line-strong">/</span>
              Chrome &amp; Brave
            </p>
          </Reveal>

          <Reveal delay={80}>
            <h1 className="display-xl mt-8 max-w-[18ch] text-ink">
              Watch in one language,
              <br />
              <Accent>read in two.</Accent>
            </h1>
          </Reveal>

          <Reveal delay={150}>
            <p className="lede mt-9 max-w-[40rem]">
              MajorTom stacks the original subtitle line above its translation — on any video
              site, not a hardcoded list of three. Every word in the original is clickable:
              click one to look it up and keep it, with the sentence it came from.
            </p>
          </Reveal>

          <Reveal delay={210}>
            <div className="mt-11 flex flex-wrap items-center gap-3">
              <ButtonLink href="/install">Install it</ButtonLink>
              <ButtonLink href="/how-it-works" variant="ghost">
                How it finds subtitles
              </ButtonLink>
            </div>
          </Reveal>
        </Wrap>

        <Wrap wide className="mt-[clamp(3.5rem,7vw,6rem)]">
          <Reveal delay={120}>
            <SubtitleStage />
          </Reveal>
        </Wrap>
      </section>

      {/* ── Coverage strip ────────────────────────────────────────────────── */}
      <section className="border-y border-line py-8">
        <Wrap>
          <Reveal className="flex flex-col gap-5 lg:flex-row lg:items-center lg:gap-10">
            <p className="micro shrink-0">Working today on</p>
            <ul className="flex flex-wrap items-center gap-x-7 gap-y-2.5">
              {worksOn.map((s, i) => (
                <li
                  key={s}
                  className={`text-[0.9375rem] ${i < 3 ? "font-display font-medium tracking-[-0.02em] text-ink" : "text-faint"}`}
                >
                  {s}
                </li>
              ))}
            </ul>
          </Reveal>
        </Wrap>
      </section>

      {/* ── The idea ──────────────────────────────────────────────────────── */}
      <Section id="idea">
        <Wrap>
          <SectionHead
            label="The idea"
            title={
              <>
                Three rules,
                <br />
                <Accent>and no more.</Accent>
              </>
            }
          />

          <ol className="mt-16 grid gap-x-8 gap-y-12 md:grid-cols-3">
            {principles.map((p, i) => (
              <Reveal as="li" key={p.n} delay={i * 90}>
                <p className="font-mono text-[0.8125rem] tracking-[0.1em] text-amber">{p.n}</p>
                <h3 className="display-md mt-5 text-ink">{p.title}</h3>
                <p className="prose-p mt-4 text-[0.9375rem]">{p.body}</p>
              </Reveal>
            ))}
          </ol>
        </Wrap>
      </Section>

      {/* ── Capture ───────────────────────────────────────────────────────── */}
      <Section id="capture" rule>
        <Wrap>
          <SectionHead
            label="Capture"
            title={
              <>
                Four ways in,
                <br />
                <Accent>best one wins.</Accent>
              </>
            }
            lede="Sites differ wildly in how they deliver captions, so capture is layered. The first layer that produces cues takes the screen — and if a more trustworthy source turns up later, it quietly replaces the one already running."
          />

          <CaptureStack />

          <Reveal className="mt-12">
            <Link
              href="/how-it-works"
              className="group inline-flex items-center gap-2 text-[0.9375rem] font-medium text-ink"
            >
              <span className="border-b border-line-strong pb-0.5 transition-colors duration-300 group-hover:border-amber">
                Read why the adapter layer has to exist
              </span>
              <span className="transition-transform duration-300 group-hover:translate-x-1">→</span>
            </Link>
          </Reveal>
        </Wrap>
      </Section>

      {/* ── Translation quality ───────────────────────────────────────────── */}
      <Section id="quality" rule>
        <Wrap>
          <SectionHead
            label="Translation"
            title={
              <>
                Subtitles break sentences.
                <br />
                <Accent>We put them back.</Accent>
              </>
            }
            lede="Broadcasters split one sentence across three or four cues. Translating those fragments in isolation is the single biggest reason machine-translated subtitles read badly."
          />
          <SentenceCompare />
        </Wrap>
      </Section>

      {/* ── Coda ──────────────────────────────────────────────────────────── */}
      <Section rule>
        <Wrap>
          <Reveal className="flex flex-col items-start justify-between gap-10 lg:flex-row lg:items-end">
            <h2 className="display-lg max-w-[14ch] text-ink">
              Take it
              <br />
              <Accent>for a spin.</Accent>
            </h2>
            <div className="flex flex-wrap gap-3">
              <ButtonLink href="/install">Install it</ButtonLink>
              <ButtonLink href={site.repo} variant="ghost">
                Read the source
              </ButtonLink>
            </div>
          </Reveal>
        </Wrap>
      </Section>
    </>
  );
}
