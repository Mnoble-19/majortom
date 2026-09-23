import Link from "next/link";
import { nav, site } from "@/lib/site";
import { Mark } from "./ui/mark";
import { Wrap } from "./ui/section";

const project = [
  { href: site.repo, label: "Source" },
  { href: site.issues, label: "Issues" },
  { href: site.releases, label: "Releases" },
  { href: site.deepl, label: "DeepL API" },
];

export function SiteFooter() {
  return (
    <footer className="border-t border-line">
      <Wrap className="grid gap-12 py-16 sm:grid-cols-2 lg:grid-cols-4 lg:gap-8">
        <div className="lg:col-span-2">
          <Mark />
          <p className="prose-p mt-5 max-w-[24rem] text-[0.9375rem]">
            Dual subtitles and click-to-save vocabulary, for the language you are already
            watching in.
          </p>
        </div>

        <nav aria-label="Pages">
          <p className="micro mb-5">Pages</p>
          <ul className="space-y-3">
            {nav.map((item) => (
              <li key={item.href}>
                <Link
                  href={item.href}
                  className="text-[0.9375rem] text-muted transition-colors duration-300 hover:text-ink"
                >
                  {item.label}
                </Link>
              </li>
            ))}
            <li>
              <Link
                href="/privacy"
                className="text-[0.9375rem] text-muted transition-colors duration-300 hover:text-ink"
              >
                Privacy
              </Link>
            </li>
          </ul>
        </nav>

        <nav aria-label="Project">
          <p className="micro mb-5">Project</p>
          <ul className="space-y-3">
            {project.map((item) => (
              <li key={item.href}>
                <a
                  href={item.href}
                  target="_blank"
                  rel="noreferrer noopener"
                  className="text-[0.9375rem] text-muted transition-colors duration-300 hover:text-ink"
                >
                  {item.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>
      </Wrap>

      <Wrap className="flex flex-col gap-3 border-t border-line py-8 sm:flex-row sm:items-center sm:justify-between">
        <p className="micro">Ground control to Major Tom</p>
        <p className="micro">
          v{site.version} — MIT — a side project that got out of hand
        </p>
      </Wrap>
    </footer>
  );
}
