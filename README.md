<p align="center">
  <img src="docs/icon.png" width="128" alt="Wham's icon: a pixel sun on a candy gradient">
</p>

<h1 align="center">Wham</h1>

<p align="center">
  <b>Close the lid. Your Mac stays awake.</b><br>
  A one-click menu bar switch that keeps your Mac awake, for real, even with the lid shut.<br>
  <a href="https://wham.sh">wham.sh</a>
</p>

<p align="center">
  <img src="docs/toast-on.png" width="294" alt="MAC STAYS AWAKE - Even with the lid closed">
  <img src="docs/toast-off.png" width="266" alt="MAC CAN SLEEP - Back to normal sleep">
</p>

## What for

Anything that should keep running after you close the lid:

- **AI agents in the terminal.** Claude Code, Codex, OpenCode or Grok finish
  the task while you are away.
- **Video exports and renders.** Final Cut, Premiere, DaVinci Resolve, ffmpeg,
  Blender.
- **Local AI.** Ollama or LM Studio serving your other devices, big model
  downloads, fine-tunes.
- **Builds, tests, downloads, backups and syncs.**
- **Servers and remote access.** A dev server you open from your phone, Plex,
  SSH, tmux, Screen Sharing.

Scripts and agents can flip it too: `wham on` before a long job, `wham off`
after.

## Install

**[Download Wham](https://wham.sh/download)**, open it and drag Wham into
Applications. Open Wham and click its switch in the menu bar. That is all: no
Terminal, no settings.

From a terminal, if you prefer:

| | |
| --- | --- |
| Script | `curl -fsSL wham.sh \| sh` |
| Homebrew | `brew install gwendall/tap/wham` |
| npm | `npx wham.sh` |

Wham needs macOS 11 Big Sur or later, on Apple silicon or Intel. Every way
installs the same signed and notarized app from the
[latest release](https://github.com/gwendall/wham/releases/latest).

## Use it

Wham lives in your menu bar as a little switch.

- **Click it**: the sun comes up, the switch turns candy, and your Mac stays
  awake. Close the lid, put it in a bag, unplug the screen: it keeps running.
- **Click again**: the moon comes back and your Mac sleeps as usual.
- **Right-click** (or control-click) for the menu: sound, open at login, quit.

The first time you turn it on, macOS asks for your password, once (see
[how it works](#how-it-works)). Quitting Wham always gives sleep back.

From a terminal, the installer also gives you a `wham` command:

```sh
wham on        # your Mac stays awake, lid closed too
wham off       # your Mac sleeps as usual
wham toggle
wham status
```

> Mind the heat: a Mac that stays awake in a closed bag gets warm. Turn Wham
> off when you do not need it.

## How it works

Keeping a Mac awake with the lid open is easy: apps like `caffeinate` or
Amphetamine hold a *power assertion*. But when you close the lid, macOS ignores
power assertions and sleeps anyway, unless an external display, keyboard and
power adapter are plugged in.

The one switch macOS does honor with the lid closed is the kernel's
`SleepDisabled` flag, set by:

```sh
sudo pmset -a disablesleep 1   # on
sudo pmset -a disablesleep 0   # off
```

That is all Wham does. To flip it without asking for your password every time,
Wham installs one sudoers rule, the first time, with your permission:

```
# /private/etc/sudoers.d/wham
#501 ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

It allows exactly those two commands, for your user (named by its ID, here
501, so any user name works), and nothing else. Wham checks the rule with
`visudo` before installing it.

The switch always shows what the kernel says, read from the IORegistry every
two seconds, never a cached guess. If something else flips the flag (`wham on`
in a terminal, `pmset`, a reboot), the switch follows.

## Is it safe?

- About a thousand lines of Swift, no dependencies, no network access (the
  menu links to this page), no analytics.
- Every release is built from this repo, signed with Developer ID
  (`NQCA86NEA3`) and notarized by Apple. The `curl` installer refuses an app
  signed by anyone else.
- The only privilege Wham holds is the rule above. Uninstalling removes it.

## Tiny

Idle, Wham uses about 0.03 % of one CPU core and 10 MB of memory, and it is
1.4 MB on disk. One timer reads one kernel flag every two seconds; nothing else
runs. [docs/compatibility.md](docs/compatibility.md) has the measurements, the
budgets CI holds it to, and every Mac setup we know of that could get in the
way (old macOS versions, standard accounts, managed Macs, a full menu bar) with
what Wham does about each.

## Why not the Mac App Store?

Apps from the Mac App Store run in a sandbox, which cannot run `pmset` as root
or install a sudoers rule. A sandboxed app can only hold power assertions, and
macOS drops those when the lid closes. So any App Store "stay awake" app sleeps
with the lid shut; Wham cannot be one of them and still work.

## Uninstall

```sh
curl -fsSL wham.sh/uninstall | sh
```

This quits Wham (your Mac sleeps as usual again), removes the app, the `wham`
command, its settings and the sudoers rule (that last step asks for your
password). With Homebrew: `brew uninstall --zap wham`. With npm:
`npx wham.sh uninstall`.

## Build from source

You need the Xcode command line tools (`xcode-select --install`).

```sh
scripts/test.sh     # chime, sudoers rule and its install, sprites, CLI, shell scripts
scripts/build.sh    # build/Wham.app, universal, signed ad hoc without a Developer ID
scripts/eval.sh     # runs the app for real: idle CPU, memory, CLI speed
open build/Wham.app
```

| Path | What |
| --- | --- |
| `app/Sources` | The app: menu bar switch, toast, chime, `pmset` and sudoers, CLI |
| `install.sh`, `uninstall.sh` | What `curl wham.sh` and `curl wham.sh/uninstall` run |
| `scripts/release.sh` | Tags a release; GitHub Actions (`release.yml`) runs `scripts/package.sh`, publishes it and updates the cask |
| `packaging/wham.rb` | The Homebrew cask template |
| `npm` | The `wham.sh` npm package |
| `site` | [wham.sh](https://wham.sh), Next.js |
| `docs/brand.md` | Name, voice, colors, type, sprites, sound |

To release, `scripts/release.sh 1.2.0` from a clean main: it tags and pushes,
and the release workflow builds, signs, notarizes, publishes and updates the
Homebrew cask. The npm package only wraps the installer, which always fetches
the latest release, so it is published by hand (`cd npm && npm publish`) only
when the wrapper or the scripts change.

`scripts/lid-test.sh` checks the real thing: run it, close the lid for two
minutes, open it, and it tells you whether the Mac slept.

## Credits

Made by [Gwendall](https://gwendall.com).

The pixel letters are [Silkscreen](https://github.com/googlefonts/silkscreen)
by Jason Kottke, under the SIL Open Font License 1.1
([app/Resources/OFL.txt](app/Resources/OFL.txt)).

Wake me up before you go-go? Your Mac won't need it.

## License

[MIT](LICENSE)
