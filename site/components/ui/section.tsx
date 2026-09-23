import { Reveal } from "./reveal";

export function Wrap({
  children,
  className = "",
  wide = false,
}: {
  children: React.ReactNode;
  className?: string;
  wide?: boolean;
}) {
  return (
    <div
      className={`mx-auto w-full px-6 sm:px-8 lg:px-10 ${wide ? "max-w-[86rem]" : "max-w-[76rem]"} ${className}`}
    >
      {children}
    </div>
  );
}

export function Section({
  children,
  id,
  rule = false,
  className = "",
}: {
  children: React.ReactNode;
  id?: string;
  /** Draw the hairline that separates this section from the one above it. */
  rule?: boolean;
  className?: string;
}) {
  return (
    <section
      id={id}
      className={`py-[clamp(4.5rem,10vw,8.5rem)] ${rule ? "border-t border-line" : ""} ${className}`}
    >
      {children}
    </section>
  );
}

export function SectionHead({
  label,
  title,
  lede,
  className = "",
}: {
  label: string;
  title: React.ReactNode;
  lede?: React.ReactNode;
  className?: string;
}) {
  return (
    <Reveal as="header" className={`max-w-[46rem] ${className}`}>
      <p className="micro mb-6">{label}</p>
      <h2 className="display-lg text-ink">{title}</h2>
      {lede ? <p className="lede mt-7 max-w-[38rem]">{lede}</p> : null}
    </Reveal>
  );
}

/** The italic serif clause that closes a headline. */
export function Accent({ children }: { children: React.ReactNode }) {
  return <em className="accent text-muted">{children}</em>;
}

export function Code({ children }: { children: React.ReactNode }) {
  return <code className="code-inline">{children}</code>;
}
