"use client";

import { useState } from "react";

/**
 * A terminal block that can hand its contents to the clipboard. Falls back to
 * selecting nothing loudly — if the write fails the label just says so, rather
 * than pretending it worked.
 */
export function CodeBlock({ lines, label }: { lines: string[]; label?: string }) {
  const [state, setState] = useState<"idle" | "done" | "failed">("idle");

  async function copy() {
    try {
      await navigator.clipboard.writeText(lines.join("\n"));
      setState("done");
    } catch {
      setState("failed");
    }
    window.setTimeout(() => setState("idle"), 2000);
  }

  return (
    <div className="overflow-hidden rounded-xl border border-line bg-ground-2">
      <div className="flex items-center justify-between border-b border-line px-4 py-2.5">
        <p className="micro">{label ?? "terminal"}</p>
        <button
          type="button"
          onClick={copy}
          className="cursor-pointer font-mono text-[0.6875rem] tracking-[0.12em] text-faint uppercase transition-colors duration-300 hover:text-ink"
        >
          {state === "done" ? "copied" : state === "failed" ? "blocked" : "copy"}
        </button>
      </div>
      <pre className="overflow-x-auto px-4 py-4 font-mono text-[0.8125rem] leading-[1.85] text-[#cfd6e4]">
        <code>
          {lines.map((l) => (
            <span key={l} className="block whitespace-pre">
              <span className="mr-3 select-none text-faint">$</span>
              {l}
            </span>
          ))}
        </code>
      </pre>
    </div>
  );
}
