import Link from "next/link";

type Variant = "solid" | "ghost";

type ButtonLinkProps = {
  href: string;
  children: React.ReactNode;
  variant?: Variant;
  className?: string;
};

const base =
  "group inline-flex items-center gap-2 rounded-full px-5 py-2.5 text-[0.9375rem] font-medium " +
  "transition-colors duration-300 whitespace-nowrap";

const variants: Record<Variant, string> = {
  solid: "bg-ink text-ground hover:bg-white",
  ghost: "border border-line-strong text-ink hover:bg-white/[0.06] hover:border-white/30",
};

function isExternal(href: string) {
  return href.startsWith("http") || href.startsWith("mailto:");
}

export function ButtonLink({ href, children, variant = "solid", className = "" }: ButtonLinkProps) {
  const cls = `${base} ${variants[variant]} ${className}`;

  if (isExternal(href)) {
    return (
      <a href={href} className={cls} target="_blank" rel="noreferrer noopener">
        {children}
        <ArrowOut />
      </a>
    );
  }

  return (
    <Link href={href} className={cls}>
      {children}
      <ArrowIn />
    </Link>
  );
}

function ArrowIn() {
  return (
    <svg viewBox="0 0 16 16" className="h-3.5 w-3.5" fill="none" aria-hidden="true">
      <path
        d="M3.5 8h9M9 4.5 12.5 8 9 11.5"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="transition-transform duration-300 group-hover:translate-x-0.5"
      />
    </svg>
  );
}

function ArrowOut() {
  return (
    <svg viewBox="0 0 16 16" className="h-3.5 w-3.5" fill="none" aria-hidden="true">
      <path
        d="M5.5 10.5 10.5 5.5M6.75 5.5h3.75V9.25"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="transition-transform duration-300 group-hover:translate-x-0.5 group-hover:-translate-y-0.5"
      />
    </svg>
  );
}
