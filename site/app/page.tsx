import type { ReactNode } from "react";
import { CopyCommand } from "@/components/CopyCommand";
import { Disclosure } from "@/components/Disclosure";
import { HeroStage } from "@/components/HeroStage";
import { MenuBarDemo } from "@/components/MenuBarDemo";
import { MusicToggle } from "@/components/MusicToggle";
import { PixelSprite } from "@/components/PixelSprite";
import { LidArt, OpenArt, SwitchArt } from "@/components/StepArt";
import { PROMPT, Tile, UseCases } from "@/components/UseCases";
import { HEART, MOON, SUN, SUN_LIT } from "@/lib/sprites";

const GITHUB = "https://github.com/gwendall/wham";

const STEPS = [
  {
    art: <OpenArt />,
    title: "Download and open Wham",
    text: "Drag it to Applications and open it. It lives in your menu bar, next to the clock.",
  },
  {
    art: <SwitchArt />,
    title: "Click the switch",
    text: "The sun comes out and the chime plays. The very first time, macOS asks for your password, once.",
  },
  {
    art: <LidArt />,
    title: "Close the lid",
    text: "Your Mac keeps going. Claude Code finishes its task, the export reaches the last frame, the download hits 100%.",
  },
];

// Measured by scripts/eval.sh (docs/compatibility.md); CI holds Wham to its budgets.
const STATS = [
  { value: "1.4", unit: "MB", text: "The whole app, on disk. The download is 2.7 MB." },
  { value: "10", unit: "MB", text: "Of memory while it runs." },
  { value: "0.03", unit: "%", text: "Of one CPU core, idle: a hundredth of a second of work every 30 seconds." },
  { value: "0", unit: "", text: "Dependencies. No analytics, no trackers, nothing else running." },
];

type Verdict = "yes" | "setup" | "helpers" | "no";

// Every claim here is checked against the app's own words (store listing,
// README, man page), its binary, or a published advisory, all linked.
const RIVALS: { name: string; verdict: Verdict; tag: string; text: ReactNode; meta: string; source?: string }[] = [
  {
    name: "Wham",
    verdict: "yes",
    tag: "Yes, on its own",
    text: (
      <>
        Turns off the kernel&apos;s sleep flag, the one switch macOS honors with the lid shut, and back on when you are done.
        Download, drag, click. macOS 11 or later, Intel too, signed and notarized.
      </>
    ),
    meta: "1.4 MB on disk · Free, open source",
  },
  {
    name: "Insomnia",
    verdict: "setup",
    tag: "Yes, with setup",
    text: (
      <>
        Flips the same flag, inside timed sessions with extras: it freezes apps, mutes audio, joins your hotspot. You install it
        through your coding agent or the Terminal, on macOS 26 and Apple silicon only, and its builds are not notarized.
      </>
    ),
    meta: "2.3 MB on disk · Free, open source · Experimental",
    source: "https://github.com/krishhgg/Insomnia#readme",
  },
  {
    name: "Amphetamine",
    verdict: "helpers",
    tag: "With helper apps",
    text: (
      <>
        Sandboxed by the App Store. For a closed lid it offers Amphetamine Enhancer, a separate app from outside the store, and
        on Apple silicon laptops Power Protect, another separate download.
      </>
    ),
    meta: "6.7 MB download, plus helpers · Free",
    source: "https://apps.apple.com/us/app/amphetamine/id937984704",
  },
  {
    name: "Caffeine",
    verdict: "no",
    tag: "Lid open only",
    text: (
      <>
        Holds a power assertion (we looked inside its binary): the polite request to stay up that macOS drops the moment the lid
        closes.
      </>
    ),
    meta: "0.8 MB on disk · Free",
    source: "https://intelliscapesolutions.com/apps/caffeine",
  },
  {
    name: "KeepingYouAwake",
    verdict: "no",
    tag: "Lid open only",
    text: (
      <>
        A friendly switch for <Code>caffeinate</Code>. In its own words, it &ldquo;will only prevent sleep on desktop Macs and
        portable Macs with an open lid.&rdquo;
      </>
    ),
    meta: "7.6 MB on disk · Free, open source",
    source: "https://github.com/newmarcel/KeepingYouAwake#readme",
  },
  {
    name: "caffeinate",
    verdict: "no",
    tag: "Lid open only",
    text: (
      <>
        Built into macOS, with the same power assertions. Even its strongest flag, <Code>-s</Code>, is &ldquo;valid only when
        system is running on AC power.&rdquo;
      </>
    ),
    meta: "Built in · man caffeinate",
  },
];

const FAQ: { q: string; a: ReactNode }[] = [
  {
    q: "Do I need the Terminal?",
    a: (
      <>
        No. Download Wham, open it, and everything happens in the menu bar: one click to keep your Mac awake, one click to let it
        sleep. The commands at the bottom of this page are only there for people who like typing them.
      </>
    ),
  },
  {
    q: "Is it safe?",
    a: (
      <>
        Yes. Turning sleep off takes an administrator: the first time you click, macOS asks for your password once, so Wham
        can flip the sleep setting without asking again. That is the only thing it is allowed to do. The app is signed by its
        developer and notarized by Apple, and every line of it is on <A href={GITHUB}>GitHub</A>.
      </>
    ),
  },
  {
    q: "Will my Mac overheat in a bag?",
    a: (
      <>
        It can. With Wham on, your Mac stays fully awake with the lid shut, and a busy laptop in a closed bag has nowhere to put
        its heat. Wham is meant for desks, docks and shelves, where air can move. Before you pack up, flip it off and your Mac
        sleeps when you close it, like it always did.
      </>
    ),
  },
  {
    q: "What about the battery?",
    a: (
      <>
        Wham itself costs next to nothing: it checks one setting every two seconds. But an awake Mac drains its battery like an
        awake Mac, lid closed or not. For long jobs, plug it in.
      </>
    ),
  },
  {
    q: "Do I need an external display, a keyboard or power?",
    a: (
      <>
        No. That is what macOS asks for its own &ldquo;clamshell mode&rdquo;, and Wham does not need any of it. Close the lid on
        a bare laptop and it stays awake.
      </>
    ),
  },
  {
    q: "What happens when I quit Wham?",
    a: (
      <>
        Sleep comes back. Quitting turns the setting off on the way out, whether you quit from its menu (right-click the
        switch), from a script, or by logging out.
      </>
    ),
  },
  {
    q: "How do I uninstall it?",
    a: (
      <>
        Quit Wham from its menu, which gives sleep back, then drag Wham from Applications to the Trash. For a full cleanup,
        including the password rule, use the one-line uninstaller under <A href="#developers">For developers</A>.
      </>
    ),
  },
  {
    q: "Why not the Mac App Store?",
    a: (
      <>
        App Store apps live in a sandbox, and a sandboxed app cannot change the Mac&apos;s sleep setting. The ones that try settle
        for asking macOS to stay up, which is exactly what stops working when you close the lid.
      </>
    ),
  },
];

export default function Home() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify({
            "@context": "https://schema.org",
            "@type": "SoftwareApplication",
            name: "Wham",
            description: "A one-click menu bar switch that keeps your Mac awake, for real, even with the lid shut.",
            url: "https://wham.sh",
            operatingSystem: "macOS 11 or later",
            applicationCategory: "UtilitiesApplication",
            offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
            author: { "@type": "Person", name: "Gwendall", url: "https://gwendall.com" },
            license: "https://opensource.org/licenses/MIT",
          }),
        }}
      />
      <a
        href="#main"
        className="sr-only z-50 rounded-full bg-ink px-4 py-2 text-body font-bold text-white focus:not-sr-only focus:fixed focus:left-4 focus:top-4"
      >
        Skip to content
      </a>
      <Header />
      <main id="main">
        <Hero />
        <TryIt />
        <Uses />
        <HowItWorks />
        <Tiny />
        <Compare />
        <Faq />
        <Developers />
      </main>
      <Footer />
    </>
  );
}

function Header() {
  return (
    <header className="page flex h-20 items-center justify-between gap-4">
      <a href="#main" className="flex items-center gap-3 rounded-lg" aria-label="Wham, back to the top">
        <PixelSprite rows={SUN_LIT} cell={2} />
        <span className="flex items-baseline">
          <span className="font-pixel text-pixel-lg">Wham</span>
          <span className="text-title font-extrabold text-muted">.sh</span>
        </span>
      </a>
      <nav aria-label="Main" className="flex items-center gap-1 text-body font-bold">
        <NavLink href="#how" className="hidden md:flex">
          How it works
        </NavLink>
        <NavLink href="#compare" className="hidden md:flex">
          Compare
        </NavLink>
        <NavLink href="#faq" className="hidden md:flex">
          FAQ
        </NavLink>
        <a href="/download" className="press flex h-10 items-center rounded-full bg-candy px-4 text-ink">
          Download
        </a>
        <MusicToggle />
        <a
          href={GITHUB}
          className="flex size-10 items-center justify-center rounded-full transition-colors hover:bg-fg/6"
          aria-label="Wham on GitHub"
        >
          <GitHubIcon />
        </a>
      </nav>
    </header>
  );
}

function Hero() {
  return (
    <section className="page grid grid-cols-1 items-center gap-8 pb-(--section-y) pt-4 sm:pt-8 lg:grid-cols-[1.3fr_1fr] lg:gap-4 lg:pt-12">
      <div className="flex min-w-0 flex-col items-start">
        <p className="flex items-center gap-2 font-pixel text-pixel text-muted">
          <PixelSprite rows={SUN} cell={1} className="text-candy-pink" />
          Menu bar app for macOS
        </p>
        <p aria-hidden="true" className="wordmark mt-6 font-pixel text-wordmark">
          <span className="wordmark-shadow">Wham</span>
          <span className="wordmark-face">Wham</span>
        </p>
        <h1 className="mt-8 text-display font-black">
          <span className="block">Close the lid.</span> <span className="candy-mark">Your Mac stays awake.</span>
        </h1>
        <p className="mt-6 max-w-[32rem] text-lead text-muted">
          A one-click menu bar switch that keeps your Mac awake, for real, even with the lid shut.
        </p>
        <a href="/download" className="press candy-glow mt-8 flex h-14 items-center gap-2 rounded-full bg-candy pl-3 pr-6 text-lead font-black text-ink">
          <span className="flex size-8 items-center justify-center">
            <PixelSprite rows={DOWN} cell={2} />
          </span>
          Download for Mac
        </a>
        <p className="mt-4 text-small text-muted">Free. macOS 11 or later. Apple silicon and Intel.</p>
      </div>
      <HeroStage />
    </section>
  );
}

function TryIt() {
  return (
    <Section id="try" eyebrow="Try it" title="One switch in your menu bar.">
      <Lead>
        That is the whole app. A sun when your Mac stays awake, a moon when it can sleep, a little chime either way. Go on,
        click it.
      </Lead>
      <div className="mt-12">
        <MenuBarDemo />
      </div>
    </Section>
  );
}

function Uses() {
  return (
    <Section id="uses" eyebrow="What it is for" title="Made for long jobs.">
      <Lead>
        Start it, close the lid, walk away. Anything that takes longer than you want to sit and watch keeps going until it is
        done.
      </Lead>
      <UseCases />
    </Section>
  );
}

function HowItWorks() {
  return (
    <Section id="how" eyebrow="How it works" title="Three steps. The third one is the point.">
      <ol className="mt-12 grid grid-cols-1 gap-4 md:grid-cols-3">
        {STEPS.map((step, i) => (
          <li key={step.title} className="flex flex-col rounded-3xl bg-card p-6 ring-1 ring-line">
            <div className="flex h-24 items-end">{step.art}</div>
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
        <span>
          Most keep-awake apps only ask macOS to stay up, which it ignores once the lid closes, so Wham turns sleep off itself
          and back on when you are done.
        </span>
      </p>
    </Section>
  );
}

function Tiny() {
  return (
    <Section id="tiny" eyebrow="Tiny" title="You will forget it is running.">
      <Lead>
        Wham does one thing: every two seconds, it reads one kernel flag. The rest of the time it does nothing at all, and CI
        holds it to a budget.
      </Lead>
      <ul className="mt-12 grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
        {STATS.map((stat) => (
          <li key={stat.text} className="flex flex-col rounded-3xl bg-card p-5 ring-1 ring-line sm:p-6">
            <p className="flex items-baseline gap-2">
              <span className="font-pixel text-pixel-lg">{stat.value}</span>
              {stat.unit && <span className="font-pixel text-pixel text-candy-pink">{stat.unit}</span>}
            </p>
            <p className="mt-4 text-body text-muted">{stat.text}</p>
          </li>
        ))}
      </ul>
      <p className="mt-8 max-w-[44rem] text-body text-muted">
        For scale: Insomnia takes 2.3 MB on disk for Apple silicon alone (Wham&apos;s 1.4 MB carries Intel too), KeepingYouAwake
        7.6 MB, and Amphetamine is a 6.7 MB download before its helper apps. Measured on a MacBook Air, macOS 26.6; the details
        are in{" "}
        <A href={`${GITHUB}/blob/main/docs/compatibility.md#resources`}>docs/compatibility.md</A>.
      </p>
    </Section>
  );
}

const VERDICT_STYLE: Record<Verdict, string> = {
  yes: "bg-candy text-ink",
  setup: "bg-candy-cyan/25 text-fg",
  helpers: "bg-candy-yellow/25 text-fg",
  no: "bg-fg/7 text-muted",
};

function Compare() {
  return (
    <Section id="compare" eyebrow="Compare" title="Most keep-awake apps stop at the lid.">
      <Lead>
        Keeping a Mac awake with the lid open is easy. Shut it, and macOS ignores the polite way to ask. Here is how the
        well-known apps handle a closed lid, on battery, with no screen plugged in.
      </Lead>
      <ul className="mt-12 grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
        {RIVALS.map((app) => (
          <li
            key={app.name}
            className={`flex flex-col rounded-3xl bg-card p-6 ${app.verdict === "yes" ? "ring-2 ring-candy-pink/60" : "ring-1 ring-line"}`}
          >
            <p className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
              <span className="text-title font-black">{app.name}</span>
              <span className={`flex h-7 items-center gap-1.5 rounded-full px-3 text-small font-extrabold ${VERDICT_STYLE[app.verdict]}`}>
                <PixelSprite rows={app.verdict === "no" ? MOON : SUN} cell={1} />
                {app.tag}
              </span>
            </p>
            <p className="mt-3 flex-1 text-body text-muted">{app.text}</p>
            <p className="mt-4 text-small text-muted">
              {app.meta}
              {app.source && (
                <>
                  {" · "}
                  <A href={app.source}>Source</A>
                </>
              )}
            </p>
          </li>
        ))}
      </ul>
      <p className="mt-8 max-w-[44rem] text-body text-muted">
        On their own, App Store apps cannot, and the honest ones say so: Lungo &ldquo;will not prevent your computer from
        sleeping if you close the lid. This is a Mac App Store limitation.&rdquo;{" "}
        <A href="https://apps.apple.com/app/lungo/id1263070803">Source</A>
      </p>
    </Section>
  );
}

function Faq() {
  return (
    <Section id="faq" eyebrow="FAQ" title="Good questions.">
      <div className="mt-12 grid grid-cols-1 gap-3">
        {FAQ.map(({ q, a }) => (
          <Disclosure
            key={q}
            summary={q}
            className="rounded-3xl bg-card ring-1 ring-line transition-shadow data-[open=true]:ring-candy-pink/50"
            buttonClassName="rounded-3xl p-6 text-title font-extrabold"
          >
            <div className="px-6 pb-6 text-body text-muted">{a}</div>
          </Disclosure>
        ))}
      </div>
    </Section>
  );
}

// Everything a terminal can do, folded away at the bottom.
function Developers() {
  return (
    <section aria-label="For developers" className="page pb-(--section-y)">
      <Disclosure
        id="developers"
        heading="h2"
        className="scroll-mt-4 rounded-3xl bg-card ring-1 ring-line transition-shadow data-[open=true]:ring-candy-pink/50"
        buttonClassName="rounded-3xl p-6"
        summary={
          <span className="flex min-w-0 items-center gap-4">
            <Tile sprite={PROMPT} className="bg-ink text-white dark:bg-white/10" />
            <span className="min-w-0">
              <span className="block text-title font-black">For developers</span>
              <span className="mt-1 block text-small text-muted">Terminal, Homebrew, npm and the wham command.</span>
            </span>
          </span>
        }
      >
        <div className="grid grid-cols-1 gap-12 px-6 pb-6 pt-6 lg:grid-cols-2">
          <div className="min-w-0">
            <Label>Install</Label>
            <p className="mt-3 text-body text-muted">
              The same signed app as the download, plus the <Code>wham</Code> command. Run it again to update.
            </p>
            <div className="mt-6 grid gap-3">
              <CopyCommand command="curl -fsSL wham.sh | sh" />
              <CopyCommand command="brew install gwendall/tap/wham" />
              <CopyCommand command="npx wham.sh" />
            </div>
            <p className="mt-6 text-body text-muted">
              Curious first? <A href="/install">Read install.sh</A>: it downloads the latest release, checks its signature, puts
              it in Applications and opens it.
            </p>
          </div>
          <div className="min-w-0">
            <Label>The wham command</Label>
            <pre className="mt-6 whitespace-pre-wrap break-words rounded-2xl bg-ink p-4 font-mono text-small text-white ring-1 ring-white/10 dark:bg-[#1c1222]">
              <Prompt />
              wham on{"\n"}
              <span className="text-candy-pink">on: your Mac stays awake, even with the lid closed</span>
              {"\n"}
              <Prompt />
              wham status{"\n"}
              <span className="text-candy-pink">on: your Mac stays awake, even with the lid closed</span>
              {"\n"}
              <Prompt />
              wham off{"\n"}
              <span className="text-moon">off: your Mac sleeps as usual</span>
            </pre>
            <Label className="mt-12">Uninstall</Label>
            <div className="mt-6">
              <CopyCommand command="curl -fsSL wham.sh/uninstall | sh" />
            </div>
            <p className="mt-6 text-body text-muted">
              It quits Wham, which gives sleep back, then removes the app, the <Code>wham</Code> command, its settings and the
              sudoers rule below. With Homebrew: <Code>brew uninstall --zap wham</Code>.{" "}
              <A href="/uninstall">Read uninstall.sh</A>.
            </p>
            <pre className="mt-6 whitespace-pre-wrap break-words rounded-2xl bg-ink p-4 font-mono text-small text-white/90 ring-1 ring-white/10 dark:bg-[#1c1222]">
              <span className="text-white/45"># /private/etc/sudoers.d/wham, for user ID 501 (you)</span>
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

function Footer() {
  return (
    <footer className="page pb-8">
      <div className="relative overflow-hidden rounded-4xl bg-night px-8 py-16 text-center text-white dark:ring-1 dark:ring-white/10">
        <div
          aria-hidden="true"
          className="absolute inset-x-0 -bottom-24 mx-auto h-48 w-[80%] rounded-full bg-[radial-gradient(closest-side,rgba(255,3,180,0.35),transparent)]"
        />
        <div className="relative flex flex-col items-center">
          <PixelSprite rows={SUN_LIT} cell={4} className="text-candy-yellow" />
          <p className="mt-6 text-title font-black">
            <span className="block">
              Wake me up before you <span className="whitespace-nowrap">go-go?</span>
            </span>{" "}
            <span className="block text-white/60">Your Mac won&apos;t need it.</span>
          </p>
          <a
            href="https://gwendall.com"
            className="group mt-12 flex flex-col items-center gap-3 rounded-2xl p-3"
            aria-label="Made by Gwendall, gwendall.com"
          >
            <span className="flex items-center gap-3 font-pixel text-pixel text-white/60 pixel-even">
              Made with
              <PixelSprite rows={HEART} cell={3} className="text-candy-pink transition-transform duration-300 group-hover:scale-125" />
              by
            </span>
            <span className="font-pixel text-pixel-lg text-white pixel-even transition-colors group-hover:text-candy-yellow">Gwendall</span>
            <span className="h-1 w-full bg-candy opacity-80 transition-opacity group-hover:opacity-100" />
          </a>
        </div>
      </div>
      <div className="mt-6 flex flex-col items-center justify-between gap-3 text-small text-muted sm:flex-row">
        <p className="flex items-center gap-2">
          <PixelSprite rows={SUN} cell={1} />
          Wham is free and open source, under the <A href={`${GITHUB}/blob/main/LICENSE`}>MIT</A> license.
        </p>
        <nav aria-label="Footer" className="flex items-center gap-6 font-bold">
          <a href={GITHUB} className="transition-colors hover:text-fg">
            GitHub
          </a>
          <a href="/install" className="transition-colors hover:text-fg">
            install.sh
          </a>
          <a href="/uninstall" className="transition-colors hover:text-fg">
            uninstall.sh
          </a>
        </nav>
      </div>
    </footer>
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

function NavLink({ href, className = "", children }: { href: string; className?: string; children: ReactNode }) {
  return (
    <a href={href} className={`h-10 items-center rounded-full px-4 transition-colors hover:bg-fg/6 ${className}`}>
      {children}
    </a>
  );
}

function Code({ children }: { children: ReactNode }) {
  return <code className="rounded-sm bg-fg/7 px-1 font-mono text-[0.875em] text-fg">{children}</code>;
}

function A({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a
      href={href}
      className="font-bold text-fg underline decoration-candy-pink decoration-2 underline-offset-4 transition-colors hover:decoration-candy-cyan"
    >
      {children}
    </a>
  );
}

function Prompt() {
  return (
    <span aria-hidden="true" className="select-none text-white/45">
      ${" "}
    </span>
  );
}

function GitHubIcon() {
  return (
    <svg aria-hidden="true" width="20" height="20" viewBox="0 0 16 16" fill="currentColor">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8Z" />
    </svg>
  );
}

const DOWN = ["..##..", "..##..", "..##..", "######", ".####.", "..##..", "......", "######"];
