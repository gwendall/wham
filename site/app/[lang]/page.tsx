import type { ReactNode } from "react";
import { notFound } from "next/navigation";
import { CopyCommand } from "@/components/CopyCommand";
import { Disclosure } from "@/components/Disclosure";
import { HeroStage } from "@/components/HeroStage";
import { MenuBarDemo } from "@/components/MenuBarDemo";
import { PixelSprite } from "@/components/PixelSprite";
import { A, Code, Footer, GITHUB, Header, SkipLink } from "@/components/Site";
import { LidArt, OpenArt, SwitchArt } from "@/components/StepArt";
import { PROMPT, Tile, UseCases } from "@/components/UseCases";
import { isLocale, LANGUAGES, messages, pathFor, type Locale, type Messages } from "@/lib/i18n";
import { rich } from "@/lib/rich";
import { MOON, SUN } from "@/lib/sprites";

const STEP_ART = [<OpenArt key="open" />, <SwitchArt key="switch" />, <LidArt key="lid" />];

type Verdict = "yes" | "helpers" | "no";

// Every claim here is checked against the app's own words (store listing,
// README, man page), its binary, or a published advisory, all linked.
const RIVALS: { key: Exclude<keyof Messages["compare"], "eyebrow" | "title" | "lead" | "source" | "lungo">; name: string; verdict: Verdict; source?: string }[] = [
  { key: "wham", name: "Wham", verdict: "yes" },
  { key: "amphetamine", name: "Amphetamine", verdict: "helpers", source: "https://apps.apple.com/us/app/amphetamine/id937984704" },
  { key: "caffeine", name: "Caffeine", verdict: "no", source: "https://intelliscapesolutions.com/apps/caffeine" },
  { key: "keepingyouawake", name: "KeepingYouAwake", verdict: "no", source: "https://github.com/newmarcel/KeepingYouAwake#readme" },
  { key: "caffeinate", name: "caffeinate", verdict: "no" },
];

export default async function Home({ params }: PageProps<"/[lang]">) {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  const m = await messages(lang);
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify({
            "@context": "https://schema.org",
            "@type": "SoftwareApplication",
            name: "Wham",
            description: m.meta.app,
            url: `https://wham.sh${pathFor(lang) === "/" ? "" : pathFor(lang)}`,
            inLanguage: LANGUAGES[lang].tag,
            operatingSystem: m.meta.os,
            applicationCategory: "UtilitiesApplication",
            offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
            author: { "@type": "Person", name: "Gwendall", url: "https://gwendall.com" },
            license: "https://opensource.org/licenses/MIT",
          }),
        }}
      />
      <SkipLink m={m} />
      <Header m={m} lang={lang} />
      <main id="main">
        <Hero m={m} />
        <TryIt m={m} />
        <Uses m={m} />
        <HowItWorks m={m} />
        <Tiny m={m} />
        <Compare m={m} />
        <Faq m={m} lang={lang} />
        <Developers m={m} />
      </main>
      <Footer m={m} lang={lang} />
    </>
  );
}

type Props = { m: Messages };

function Hero({ m }: Props) {
  return (
    <section className="page grid grid-cols-1 items-center gap-8 pb-(--section-y) pt-4 sm:pt-8 lg:grid-cols-[1.3fr_1fr] lg:gap-4 lg:pt-12">
      <div className="flex min-w-0 flex-col items-start">
        <p className="flex items-center gap-2 font-pixel text-pixel text-muted">
          <PixelSprite rows={SUN} cell={1} className="text-candy-pink" />
          {m.hero.eyebrow}
        </p>
        <p aria-hidden="true" className="wordmark mt-6 font-pixel text-wordmark">
          <span className="wordmark-shadow">Wham</span>
          <span className="wordmark-face">Wham</span>
        </p>
        <h1 className="mt-8 text-display font-black">
          <span className="block">{m.hero.title}</span> <span className="candy-mark">{m.hero.mark}</span>
        </h1>
        <p className="mt-6 max-w-[32rem] text-lead text-muted">{m.hero.lead}</p>
        <a href="/download" data-sound="download" className="press candy-glow mt-8 flex h-14 items-center gap-2 rounded-full bg-candy pl-3 pr-6 text-lead font-black text-ink">
          <span className="flex size-8 items-center justify-center">
            <PixelSprite rows={DOWN} cell={2} />
          </span>
          {m.hero.download}
        </a>
        <p className="mt-4 text-small text-muted">{m.hero.note}</p>
      </div>
      <HeroStage label={m.hero.stage} huds={m.hud} />
    </section>
  );
}

function TryIt({ m }: Props) {
  return (
    <Section id="try" eyebrow={m.try.eyebrow} title={m.try.title}>
      <Lead>{m.try.lead}</Lead>
      <div className="mt-12">
        <MenuBarDemo labels={m.demo} />
      </div>
    </Section>
  );
}

function Uses({ m }: Props) {
  return (
    <Section id="uses" eyebrow={m.uses.eyebrow} title={m.uses.title}>
      <Lead>{m.uses.lead}</Lead>
      <UseCases agents={m.uses.agents} jobs={m.uses.jobs} />
    </Section>
  );
}

function HowItWorks({ m }: Props) {
  return (
    <Section id="how" eyebrow={m.how.eyebrow} title={m.how.title}>
      <ol className="mt-12 grid grid-cols-1 gap-4 md:grid-cols-3">
        {m.how.steps.map((step, i) => (
          <li key={i} className="flex flex-col rounded-3xl bg-card p-6 ring-1 ring-line">
            <div className="flex h-24 items-end">{STEP_ART[i]}</div>
            <p className="mt-6 flex items-center gap-3">
              <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-candy font-pixel text-pixel text-ink pixel-even">
                {i + 1}
              </span>
              <span className="text-title font-black">{step.title}</span>
            </p>
            <p className="mt-3 text-body text-muted">{step.text}</p>
          </li>
        ))}
      </ol>
      <p className="mt-8 flex max-w-[44rem] gap-3 text-body text-muted">
        <PixelSprite rows={MOON} cell={2} className="mt-0.5 shrink-0 text-moon" />
        <span>{m.how.note}</span>
      </p>
    </Section>
  );
}

// The numbers are measured by scripts/eval.sh (docs/compatibility.md), and CI
// holds Wham to its budgets: a new measurement changes every messages file.
function Tiny({ m }: Props) {
  return (
    <Section id="tiny" eyebrow={m.tiny.eyebrow} title={m.tiny.title}>
      <Lead>{m.tiny.lead}</Lead>
      <ul className="mt-12 grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
        {m.tiny.stats.map((stat, i) => (
          <li key={i} className="flex flex-col rounded-3xl bg-card p-5 ring-1 ring-line sm:p-6">
            <p className="flex items-baseline gap-2">
              <span className="font-pixel text-pixel-lg">{stat.value}</span>
              {stat.unit && <span className="font-pixel text-pixel text-candy-pink">{stat.unit}</span>}
            </p>
            <p className="mt-4 text-body text-muted">{stat.text}</p>
          </li>
        ))}
      </ul>
      <p className="mt-8 max-w-[44rem] text-body text-muted">
        {rich(m.tiny.scale, { doc: (text) => <A href={`${GITHUB}/blob/main/docs/compatibility.md#resources`}>{text}</A> })}
      </p>
    </Section>
  );
}

const VERDICT_STYLE: Record<Verdict, string> = {
  yes: "bg-candy text-ink",
  helpers: "bg-candy-yellow/25 text-fg",
  no: "bg-fg/7 text-muted",
};

function Compare({ m }: Props) {
  return (
    <Section id="compare" eyebrow={m.compare.eyebrow} title={m.compare.title}>
      <Lead>{m.compare.lead}</Lead>
      <ul className="mt-12 grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
        {RIVALS.map((app) => {
          const words = m.compare[app.key];
          return (
            <li
              key={app.name}
              className={`flex flex-col rounded-3xl bg-card p-6 ${app.verdict === "yes" ? "ring-2 ring-candy-pink/60 md:col-span-2" : "ring-1 ring-line"}`}
            >
              <p className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
                <span className="text-title font-black">{app.name}</span>
                <span className={`flex h-7 items-center gap-1.5 rounded-full px-3 text-small font-extrabold ${VERDICT_STYLE[app.verdict]}`}>
                  <PixelSprite rows={app.verdict === "no" ? MOON : SUN} cell={1} />
                  {words.tag}
                </span>
              </p>
              <p className="mt-3 flex-1 text-body text-muted">{rich(words.text, { code: (text) => <Code>{text}</Code> })}</p>
              <p className="mt-4 text-small text-muted">
                {words.meta}
                {app.source && (
                  <>
                    {" · "}
                    <A href={app.source}>{m.compare.source}</A>
                  </>
                )}
              </p>
            </li>
          );
        })}
      </ul>
      <p className="mt-8 max-w-[44rem] text-body text-muted">
        {m.compare.lungo} <A href="https://apps.apple.com/app/lungo/id1263070803">{m.compare.source}</A>
      </p>
    </Section>
  );
}

function Faq({ m, lang }: Props & { lang: Locale }) {
  const tags = {
    code: (text: string) => <Code>{text}</Code>,
    github: (text: string) => <A href={GITHUB}>{text}</A>,
    dev: (text: string) => <A href="#developers">{text}</A>,
    changelog: (text: string) => <A href={pathFor(lang, "/changelog")}>{text}</A>,
  };
  return (
    <Section id="faq" eyebrow={m.faq.eyebrow} title={m.faq.title}>
      <div className="mt-12 grid grid-cols-1 gap-3">
        {m.faq.items.map(({ q, a }) => (
          <Disclosure
            key={q}
            summary={q}
            className="rounded-3xl bg-card ring-1 ring-line transition-shadow data-[open=true]:ring-candy-pink/50"
            buttonClassName="rounded-3xl p-6 text-title font-extrabold"
          >
            <div className="px-6 pb-6 text-body text-muted">{rich(a, tags)}</div>
          </Disclosure>
        ))}
      </div>
    </Section>
  );
}

// Everything a terminal can do, folded away at the bottom. The commands and
// what they print stay as the command line says them, in English.
function Developers({ m }: Props) {
  const tags = (script: string) => ({
    code: (text: string) => <Code>{text}</Code>,
    script: (text: string) => <A href={script}>{text}</A>,
  });
  return (
    <section aria-label={m.dev.title} className="page pb-(--section-y)">
      <Disclosure
        id="developers"
        heading="h2"
        className="scroll-mt-4 rounded-3xl bg-card ring-1 ring-line transition-shadow data-[open=true]:ring-candy-pink/50"
        buttonClassName="rounded-3xl p-6"
        summary={
          <span className="flex min-w-0 items-center gap-4">
            <Tile sprite={PROMPT} className="bg-ink text-white dark:bg-white/10" />
            <span className="min-w-0">
              <span className="block text-title font-black">{m.dev.title}</span>
              <span className="mt-1 block text-small text-muted">{m.dev.subtitle}</span>
            </span>
          </span>
        }
      >
        <div className="grid grid-cols-1 gap-12 px-6 pb-6 pt-6 lg:grid-cols-2">
          <div className="min-w-0">
            <Label>{m.dev.install}</Label>
            <p className="mt-3 text-body text-muted">{rich(m.dev.installText, tags("/install"))}</p>
            <div className="mt-6 grid gap-3">
              <CopyCommand command="curl -fsSL wham.sh | sh" labels={m.copy} />
              <CopyCommand command="brew install gwendall/tap/wham" labels={m.copy} />
              <CopyCommand command="npx wham.sh" labels={m.copy} />
            </div>
            <p className="mt-6 text-body text-muted">{rich(m.dev.curious, tags("/install"))}</p>
          </div>
          <div className="min-w-0">
            <Label>{m.dev.command}</Label>
            <pre className="mt-6 whitespace-pre-wrap break-words rounded-2xl bg-ink p-4 font-mono text-small text-white ring-1 ring-white/10 dark:bg-[#1c1222]">
              <Prompt />
              wham on{"\n"}
              <span className="text-candy-pink">on: your Mac stays awake, even with the lid closed</span>
              {"\n"}
              <Prompt />
              wham on 2h{"\n"}
              <span className="text-candy-pink">on until 4:30 PM: your Mac stays awake, even with the lid closed</span>
              {"\n"}
              <Prompt />
              wham status{"\n"}
              <span className="text-candy-pink">on until 4:30 PM: your Mac stays awake, even with the lid closed</span>
              {"\n"}
              <Prompt />
              wham off{"\n"}
              <span className="text-moon">off: your Mac sleeps as usual</span>
              {"\n"}
              <Prompt />
              wham run make{"\n"}
              <span className="text-white/45">{m.dev.runComment}</span>
            </pre>
            <Label className="mt-12">{m.dev.uninstall}</Label>
            <div className="mt-6">
              <CopyCommand command="curl -fsSL wham.sh/uninstall | sh" labels={m.copy} />
            </div>
            <p className="mt-6 text-body text-muted">{rich(m.dev.uninstallText, tags("/uninstall"))}</p>
            <pre className="mt-6 whitespace-pre-wrap break-words rounded-2xl bg-ink p-4 font-mono text-small text-white/90 ring-1 ring-white/10 dark:bg-[#1c1222]">
              <span className="text-white/45">{m.dev.sudoersComment}</span>
              {"\n"}
              <span className="text-candy-yellow">#501</span> ALL=(root) NOPASSWD: <span className="text-candy-pink">/usr/bin/pmset -a disablesleep 0</span>,{" "}
              <span className="text-candy-cyan">/usr/bin/pmset -a disablesleep 1</span>
            </pre>
          </div>
        </div>
      </Disclosure>
    </section>
  );
}

function Section({ id, eyebrow, title, children }: { id: string; eyebrow: string; title: string; children: ReactNode }) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="page py-(--section-y)">
      <p className="font-pixel text-pixel text-candy-pink">{eyebrow}</p>
      <h2 id={`${id}-title`} className="mt-4 text-heading font-black">
        {title}
      </h2>
      {children}
    </section>
  );
}

function Lead({ children }: { children: ReactNode }) {
  return <p className="mt-4 max-w-[38rem] text-lead text-muted">{children}</p>;
}

function Label({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <p className={`font-pixel text-pixel text-muted ${className}`}>{children}</p>;
}

function Prompt() {
  return (
    <span aria-hidden="true" className="select-none text-white/45">
      ${" "}
    </span>
  );
}

const DOWN = ["..##..", "..##..", "..##..", "######", ".####.", "..##..", "......", "######"];
