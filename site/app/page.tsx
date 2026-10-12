import type { ReactNode } from "react";
import { CopyCommand } from "@/components/CopyCommand";
import { HeroStage } from "@/components/HeroStage";
import { MenuBarDemo } from "@/components/MenuBarDemo";
import { PixelSprite } from "@/components/PixelSprite";
import { LidArt, RunArt, SwitchArt } from "@/components/StepArt";
import { HEART, MOON, SUN } from "@/lib/sprites";

const GITHUB = "https://github.com/gwendall/wham";

const STEPS = [
  {
    art: <SwitchArt />,
    title: "Click the switch",
    text: "The sun comes out and the chime plays. The very first time, macOS asks for your password, once.",
  },
  {
    art: <LidArt />,
    title: "Close the lid",
    text: "Like you always do. On a desk, in a dock, on the shelf by the router. No external display needed.",
  },
  {
    art: <RunArt />,
    title: "Your Mac keeps going",
    text: "Downloads, renders, builds, backups, servers, remote sessions: all of it keeps running until you flip it back.",
  },
];

const FAQ: { q: string; a: ReactNode }[] = [
  {
    q: "Is it safe?",
    a: (
      <>
        The only thing Wham can do as root is run <Code>pmset -a disablesleep 0</Code> or <Code>1</Code>: that is all its sudoers
        rule allows, and <Code>visudo</Code> checks the rule before it goes live. The app is signed with a Developer ID (the
        installer refuses anything else), and every line of it is on <A href={GITHUB}>GitHub</A>.
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
        Wham itself costs next to nothing: it reads one kernel flag every two seconds. But an awake Mac drains its battery like
        an awake Mac, lid closed or not. For long jobs, plug it in.
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
    q: "How do I uninstall it?",
    a: (
      <>
        One line: <Code>curl -fsSL wham.sh/uninstall | sh</Code>. It quits Wham (which gives sleep back), then removes the app,
        the <Code>wham</Code> command, its settings and the sudoers rule. With Homebrew: <Code>brew uninstall --zap wham</Code>.
      </>
    ),
  },
  {
    q: "Why not the Mac App Store?",
    a: (
      <>
        App Store apps live in a sandbox, and a sandboxed app cannot change the kernel&apos;s sleep setting. The ones that try
        settle for a power assertion, which is exactly what stops working when you close the lid.
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
        className="sr-only z-50 rounded-full bg-ink px-4 py-2 font-bold text-white focus:not-sr-only focus:fixed focus:left-4 focus:top-4"
      >
        Skip to content
      </a>
      <Header />
      <main id="main">
        <Hero />
        <TryIt />
        <HowItWorks />
        <Install />
        <Faq />
      </main>
      <Footer />
    </>
  );
}

function Header() {
  return (
    <header className="mx-auto flex max-w-6xl items-center justify-between px-4 py-5 sm:px-6">
      <a href="#main" className="flex items-center gap-2.5 rounded-lg" aria-label="Wham, back to the top">
        <PixelSprite rows={SUN} cell={2} />
        <span className="flex items-baseline">
          <span className="font-pixel text-[24px] leading-none tracking-[0.125em]">Wham</span>
          <span className="text-[15px] font-extrabold opacity-45">.sh</span>
        </span>
      </a>
      <nav aria-label="Main" className="flex items-center gap-1 text-[15px] font-bold">
        <a href="#how" className="hidden rounded-full px-3 py-2 hover:bg-fg/5 sm:block">
          How it works
        </a>
        <a href="#faq" className="hidden rounded-full px-3 py-2 hover:bg-fg/5 sm:block">
          FAQ
        </a>
        <a href="#install" className="rounded-full px-3 py-2 hover:bg-fg/5">
          Install
        </a>
        <a href={GITHUB} className="rounded-full p-2 hover:bg-fg/5" aria-label="Wham on GitHub">
          <GitHubIcon />
        </a>
      </nav>
    </header>
  );
}

function Hero() {
  return (
    <section className="mx-auto grid max-w-6xl grid-cols-1 items-center gap-6 px-4 pb-16 pt-4 sm:px-6 sm:pt-8 lg:grid-cols-[1.08fr_1fr] lg:gap-4 lg:pb-12 lg:pt-10">
      <div className="flex min-w-0 flex-col items-start">
        <p className="flex items-center gap-2 font-pixel text-[16px] leading-none text-muted">
          <PixelSprite rows={SUN} cell={1} className="text-candy-pink" />
          Menu bar app for macOS
        </p>
        <p aria-hidden="true" className="wordmark mt-5 font-pixel text-[64px] leading-none sm:text-[96px]">
          <span className="wordmark-shadow">Wham</span>
          <span className="wordmark-face">Wham</span>
        </p>
        <h1 className="mt-7 text-[38px] font-black leading-[1.06] tracking-[-0.025em] sm:text-[54px] lg:text-[46px] xl:text-[52px]">
          <span className="block">Close the lid.</span> <span className="candy-mark">Your Mac stays awake.</span>
        </h1>
        <p className="mt-5 max-w-[31rem] text-[18px] leading-[1.5] text-muted sm:text-[20px]">
          A one-click menu bar switch that keeps your Mac awake, for real, even with the lid shut.
        </p>
        <div className="mt-8 w-full max-w-[33rem]">
          <CopyCommand primary command="curl -fsSL wham.sh | sh" />
        </div>
        <div className="mt-5 flex flex-wrap items-center gap-x-5 gap-y-3">
          <a href="/download" className="btn-candy">
            <PixelSprite rows={DOWN} cell={2} />
            Download for Mac
          </a>
          <a href="#install" className="rounded-md text-[15px] font-bold underline decoration-2 underline-offset-4 hover:decoration-candy-pink">
            or Homebrew, npm
          </a>
        </div>
        <p className="mt-6 text-[14px] text-muted">Free and open source. macOS 11 Big Sur or later, Apple silicon and Intel.</p>
      </div>
      <HeroStage />
    </section>
  );
}

function TryIt() {
  return (
    <Section id="try" eyebrow="Try it" title="One switch in your menu bar.">
      <p className="mt-4 max-w-[38rem] text-[18px] leading-[1.55] text-muted">
        That is the whole app. A sun when your Mac stays awake, a moon when it can sleep, a little chime either way. Go on,
        click it.
      </p>
      <div className="mt-10">
        <MenuBarDemo />
      </div>
    </Section>
  );
}

function HowItWorks() {
  return (
    <Section id="how" eyebrow="How it works" title="Three steps. The third one is the point.">
      <ol className="mt-10 grid grid-cols-1 gap-4 md:grid-cols-3">
        {STEPS.map((step, i) => (
          <li key={step.title} className="flex flex-col rounded-[22px] bg-card p-6 ring-1 ring-line">
            <div className="flex h-[80px] items-end md:h-[96px]">{step.art}</div>
            <p className="mt-6 flex items-center gap-3">
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-candy font-pixel text-[16px] leading-none text-ink">
                {i + 1}
              </span>
              <span className="text-[21px] font-black tracking-[-0.01em]">{step.title}</span>
            </p>
            <p className="mt-3 text-[16px] leading-[1.55] text-muted">{step.text}</p>
          </li>
        ))}
      </ol>

      <div className="mt-6 grid grid-cols-1 overflow-hidden rounded-[22px] ring-1 ring-line md:grid-cols-2">
        <div className="bg-night p-6 text-white sm:p-8">
          <p className="flex items-center gap-2 font-pixel text-[16px] leading-none text-moon">
            <PixelSprite rows={MOON} cell={1} />
            Why the others fall asleep
          </p>
          <h3 className="mt-4 text-[24px] font-black leading-[1.15] tracking-[-0.01em]">
            Other apps hold a power assertion.
          </h3>
          <p className="mt-3 text-[16px] leading-[1.6] text-white/70">
            It is the polite way to ask macOS to stay up, the same thing <Code dark>caffeinate</Code> does. macOS honors it while
            the lid is open, then drops it the moment you close the lid. Your Mac sleeps anyway, halfway through the download.
          </p>
        </div>
        <div className="relative bg-candy p-6 text-ink sm:p-8">
          <div className="absolute inset-0 bg-white/30" aria-hidden="true" />
          <div className="relative">
            <p className="flex items-center gap-2 font-pixel text-[16px] leading-none">
              <PixelSprite rows={SUN} cell={1} />
              What Wham does
            </p>
            <h3 className="mt-4 text-[24px] font-black leading-[1.15] tracking-[-0.01em]">
              Wham flips the kernel&apos;s own sleep switch.
            </h3>
            <p className="mt-3 text-[16px] leading-[1.6] text-ink/80">
              It sets <Code light>pmset disablesleep</Code>, the flag macOS itself checks before it goes to sleep. With it on,
              closing the lid has nothing left to trigger. Flip it off and your Mac sleeps as usual.
            </p>
          </div>
        </div>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-6 rounded-[22px] bg-card p-6 ring-1 ring-line sm:p-8 lg:grid-cols-[1fr_1.25fr] lg:items-center">
        <div>
          <p className="font-pixel text-[16px] leading-none text-muted">One password, once</p>
          <h3 className="mt-4 text-[24px] font-black leading-[1.15] tracking-[-0.01em]">Exactly two commands. Nothing else.</h3>
          <p className="mt-3 text-[16px] leading-[1.6] text-muted">
            Changing that flag takes an administrator. So the first time you click, macOS shows its own password prompt, and Wham
            installs a sudoers rule that lets your account run two commands without a password: sleep off, sleep on. Wham never
            gets root for anything else, and uninstalling removes the rule.
          </p>
        </div>
        <pre className="min-w-0 overflow-x-auto whitespace-pre-wrap break-words rounded-[16px] bg-ink p-5 font-mono text-[13px] leading-[1.7] text-white/90 ring-1 ring-white/10 dark:bg-[#1c1222] sm:text-[14px]">
          <span className="text-white/45"># /private/etc/sudoers.d/wham, for user ID 501 (you)</span>
          {"\n"}
          <span className="text-candy-yellow">#501</span> ALL=(root) NOPASSWD: <span className="text-candy-pink">/usr/bin/pmset -a disablesleep 0</span>,{" "}
          <span className="text-candy-cyan">/usr/bin/pmset -a disablesleep 1</span>
        </pre>
      </div>
    </Section>
  );
}

function Install() {
  return (
    <Section id="install" eyebrow="Install" title="Pick your way in.">
      <p className="mt-4 max-w-[38rem] text-[18px] leading-[1.55] text-muted">
        Every one of them installs the same signed app, puts it in your menu bar and adds the <Code>wham</Code> command.
      </p>
      <div className="mt-10 grid grid-cols-1 gap-6 lg:grid-cols-[1.35fr_1fr]">
        <div className="flex min-w-0 flex-col rounded-[22px] bg-card p-4 ring-1 ring-line sm:p-8">
          <Label>Terminal (recommended)</Label>
          <div className="mt-3">
            <CopyCommand primary command="curl -fsSL wham.sh | sh" />
          </div>
          <p className="mt-3 text-[15px] leading-[1.55] text-muted">
            Downloads the latest release, checks that its developer signed it, puts it in Applications and opens it. Run it again
            to update. Curious first? <A href="/install">Read the script</A>.
          </p>
          <div className="mt-7 grid grid-cols-1 gap-5">
            <div>
              <Label>Homebrew</Label>
              <div className="mt-3">
                <CopyCommand command="brew install gwendall/tap/wham" />
              </div>
            </div>
            <div>
              <Label>npm</Label>
              <div className="mt-3">
                <CopyCommand command="npx wham.sh" />
              </div>
            </div>
          </div>
          <div className="mt-8 flex flex-wrap items-center gap-x-5 gap-y-3 border-t border-line pt-7">
            <a href="/download" className="btn-candy">
              <PixelSprite rows={DOWN} cell={2} />
              Download for Mac
            </a>
            <span className="text-[15px] text-muted">Wham.dmg: open it, drag Wham to Applications.</span>
          </div>
        </div>

        <div className="flex min-w-0 flex-col gap-6">
          <div className="min-w-0 rounded-[22px] bg-card p-5 ring-1 ring-line sm:p-8">
            <Label>From a terminal</Label>
            <p className="mt-3 text-[15px] leading-[1.55] text-muted">The same switch, for scripts and SSH sessions.</p>
            <pre className="mt-4 whitespace-pre-wrap break-words rounded-[16px] bg-ink p-5 font-mono text-[13px] leading-[1.75] text-white ring-1 ring-white/10 dark:bg-[#1c1222] sm:text-[14px]">
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
          </div>
          <div className="rounded-[22px] bg-card p-5 ring-1 ring-line sm:p-8">
            <Label>Requirements</Label>
            <ul className="mt-4 grid gap-3 text-[16px] font-semibold">
              <Check>macOS 11 Big Sur or later</Check>
              <Check>Apple silicon and Intel</Check>
              <Check>
                Free and open source, <A href={`${GITHUB}/blob/main/LICENSE`}>MIT</A>
              </Check>
            </ul>
            <a
              href={GITHUB}
              className="mt-6 inline-flex items-center gap-2 rounded-full bg-fg px-5 py-3 text-[15px] font-extrabold text-bg transition-transform hover:-translate-y-0.5"
            >
              <GitHubIcon />
              gwendall/wham on GitHub
            </a>
          </div>
        </div>
      </div>
    </Section>
  );
}

function Faq() {
  return (
    <Section id="faq" eyebrow="FAQ" title="Good questions.">
      <div className="mt-10 grid grid-cols-1 gap-3">
        {FAQ.map(({ q, a }) => (
          <details key={q} className="group rounded-[18px] bg-card ring-1 ring-line open:ring-candy-pink/50">
            <summary className="flex cursor-pointer items-center justify-between gap-4 rounded-[18px] px-5 py-4 text-[18px] font-extrabold sm:px-6 sm:py-5">
              {q}
              <span
                aria-hidden="true"
                className="faq-plus flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-fg/6 font-pixel text-[16px] leading-none transition-transform duration-300"
              >
                +
              </span>
            </summary>
            <div className="px-5 pb-5 text-[16px] leading-[1.65] text-muted sm:px-6 sm:pb-6">{a}</div>
          </details>
        ))}
      </div>
    </Section>
  );
}

function Footer() {
  return (
    <footer className="mx-auto max-w-6xl px-4 pb-10 pt-8 sm:px-6">
      <div className="relative overflow-hidden rounded-[28px] bg-night px-6 py-14 text-center text-white dark:ring-1 dark:ring-white/10">
        <div
          aria-hidden="true"
          className="absolute inset-x-0 -bottom-24 mx-auto h-48 w-[80%] rounded-full bg-[radial-gradient(closest-side,rgba(255,3,180,0.35),transparent)]"
        />
        <div className="relative flex flex-col items-center">
          <PixelSprite rows={SUN} cell={4} className="text-candy-yellow" />
          <p className="mt-6 text-[22px] font-black leading-[1.3] tracking-[-0.01em] text-balance sm:text-[26px]">
            <span className="block">
              Wake me up before you <span className="whitespace-nowrap">go-go?</span>
            </span>{" "}
            <span className="block text-white/60">Your Mac won&apos;t need it.</span>
          </p>
          <a
            href="https://gwendall.com"
            className="group mt-10 flex flex-col items-center gap-3 rounded-2xl px-4 py-2"
            aria-label="Made by Gwendall, gwendall.com"
          >
            <span className="flex items-center gap-3 font-pixel text-[16px] leading-none text-white/60">
              Made with
              <PixelSprite rows={HEART} cell={3} className="text-candy-pink transition-transform duration-300 group-hover:scale-125" />
              by
            </span>
            <span className="font-pixel text-[32px] leading-none tracking-[0.125em] text-white transition-colors group-hover:text-candy-yellow">
              Gwendall
            </span>
            <span className="h-[4px] w-full bg-candy opacity-80 transition-opacity group-hover:opacity-100" />
          </a>
        </div>
      </div>
      <div className="mt-6 flex flex-col items-center justify-between gap-3 px-2 text-[14px] text-muted sm:flex-row">
        <p className="flex items-center gap-2">
          <PixelSprite rows={SUN} cell={1} />
          Wham is free and open source, under the MIT license.
        </p>
        <nav aria-label="Footer" className="flex items-center gap-5 font-bold">
          <a href={GITHUB} className="hover:text-fg">
            GitHub
          </a>
          <a href="/install" className="hover:text-fg">
            install.sh
          </a>
          <a href="/uninstall" className="hover:text-fg">
            uninstall.sh
          </a>
        </nav>
      </div>
    </footer>
  );
}

function Section({ id, eyebrow, title, children }: { id: string; eyebrow: string; title: string; children: ReactNode }) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="mx-auto max-w-6xl scroll-mt-6 px-4 py-12 sm:px-6 sm:py-16">
      <p className="font-pixel text-[16px] leading-none text-candy-pink">{eyebrow}</p>
      <h2 id={`${id}-title`} className="mt-4 text-[32px] font-black leading-[1.08] tracking-[-0.02em] text-balance sm:text-[44px]">
        {title}
      </h2>
      {children}
    </section>
  );
}

function Label({ children }: { children: ReactNode }) {
  return <p className="font-pixel text-[16px] leading-none text-muted">{children}</p>;
}

function Code({ children, dark, light }: { children: ReactNode; dark?: boolean; light?: boolean }) {
  const tone = dark ? "bg-white/10 text-white" : light ? "bg-ink/10 text-ink" : "bg-fg/7 text-fg";
  return <code className={`rounded-md px-1.5 py-0.5 font-mono text-[0.88em] ${tone}`}>{children}</code>;
}

function A({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a href={href} className="font-bold text-fg underline decoration-candy-pink decoration-2 underline-offset-3 hover:decoration-candy-cyan">
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

function Check({ children }: { children: ReactNode }) {
  return (
    <li className="flex items-center gap-3">
      <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-candy text-ink">
        <PixelSprite rows={TICK} cell={2} />
      </span>
      <span>{children}</span>
    </li>
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
const TICK = [".....#", "....##", "#..##.", "####..", ".##..."];
