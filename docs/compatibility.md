# Compatibility and resources

Every case we know of that could stop Wham from working on a Mac, what Wham
does about it, and how that is checked. "Test" means `scripts/test.sh`, "eval"
means `scripts/eval.sh` (the real app, on the kernel's real flag, against its
budgets), "CI" means both on every push, on the GitHub runners listed below.
"Update test" is `scripts/update-test.sh` and "lid test" `scripts/lid-test.sh`,
both run by hand on a Mac: one needs the Developer ID certificate, the other a
lid to close.

The eval reaches the battery and the heat through a stand-in file
(`WHAM_FAKE_POWER`), and the menu through `WHAM_PRESS`, which has the app press
its own menu items by title: no accessibility permission, the same code paths.
Neither does anything unless set.

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
| Admin account | macOS asks for the password once, its prompt saying why (a setting only an administrator can change, and the one Wham then turns on and off); Wham installs `/private/etc/sudoers.d/wham` | Test: the rule passes `visudo`, the prompt says why; CI installs it as root with stand-in paths and checks 0440, root, exact content |
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
release; Check for Updates, in the menu, asks right away: the menu stays open,
and the line itself says Checking for Updates… with a spinner, then how it went
(up to date, no answer, or Updating to Wham X…). A newer one is
downloaded next to the app, checked with `codesign` (Wham's identifier, signed
by team `NQCA86NEA3`), run once (`wham version` must name the new version), and
swapped in; Wham then reopens from the new copy, with the switch as it was, and
says which version it now is. With Update Automatically off, Wham still asks,
downloads nothing, and offers the new version in its menu (Update to Wham X).

| Case | What Wham does | Checked by |
| --- | --- | --- |
| A release signed by anyone else, or that does not run | Refused, the running copy stays | `scripts/update-test.sh` |
| The app's folder is not writable (an admin installed it, a standard user runs it; managed Macs) | Never tries; the next install or `brew upgrade` updates it. Check for Updates says so and opens wham.sh | `Update.canReplace` |
| A build from source (ad hoc signed) | Never updates itself | `Update.canReplace`, test |
| Offline, GitHub down, a proxy that blocks it | Tries again in 6 hours, quietly; Check for Updates says it could not check | `curl --max-time`, `scripts/update-test.sh` |
| Update Automatically off | Asks, downloads nothing, offers Update to Wham X in the menu; a click installs it | `scripts/update-test.sh` |
| Check for Updates on the latest version | Says it is up to date | `scripts/update-test.sh` |
| Check for Updates clicked in the open menu | The menu stays open and the line says how the check went, its title where the menu's own start (24-point rows on macOS 26, 22 before). Closed meanwhile, or chosen with Return, a note says it | `scripts/eval.sh`, its pictures in CI |
| First launch of a new version | A note says which version it now is; not on a first install, nor for a build from source | `Update.isUpdate`, tests |
| The switch is on, or a password prompt is open | On stays on through the update; it waits for the prompt to close | `reopen`, `scripts/update-test.sh` |
| Opened from the disk image | No updates until it is in Applications | `runsFromTemporaryCopy` |
| Pre-release tags | Ignored | Test |

## The menu bar

| Case | What Wham does |
| --- | --- |
| Menu bar too full, or the switch hidden by the notch | Opening Wham again (Finder, Spotlight, Launchpad) shows a toast under the switch, or, if the switch is not visible, says so and how to make room (hold ⌘ and drag other icons away) |
| First launch | A "HI, I'M WHAM" toast points at the switch |
| Light and dark menu bars | The track and the knob follow the menu bar's appearance |
| A menu bar of monochrome icons | Appearance > Monochrome: everything in the menu bar's ink, the knob cut out of the track when on (eval: the setting, remembered) |
| Little room, or a switch wider than the icons around it | Appearance > Compact: the knob alone in a ring 23 points wide instead of 50, turning in place; a timed session runs out around it like a timer (eval: the status item's width) |
| A change of look | Colors and width move together over 0.45 s, on a critically damped spring, at the display's refresh rate (a display link on macOS 14 on, a 60 Hz timer before); Reduce Motion jumps to the end; a screen asleep ends it on time (eval: every frame of both options, there and back) |
| Clicking the switch, or its menu open | No menu bar highlight around it: the knob is the only feedback |
| A Mac with a notch, whose menu bar is taller than the switch | The menu hangs from the menu bar's bottom edge, whole, its first line in sight (eval: the menu opened for real, its window against its height) |
| Reduce Motion | The switch changes without animating |
| VoiceOver | The switch has a label and a tooltip that say the state and what a click does |
| Lid closed | No chime: it would play inside a bag |

## Sessions and guards

| Case | What Wham does | Checked by |
| --- | --- | --- |
| Turn On For 1, 2, 4 or 8 hours; Stay Awake For, while on | Ends then. Each length says when it would end; once on, the menu says until when and what is left, the tooltip until when | Eval: both menu items, the menu's lines |
| A timed session runs | The switch's candy drains from the far end toward the knob, whole at the start, a ring around the knob at the end. In quarter points, so the tick redraws only when there is something to see | Test: `Session.remaining` |
| Five minutes before the end, lid open | A note drops down, without a sound ("5 minutes left", and when it ends). Not for a session under ten minutes, nor under a closed lid | Test: `Session.warnAt`; eval |
| No Time Limit | During a timed session, drops the end and stays on; off, turns on with no end. Checked while on with no end. Always in the menu: a row shown or hidden while the menu is open would resize it under the pointer | Eval: pressed, and clicked in the open menu, on and off |
| `wham on 2h` (also `45m`, `1h30m`, `1d`, `90s`) | The same. Anything else exits 64 and changes nothing | Test: the parser; eval: `wham on 3s` ends 3 to 7 s later, `wham on 2x` is refused |
| `wham on` or `wham off` during a timed session | Drops the end | Eval |
| The end passes while Wham is closed | Ends as soon as Wham opens; one still to come carries on | Eval |
| `wham on 2h` while Wham is closed | Opens Wham out of sight, since Wham is what ends the session | Eval (on CI) |
| The clock jumps, or macOS naps the app | The end is a timer in the run loop's common modes, and every look compares it with the clock | Code: `Session.end`, the 2 s tick |
| On battery, at 10% or less | Turns off ("Battery at 10%") and will not turn on until plugged in, saying so | Test: `Session.end`; eval: the switch, the menu and `wham on` |
| Battery Limit at 5, 20 or 30% | The same at that charge. The app and `wham` share it (`defaults write sh.wham.app batteryLimit -int 20`); any other value counts as 10%. Raised over the charge on battery, it ends the session at once | Test; eval: 20% at 15% ends it and `wham on` refuses, 5% stays awake at 8% |
| Plugged in at any charge, or no battery | The charge never stops it | Test |
| Plugged back in after the battery stopped it | Stays off until asked | Eval |
| Critically hot (`thermalState` critical, or macOS's thermal pressure at trapping) | Turns off ("Your Mac got too hot") and will not turn on until it cools. Below critical it carries on, so a busy server is left alone | Test; eval, also with macOS's own thermal signal raised as root on CI |
| `wham run` while the battery or the heat says no | Runs the command anyway and says it cannot keep the Mac awake | Eval |

## However Wham ends

While on, Wham keeps a watchdog: a `/bin/sh` waiting on a pipe that only Wham
writes to. However Wham ends, macOS closes the pipe and the shell runs
`sudo -n pmset -a disablesleep 0`, one of the two commands of the rule.

| Case | What happens | Checked by |
| --- | --- | --- |
| Quit from the menu | Sleep comes back, and stays back at the next launch | Eval |
| Quit from outside while on (`brew upgrade`, a script) | Sleep comes back; opened again within a minute, Wham turns back on | Eval |
| A restart, a shutdown or a logout while on | Sleep comes back. With Stay On After Restart (off by default: a Mac restarted then put in a bag should sleep), Wham turns back on at the next login, until a timed session's end; one that ended meanwhile stays off. Without it, stays off, however quick the restart | Eval: the quit macOS sends, with and without the option, timed, expired |
| A crash, a force quit, `kill -9`, `kill` | The watchdog gives sleep back within a second | Test: a process killed with -9; eval: the app killed with -9 and with TERM |
| The same while off | Nothing changes | Eval |
| Something Wham started outlives it | The watchdog's pipe is closed on exec, so it still fires | Test |
| Ctrl-C, Ctrl-\ or a closed terminal reaching the watchdog | Ignored: only the pipe sets it off | Test |
| An update while on | The old copy stands its watchdog down, the new one puts out its own: on stays on | Update test |
| An administrator without the rule, typing a password for each `wham on` | The watchdog cannot run `pmset` without a password: sleep stays off until `wham off` | By design |

## `wham run`

| Case | What happens | Checked by |
| --- | --- | --- |
| The command ends | `wham run` exits with its status, and gives sleep back if it took it | Test, eval |
| A command that does not exist, or a file that is not a program | 127, 126 | Test, eval |
| Ctrl-C | Reaches the command; `wham run` waits it out, exits 130, gives sleep back | Eval |
| `kill` (TERM) or a hangup sent to `wham run` | Passed to the command, then sleep back (143, 129) | Eval |
| `wham run` killed with -9 | Its own watchdog gives sleep back; the command keeps running | Eval |
| Already on | Left on | Test, eval |
| The command turns sleep back on itself, or Wham does (battery, heat) | Left alone: `wham run` only undoes what it did | Eval |

## The lid and the screen

| Case | What Wham does | Checked by |
| --- | --- | --- |
| Lid closed, Wham on | The Mac stays awake | Lid test |
| Lid closed, no other display | Three seconds later, turns the built-in screen off (`pmset displaysleepnow`), which locks the Mac as Lock Screen in System Settings says | Lid test: says whether the screen went dark and the Mac locked |
| Lid closed on a MacBook driving a monitor | Leaves the screens alone | `Screen.builtInAloneAndLit` |
| Screen Sharing wakes the screen afterwards | Not fought: Wham acts once per lid close | Code |

## What Wham cannot change

- **Heat below critical.** Wham only lets go once macOS calls the Mac critically
  hot. In a closed bag, turn it off before you pack up.
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

CI holds every runner to the same budgets, and runs every eval above on each.
The run of 2026-10-12, with sessions, guards and the watchdog:

| Runner | Idle CPU per 30 s, off / on | Memory | App on, watchdog out, after `wham on` | `wham on 3s` ends after | Real thermal pressure |
| --- | --- | --- | --- | --- | --- |
| macOS 14.8, Apple silicon | 0.01 s / 0.01 s | 8 MB | 107 ms | 4.4 s | lets go, then back on |
| macOS 15.7, Apple silicon | 0.01 s / 0.02 s | 8 MB | 107 ms | 4.1 s | lets go, then back on |
| macOS 15.7, Intel | 0 s / 0.01 s | 5 MB | 164 ms | 4.0 s | lets go, then back on |
| macOS 26.6, Apple silicon | 0.01 s / 0.02 s | 10 MB | 173 ms | 4.2 s | lets go, then back on |

Where the little it does goes:

- One timer, every 2 s with 1 s of tolerance so macOS can batch it with other
  wakeups, reads one IORegistry property, and while on, the power source and
  the thermal state.
- The battery, the heat and the lid arrive as notifications from macOS, not
  polls. Off, Wham reads nothing else.
- While on, the watchdog waits on its pipe: a `/bin/sh` that uses no CPU.
- The sounds are made on the first click, so CoreAudio is not loaded until
  there is something to play.
- The toast window is created on first use (`defer: true`) and ordered out when it leaves.
- One request to GitHub a few times a day for updates (with Update
  Automatically off, Wham still asks but installs nothing). No analytics, no
  background daemon.
