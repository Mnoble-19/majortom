import { captureLayers } from "@/lib/site";
import { Reveal } from "./ui/reveal";

export function CaptureStack({ detailed = false }: { detailed?: boolean }) {
  return (
    <ol className="mt-14 border-t border-line">
      {captureLayers.map((layer, i) => {
        const off = layer.status === "off";
        return (
          <Reveal as="li" key={layer.rank} delay={i * 70}>
            <div
              className={`grid gap-x-8 gap-y-4 border-b border-line py-8 md:grid-cols-[4rem_minmax(0,1fr)_15rem] md:py-10 ${
                off ? "opacity-45" : ""
              }`}
            >
              <p
                className={`font-mono text-[0.8125rem] tracking-[0.1em] ${
                  layer.status === "best" ? "text-amber" : "text-faint"
                }`}
              >
                {layer.rank}
              </p>

              <div>
                <h3 className="display-md flex flex-wrap items-center gap-3 text-ink">
                  {layer.name}
                  {layer.status === "best" ? <Tag tone="amber">most trusted</Tag> : null}
                  {off ? <Tag>not implemented</Tag> : null}
                </h3>
                <p className="prose-p mt-3 max-w-[34rem]">{layer.how}</p>
                {detailed ? (
                  <p className="mt-3 max-w-[34rem] text-[0.9375rem] leading-relaxed text-faint">
                    {layer.detail}
                  </p>
                ) : null}
              </div>

              <ul className="flex flex-wrap content-start gap-1.5">
                {layer.covers.map((c) => (
                  <li
                    key={c}
                    className="rounded-full border border-line px-2.5 py-1 font-mono text-[0.6875rem] tracking-[0.06em] text-muted"
                  >
                    {c}
                  </li>
                ))}
              </ul>
            </div>
          </Reveal>
        );
      })}
    </ol>
  );
}

function Tag({ children, tone }: { children: React.ReactNode; tone?: "amber" }) {
  return (
    <span
      className={`rounded-full border px-2.5 py-1 font-mono text-[0.625rem] tracking-[0.12em] uppercase ${
        tone === "amber"
          ? "border-amber/30 bg-amber/10 text-amber"
          : "border-line text-faint"
      }`}
    >
      {children}
    </span>
  );
}
