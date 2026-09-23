import Link from "next/link";

/**
 * The mark is the product reduced to its smallest true statement: two stacked
 * lines inside a frame — a wide one on top in ink, a shorter, quieter one below
 * in amber. Original above, translation beneath.
 */
export function MarkGlyph({ className = "" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
      className={className}
      strokeLinecap="round"
    >
      <rect
        x="1.9"
        y="4"
        width="20.2"
        height="16"
        rx="4.4"
        stroke="currentColor"
        strokeOpacity="0.32"
        strokeWidth="1.3"
      />
      <line x1="6.1" y1="12.4" x2="17.9" y2="12.4" stroke="currentColor" strokeWidth="1.9" />
      <line
        x1="8.9"
        y1="16.1"
        x2="15.1"
        y2="16.1"
        stroke="var(--color-amber)"
        strokeWidth="1.9"
      />
    </svg>
  );
}

export function Mark({ className = "" }: { className?: string }) {
  return (
    <Link
      href="/"
      className={`group inline-flex items-center gap-2.5 text-ink ${className}`}
      aria-label="MajorTom — home"
    >
      <MarkGlyph className="h-6 w-6 shrink-0 transition-transform duration-500 group-hover:-translate-y-px" />
      <span className="font-display text-[1.0625rem] font-semibold tracking-[-0.035em]">
        MajorTom
      </span>
    </Link>
  );
}
