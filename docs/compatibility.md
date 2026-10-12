# Compatibility and resources

Every case we know of that could stop Wham from working on a Mac, what Wham
does about it, and how that is checked. "Test" means `scripts/test.sh`, "eval"
means `scripts/eval.sh` (the real app against its budgets), "CI" means both on
every push, on the GitHub runners listed below.

## Systems

| | Status | Checked by |
| --- | --- | --- |
| macOS 14, 15, 26 | Runs | CI runs the tests and the evals on each |
| macOS 11, 12, 13 | Supported | CI compiles against macOS 11 for both architectures, so no newer API slips in. GitHub no longer runs these systems, so the app is not run there |
| macOS 10.15 and older | Not supported | The installer, the cask and the app's `LSMinimumSystemVersion` refuse it |
| Apple silicon | Runs | Universal binary, CI on `macos-14`, `macos-15`, `macos-26` |
| Intel | Runs | Same binary, CI on `macos-15-intel`, and under Rosetta locally |
| Virtual machines | The switch shows "unknown" if the VM has no `SleepDisabled` flag | Test skips the kernel check on CI when the flag is missing |

APIs from after macOS 11 are behind `#available`, or replaced:

- Springs: `CASpringAnimation(perceptualDuration:bounce:)` (macOS 14) is
  computed from stiffness and damping instead, the same curve.
- Open at login: `SMAppService` from macOS 13; before, a LaunchAgent in
  `~/Library/LaunchAgents/sh.wham.app.plist` that runs `open -b sh.wham.app`.
- `NSApp.activate()` (macOS 14) falls back to `activate(ignoringOtherApps:)`.
- IOKit's main port is passed as `0`, which every version accepts.

## Accounts and permissions

| Case | What Wham does | Checked by |
| --- | --- | --- |
| Admin account | macOS asks for the password once; Wham installs `/private/etc/sudoers.d/wham` | Test: the rule passes `visudo`; CI installs it as root with stand-in paths and checks 0440, root, exact content |
| Standard (non-admin) account | The same prompt takes an administrator's name and password; the rule is for the standard user | Same rule, by user ID |
| User names with spaces, dots, `@`, a domain (`DOMAIN\user`, `first.last@corp`) | The rule names the user by ID (`#501`), never by name | Test: rule text, `visudo` |
| Managed Macs whose `/etc/sudoers` does not read `sudoers.d` | Refuses to write a rule that would do nothing and says why in plain words; an administrator can still run `wham on` in Terminal, which asks for the password each time | Test: a stand-in sudoers without `includedir` is refused and nothing is written |
| `sudoers.d` missing | Created | Install script (`mkdir -p`) |
| Cancelled password prompt | The switch slides back, nothing changes | Code path `Install.cancelled` |
| Several users on one Mac | The flag is system-wide; each user's Wham shows it; each user gets their own rule | Kernel read every 2 s |
| `curl ... \| sudo sh` | The installer refuses to run as root | `install.sh` |

## Installing

| Case | What happens | Checked by |
| --- | --- | --- |
| `/Applications` not writable | Installs to `~/Applications` | `install.sh` |
| `/usr/local/bin` missing or not writable (most Apple silicon Macs) | Links `wham` in `~/.local/bin` and prints the exact line to add it to the PATH for zsh, bash or fish | `install.sh` |
| Running the installer again | Updates in place; the running Wham is stopped without its quit handler, so the sleep setting survives | Tried on this Mac |
| `brew upgrade` | Homebrew quits Wham (which gives sleep back) and reopens it; reopened within a minute, Wham turns itself back on. The cask says `auto_updates`, so Homebrew leaves the updates to Wham | `resumeAfterUpdate` |
| Opened from the disk image or straight from Downloads | Offers to move itself to Applications (and does it), since an app run from there cannot open at login | `runsFromTemporaryCopy` |
| Gatekeeper | Releases are signed with Developer ID and notarized; `install.sh` also refuses an app not signed by team `NQCA86NEA3` | `scripts/release.sh` (`spctl --assess`) |
| Login item held for approval (macOS 13+, some MDM) | Turning "Open at Login" on opens System Settings > Login Items | `LoginItem.set` |

## Updates

A minute after launch, then every 6 hours, Wham asks GitHub for the latest
release. A newer one is downloaded next to the app, checked with `codesign`
(Wham's identifier, signed by team `NQCA86NEA3`), run once (`wham version` must
name the new version), and swapped in; Wham then reopens from the new copy,
with the switch as it was.

| Case | What Wham does | Checked by |
| --- | --- | --- |
| A release signed by anyone else, or that does not run | Refused, the running copy stays | `scripts/update-test.sh` |
| The app's folder is not writable (an admin installed it, a standard user runs it; managed Macs) | Never tries; the next install or `brew upgrade` updates it | `Update.canReplace` |
| A build from source (ad hoc signed) | Never updates itself | `Update.canReplace`, test |
| Offline, GitHub down, a proxy that blocks it | Tries again in 6 hours, quietly | `curl --max-time` |
| The switch is on, or a password prompt is open | On stays on through the update; it waits for the prompt to close | `reopen`, `scripts/update-test.sh` |
| Opened from the disk image | No updates until it is in Applications | `runsFromTemporaryCopy` |
| Pre-release tags | Ignored | Test |

## The menu bar

| Case | What Wham does |
| --- | --- |
| Menu bar too full, or the switch hidden by the notch | Opening Wham again (Finder, Spotlight, Launchpad) shows a toast under the switch, or, if the switch is not visible, says so and how to make room (hold ⌘ and drag other icons away) |
| First launch | A "HI, I'M WHAM" toast points at the switch |
| Light and dark menu bars | The track and the knob follow the menu bar's appearance |
| Clicking the switch, or its menu open | No menu bar highlight around it: the knob is the only feedback |
| Reduce Motion | The switch changes without animating |
| VoiceOver | The switch has a label and a tooltip that say the state and what a click does |

## What Wham cannot change

- **Critically low battery.** macOS may still sleep to protect the battery.
- **Heat.** A Mac awake in a closed bag gets warm. Turn Wham off when you do
  not need it.
- **Apple menu > Sleep.** With `SleepDisabled` set, macOS blocks that too. Turn
  Wham off to sleep on demand.
- **The App Store.** Sandboxed apps cannot run `pmset` as root, so Wham is not
  on it (see the README).

## Resources

Measured on a MacBook Air (Apple silicon), macOS 26.6, by `scripts/eval.sh`:

| | Measured | Budget (eval fails above) |
| --- | --- | --- |
| Idle CPU, once settled | 0.01 s per 30 s (about 0.03 %) | 0.1 s per 30 s |
| Memory (physical footprint) | 10 MB | 40 MB |
| `wham` command | 0.03 s | 0.3 s |
| App on disk | 1.4 MB (536 KB of it the universal binary) | |
| Download (zip) | about 1 MB | |

CI holds every runner to the same budgets. The first run, on 2026-10-12:

| Runner | Idle CPU per 30 s | Memory | `wham on` / `wham off` flip the real flag |
| --- | --- | --- | --- |
| macOS 14.8, Apple silicon | 0.01 s | 8 MB | yes |
| macOS 15.7, Apple silicon | 0.05 s | 8 MB | yes |
| macOS 15.7, Intel | 0.01 s | 5 MB | yes |
| macOS 26.6, Apple silicon | 0.03 s | 10 MB | yes |

Where the little it does goes:

- One timer, every 2 s with 1 s of tolerance so macOS can batch it with other
  wakeups, reads one IORegistry property. Nothing else runs while idle.
- The sounds are made on the first click, so CoreAudio is not loaded until
  there is something to play.
- The toast window is created on first use (`defer: true`) and ordered out when it leaves.
- One request to GitHub a few times a day for updates (off with Update
  Automatically). No analytics, no helper process, no background daemon.
