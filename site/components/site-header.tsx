"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { nav, site } from "@/lib/site";
import { Mark } from "./ui/mark";
import { Wrap } from "./ui/section";

export function SiteHeader() {
  const pathname = usePathname();
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  // Close the mobile panel on navigation, and lock the page behind it.
  useEffect(() => setOpen(false), [pathname]);

  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [open]);

  return (
    <header
      className={`sticky top-0 z-50 transition-colors duration-500 ${
        scrolled || open
          ? "border-b border-line bg-ground/85 backdrop-blur-xl"
          : "border-b border-transparent"
      }`}
    >
      <Wrap className="flex h-16 items-center justify-between gap-6 sm:h-[4.5rem]">
        <Mark />

        <nav className="hidden items-center gap-8 md:flex" aria-label="Primary">
          {nav.map((item) => {
            const active = pathname === item.href;
            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`micro transition-colors duration-300 hover:text-ink ${
                  active ? "text-ink" : ""
                }`}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="flex items-center gap-2">
          <a
            href={site.repo}
            target="_blank"
            rel="noreferrer noopener"
            className="hidden rounded-full border border-line-strong px-4 py-2 text-[0.8125rem] font-medium text-ink transition-colors duration-300 hover:bg-white/[0.06] sm:inline-flex"
          >
            GitHub
          </a>

          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            aria-expanded={open}
            aria-label={open ? "Close menu" : "Open menu"}
            className="flex h-9 w-9 items-center justify-center rounded-full border border-line-strong md:hidden"
          >
            <span className="relative block h-3 w-4">
              <span
                className={`absolute left-0 block h-px w-full bg-ink transition-all duration-300 ${
                  open ? "top-1.5 rotate-45" : "top-0.5"
                }`}
              />
              <span
                className={`absolute left-0 block h-px w-full bg-ink transition-all duration-300 ${
                  open ? "top-1.5 -rotate-45" : "top-[0.625rem]"
                }`}
              />
            </span>
          </button>
        </div>
      </Wrap>

      {/* Mobile panel */}
      <div
        className={`overflow-hidden border-t border-line bg-ground transition-[max-height] duration-500 md:hidden ${
          open ? "max-h-[26rem]" : "max-h-0 border-t-transparent"
        }`}
      >
        <Wrap className="flex flex-col py-2">
          {nav.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="border-b border-line py-4 font-display text-xl font-semibold tracking-[-0.03em] text-ink last:border-b-0"
            >
              {item.label}
            </Link>
          ))}
          <a
            href={site.repo}
            target="_blank"
            rel="noreferrer noopener"
            className="border-t border-line py-4 font-display text-xl font-semibold tracking-[-0.03em] text-muted"
          >
            GitHub
          </a>
        </Wrap>
      </div>
    </header>
  );
}
