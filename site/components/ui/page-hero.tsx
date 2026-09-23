import { Reveal } from "./reveal";
import { Wrap } from "./section";

/** The masthead every interior page opens with. */
export function PageHero({
  label,
  title,
  lede,
  children,
}: {
  label: string;
  title: React.ReactNode;
  lede?: React.ReactNode;
  children?: React.ReactNode;
}) {
  return (
    <section className="border-b border-line pt-[clamp(3.5rem,8vw,6rem)] pb-[clamp(3rem,6vw,5rem)]">
      <Wrap>
        <Reveal>
          <p className="micro">{label}</p>
        </Reveal>
        <Reveal delay={70}>
          <h1 className="display-xl mt-7 max-w-[16ch] text-ink">{title}</h1>
        </Reveal>
        {lede ? (
          <Reveal delay={130}>
            <p className="lede mt-8 max-w-[40rem]">{lede}</p>
          </Reveal>
        ) : null}
        {children ? <Reveal delay={190}>{children}</Reveal> : null}
      </Wrap>
    </section>
  );
}
