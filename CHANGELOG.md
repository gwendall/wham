# Changelog

What changed in each version of Wham, newest first. Also on
[wham.sh/changelog](https://wham.sh/changelog), in nine languages.

<!-- Made from the changelog on wham.sh: edit it there, not here. -->

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
