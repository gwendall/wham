import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { PixelSprite } from "@/components/PixelSprite";
import { Code, Footer, Header, SkipLink } from "@/components/Site";
import { isLocale, LANGUAGES, LOCALES, messages, pathFor } from "@/lib/i18n";
import { ogSize } from "@/lib/og";
import { rich } from "@/lib/rich";
import { SUN } from "@/lib/sprites";

// What changed in each version, for the people who use Wham: written by hand in
// messages/<code>.json, newest first. The repo's CHANGELOG.md and the GitHub
// release notes are made from the English one (scripts/changelog.mjs).
const PAGE = "/changelog";

export async function generateMetadata({ params }: PageProps<"/[lang]/changelog">): Promise<Metadata> {
  const { lang } = await params;
  if (!isLocale(lang)) return {};
  const { changelog, meta } = await messages(lang);
  const languages = Object.fromEntries(LOCALES.map((code) => [LANGUAGES[code].tag, pathFor(code, PAGE)]));
  // The home page's share card: an image file only reaches its own folder.
  const card = (kind: string) => [{ url: `/${lang}/${kind}/card`, ...ogSize, alt: meta.image, type: "image/png" }];
  return {
    title: changelog.title,
    description: changelog.description,
    alternates: { canonical: pathFor(lang, PAGE), languages: { ...languages, "x-default": PAGE } },
    openGraph: {
      type: "website",
      url: pathFor(lang, PAGE),
      siteName: "Wham",
      locale: LANGUAGES[lang].og,
      alternateLocale: LOCALES.filter((code) => code !== lang).map((code) => LANGUAGES[code].og),
      title: changelog.title,
      description: changelog.description,
      images: card("opengraph-image"),
    },
    twitter: {
      card: "summary_large_image",
      title: changelog.title,
      description: changelog.description,
      images: card("twitter-image"),
    },
  };
}

export default async function Changelog({ params }: PageProps<"/[lang]/changelog">) {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  const m = await messages(lang);
  const words = m.changelog;
  const day = new Intl.DateTimeFormat(LANGUAGES[lang].tag, { dateStyle: "long", timeZone: "UTC" });
  return (
    <>
      <SkipLink m={m} />
      <Header m={m} lang={lang} page={PAGE} />
      <main id="main" className="page pb-(--section-y) pt-8 sm:pt-12">
        <p className="font-pixel text-pixel text-candy-pink">{words.eyebrow}</p>
        <h1 className="mt-4 text-heading font-black">{words.heading}</h1>
        <p className="mt-4 max-w-[38rem] text-lead text-muted">{words.lead}</p>
        <ol className="mt-12 grid max-w-[48rem] grid-cols-1 gap-4">
          {words.releases.map((release, i) => (
            <li
              key={release.version}
              id={`v${release.version}`}
              className={`scroll-mt-4 rounded-3xl bg-card p-6 ${i === 0 ? "ring-2 ring-candy-pink/60" : "ring-1 ring-line"}`}
            >
              <h2 className="flex flex-wrap items-center gap-x-3 gap-y-2">
                <span className="font-pixel text-pixel-lg">
                  <span className="sr-only">Wham </span>
                  {release.version}
                </span>
                {i === 0 && (
                  <span className="flex h-7 items-center gap-1.5 rounded-full bg-candy px-3 text-small font-extrabold text-ink">
                    <PixelSprite rows={SUN} cell={1} />
                    {words.latest}
                  </span>
                )}
              </h2>
              <p className="mt-2 text-small text-muted">
                <time dateTime={release.date}>{day.format(new Date(`${release.date}T00:00:00Z`))}</time>
              </p>
              <ul className="mt-5 grid gap-3 text-body text-muted">
                {release.items.map((item) => (
                  <li key={item} className="flex gap-3">
                    <span aria-hidden="true" className="mt-[0.6em] size-1.5 shrink-0 bg-candy-pink" />
                    <span>{rich(item, { code: (text) => <Code>{text}</Code> })}</span>
                  </li>
                ))}
              </ul>
            </li>
          ))}
        </ol>
      </main>
      <Footer m={m} lang={lang} />
    </>
  );
}
