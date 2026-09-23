"use client";

import { useEffect, useRef, useState } from "react";

type RevealProps = {
  children: React.ReactNode;
  /** Stagger, in milliseconds, applied once the element enters the viewport. */
  delay?: number;
  className?: string;
  as?: "div" | "li" | "section" | "article" | "header" | "figure";
};

/**
 * Fades and lifts its children the first time they scroll into view.
 *
 * Deliberately a one-shot: re-animating on the way back up is the kind of
 * effect that reads as decoration rather than intent. Reduced-motion users get
 * the content immediately, handled in CSS so there is no flash before hydration.
 */
export function Reveal({ children, delay = 0, className = "", as = "div" }: RevealProps) {
  const ref = useRef<HTMLElement | null>(null);
  const [shown, setShown] = useState(false);
  const Tag = as;

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    // Anything already on screen at mount should not animate in late.
    if (typeof IntersectionObserver === "undefined") {
      setShown(true);
      return;
    }

    const io = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        io.disconnect();
        window.setTimeout(() => setShown(true), delay);
      },
      { rootMargin: "0px 0px -12% 0px", threshold: 0.08 },
    );

    io.observe(el);
    return () => io.disconnect();
  }, [delay]);

  return (
    <Tag
      ref={ref as React.Ref<never>}
      className={`${shown ? "reveal-shown" : "reveal-hidden"} ${className}`}
    >
      {children}
    </Tag>
  );
}
