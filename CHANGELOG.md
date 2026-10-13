# Changelog

What changed in each version of Wham, newest first. Also on
[wham.sh/changelog](https://wham.sh/changelog), in ten languages.

<!-- Made from the changelog on wham.sh: edit it there, not here. -->

## 1.7.0 - 2026-10-14

- Wham speaks Traditional Chinese too, as written in Taiwan and Hong Kong, and draws it in the notes' pixel letters.
- Every language reread, line by line: the menu, the notes and the alerts read more naturally, and call your Mac's settings by the names macOS gives them.
- With the lid closed, when Wham gives sleep back (time up, low battery, too hot, `wham off`, or Wham quit), your Mac now goes to sleep. macOS only looks at the lid when it moves, so until now it stayed awake until you opened it. With an external display connected, it stays awake, as macOS would.
- On a charger too weak to keep up, the battery still runs down: Battery Limit now holds there too, as it does on battery.
- `wham on` no longer crashes on a duration too long to count: a session lasts a year at most.

## 1.6.0 - 2026-10-13

- Wham speaks your Mac's language: English, French, Spanish, German, Italian, Portuguese, Japanese, Korean or Chinese. The menu, the notes under the switch and the alerts follow the language your Mac is set to, with times and percentages written its way.
- The notes' pixel letters draw Japanese, Korean and Chinese too, with your Mac's own fonts set on the same grid of pixels.
- To see Wham in another language than your Mac's: System Settings > General > Language & Region > Applications. The `wham` command and its journal stay in English.

## 1.5.0 - 2026-10-13

- Every option in the menu answers with a little sound, from the same family as the switch's chime: up when it checks, down when it unchecks, a tick for a length or a limit, and a low note when Wham can't (too hot, the battery too low). Sound, in the menu, turns them all off.
- Battery Limit has a Never: on battery, your Mac stays awake until the battery runs out, for when that is what you want. Save your work first. Critical heat still lets it sleep.
- Wham keeps a journal, to tell afterwards what happened: when it turned on and off and why, the lid, sleep and wake, the battery, the heat, and while on, whether the network stayed up with the lid closed. It never leaves your Mac and names no one: no network name, no address. `wham log` prints it.

## 1.4.0 - 2026-10-13

- Every option in the menu keeps it open now: Turn On, the lengths, Sound, Appearance, Battery Limit and the others change as you click, and the menu stays so you can pick another. A click outside closes it.
- No Time Limit is always under the lengths now, checked while your Mac stays awake with no end. With Wham off, it turns Wham on with no end.
- Monochrome and Compact no longer jump: colors and width change together over half a second, at your display's refresh rate.

## 1.3.1 - 2026-10-13

- Check for Updates keeps the menu open now: the line itself shows Wham checking, with a small spinner, then says how it went.

## 1.3.0 - 2026-10-13

- Appearance, in the menu: Monochrome draws the switch in the color of your other menu bar icons, black or white.
- Appearance > Compact keeps only the sun or the moon, in a ring as wide as an icon: it turns in place instead of sliding, and a timed session runs out around it.
- Stay On After Restart, in the menu: if Wham is on when your Mac restarts or shuts down, it turns back on when you log in again, until a timed session's end. Unchecked, as it comes, Wham stays off after a restart.
- The first time, the password prompt now says why Wham asks: keeping your Mac awake with the lid closed takes a setting only an administrator can change.

## 1.2.3 - 2026-10-13

- Check for Updates, in the menu, looks for a new version right away: it installs it, or tells you that you already have the latest.
- With Update Automatically off, Wham installs nothing on its own, but its menu still tells you when a new version is out, one click away.
- After an update, a note under the switch says which version you now have, and What's New in the menu shows what changed in each one.

## 1.2.2 - 2026-10-13

- Each length in Turn On For says when it would end.
- Once on, the menu says until when your Mac stays awake, and how long is left.
- No Time Limit, under the lengths, keeps a timed session going until you turn it off.
- The switch's colors drain away as a timed session runs.
- A note drops down five minutes before a timed session ends.
- Battery Limit, in the menu: on battery, let your Mac sleep at 5, 10, 20 or 30%.

## 1.2.1 - 2026-10-12

- The menu opens whole, right under the switch, notch or not.

## 1.2.0 - 2026-10-12

- Turn On For 1, 2, 4 or 8 hours, from the menu.
- On battery at 10%, or when your Mac gets critically hot, Wham lets it sleep and says why.
- If Wham ever goes away without quitting, a crash or a force quit, your Mac gets its sleep back within a second.
- With the lid closed and no other screen, the built-in screen turns off.
- From a terminal: `wham on 2h`, and `wham run` before a command to stay awake just while it runs.

## 1.1.0 - 2026-10-12

- Wham updates itself, a few times a day. Update Automatically, in the menu, turns that off.
- One switch in the menu bar, with the sun or the moon in its knob, rolling as it slides.
- A new icon: the pixel sun, now smiling.

## 1.0.0 - 2026-10-12

- The first version: a switch in the menu bar that keeps your Mac awake, even with the lid closed. Click it again and your Mac sleeps as usual.
- A note under the switch says what your Mac will do now, with a little sound you can turn off.
- Wham opens at login, and offers to move itself to Applications when opened from the download.
- Signed by its developer and notarized by Apple. From a terminal, `wham on` and `wham off`.
