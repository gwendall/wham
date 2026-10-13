# Wham brand

Wham is a tiny macOS menu bar switch that keeps a Mac awake, even with the lid
closed. The brand is small, cute and loud in the way an 8-bit game is loud:
pixel letters, a candy gradient, a four-note chime.

Wham is a sound word: short, loud, a little cartoon. No band imagery, no
lyrics, no audio from any song. Always pair the name with what it does ("Wham - your Mac stays awake, lid closed"), because the name alone
does not say it.

## Name

- Product: **Wham**. In prose, "Wham", never "WHAM!" or "Wham!".
- Domain and handle: **wham.sh**. The install line is the brand too:
  `curl -fsSL wham.sh | sh`.
- Wordmark: `WHAM` set in Silkscreen, uppercase, tracked like all Silkscreen
  (see Type). `.sh` may follow in the body face at reduced opacity.
- Bundle identifier: `sh.wham.app`. CLI command: `wham`.

## Voice

Short, plain, friendly. Say what the Mac will do, not what the app is.

- Headline: **Close the lid. Your Mac stays awake.**
- One-liner: A one-click menu bar switch that keeps your Mac awake, for real,
  even with the lid shut.
- On: **MAC STAYS AWAKE** - Even with the lid closed
- Off: **MAC CAN SLEEP** - Back to normal sleep
- The send-off, used once, near the bottom: "Close the lid and go. Your Mac
  won't need waking up."

## Colors

| Token | Value | Use |
| --- | --- | --- |
| candy-pink | `#ff7ad9` | gradient start |
| candy-yellow | `#ffd36e` | gradient middle |
| candy-cyan | `#6fd3ff` | gradient end |
| ink | `#1a0b17` | text on candy, light-mode text |
| night | `#0f0a14` | dark backgrounds |
| pill | `#141414` | the "off" pill |
| moon | `#bfb5ff` | the moon sprite |
| butter | `#fff1b8` | the sun's face in the app icon |
| blush | `#ff8fc8` | its cheeks and tongue |
| glow | `rgba(255, 3, 180, 0.45)` | the glow under candy elements |

The candy gradient runs left to right: pink, yellow, cyan. "On" is candy, "off"
is night.

## Type

- Display: **Silkscreen** by Jason Kottke (SIL Open Font License 1.1),
  uppercase, at multiples of 8 px so its pixels stay whole. The font leaves two
  of its pixels between capitals; every size is tracked -1/8 em so they sit one
  pixel apart.
- Body: a rounded sans (SF Pro Rounded in the app, Nunito on the web).

## Sprites

Both are 11 x 11, one cell per pixel, drawn without smoothing. Their ink fills
the whole box, so centering the box centers the sprite.

Sun (on):

```
.....#.....
.#...#...#.
..#.....#..
....###....
...#####...
##.#####.##
...#####...
....###....
..#.....#..
.#...#...#.
.....#.....
```

Moon (off):

```
....##.....
..###......
.###.......
.###.......
####.......
####.......
####......#
.#####...##
.#########.
..#######..
....###....
```

App icon: the sun with a face, wide awake and pleased about it, on a candy
squircle. 21 x 21, `#` ink, `o` butter, `p` blush; one cheek pixel on each side,
clear of the mouth. Under 64 px the icon uses the 11 x 11 sun with a butter
center instead. The source of truth is `scripts/icon.swift`.

```
..........#..........
..........#..........
...#......#......#...
....#...........#....
........#####........
......##ooooo##......
.....#ooooooooo#.....
.....#ooooooooo#.....
....#ooo#ooo#ooo#....
....#ooo#ooo#ooo#....
###.#ooooooooooo#.###
....#opo#ooo#opo#....
....#oooo###oooo#....
.....#ooo#p#ooo#.....
.....#ooooooooo#.....
......##ooooo##......
........#####........
....#...........#....
...#......#......#...
..........#..........
..........#..........
```

## Menu bar switch

One switch, with the sprite inside its knob. The track is 42 x 21 pt, the knob
17 pt with 2 pt around it, and the 11 pt sprite sits exactly 3 pt from the
knob's edge. Everything lands on whole device pixels.

- On: candy track, white knob on the right, ink sun.
- Off: the menu bar's ink at 20% for the track, the knob on the left in the
  menu bar's ink with the moon cut out of it.
- Unknown (the flag can't be read): the same in orange, knob in the middle.

The knob rolls as it slides, one radian per radius travelled, clockwise going
right, on a spring (0.42 s, bounce 0.2), and lands upright; the sun and the
moon trade places in its first turn. The switch is the only feedback: no menu
bar highlight around it on click or while the menu is open.

## Toast

A 52 pt pill that drops from the menu bar under the switch: the sprite in its
round end, as far from the left edge as from the top and bottom, then the
Silkscreen title over a line in the body face.

## Sound

A four-note arpeggio on a 25% pulse wave, like an old console's square channel:
E5, G#5, B5, E6, 55 ms apart, the last note ringing 160 ms. It climbs to switch
on and falls, a little softer, to switch off. No reverb, no effects. The source
of truth is `app/Sources/Chime.swift`.

The menu has four sounds, on the same wave, in the same key, shorter and
quieter than the chime. They say what kind of thing a click did, not which
option it was: the eye sees the rest.

| Sound | When |
|---|---|
| Check: G#5 and E6, up | An option turned on: Monochrome, Compact, Sound, Open at Login, Stay On After Restart, Update Automatically; Wham up to date |
| Uncheck: E6 and G#5, down | The same turned off (Sound unchecked is silent) |
| Select: one B5 | A value picked (a length with Wham already on, a battery limit), Check for Updates, a link |
| Refused: B4 down to A#4, out of the key | Too hot, the battery too low, an update that could not be had |

Turning on, with a length or not, plays the on chime; Quit plays the off chime
when Wham was on, and nothing otherwise. One sound plays at a time: the next
one cuts it. `Wham --render-sounds <dir>` writes them all as WAV files.

## Motion

Springs: things arrive on a spring (ω 16, ζ 0.72),
rising a few points and growing from 0.92; they leave in 0.16 s, easing in.
Letters of a title drop in one after the other, 22 ms apart.
