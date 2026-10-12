# Wham brand

Wham is a tiny macOS menu bar switch that keeps a Mac awake, even with the lid
closed. The brand is small, cute and loud in the way an 8-bit game is loud:
pixel letters, a candy gradient, a four-note chime.

The name winks at "Wake Me Up Before You Go-Go". The wink stays a wink: no
band imagery, no lyrics, no audio from the song. Always pair the name with what
it does ("Wham - your Mac stays awake, lid closed"), because the name alone
does not say it.

## Name

- Product: **Wham**. In prose, "Wham", never "WHAM!" or "Wham!".
- Domain and handle: **wham.sh**. The install line is the brand too:
  `curl -fsSL wham.sh | sh`.
- Wordmark: `WHAM` set in Silkscreen, uppercase, tracked wide. `.sh` may follow
  in the body face at reduced opacity.
- Bundle identifier: `sh.wham.app`. CLI command: `wham`.

## Voice

Short, plain, friendly. Say what the Mac will do, not what the app is.

- Headline: **Close the lid. Your Mac stays awake.**
- One-liner: A one-click menu bar switch that keeps your Mac awake, for real,
  even with the lid shut.
- On: **MAC STAYS AWAKE** - Even with the lid closed
- Off: **MAC CAN SLEEP** - Back to normal sleep
- The wink, used once, near the bottom: "Wake me up before you go-go? Your Mac
  won't need it."

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
| glow | `rgba(255, 3, 180, 0.45)` | the glow under candy elements |

The candy gradient runs left to right: pink, yellow, cyan. "On" is candy, "off"
is night.

## Type

- Display: **Silkscreen** by Jason Kottke (SIL Open Font License 1.1),
  uppercase, at multiples of 8 px so its pixels stay whole.
- Body: a rounded sans (SF Pro Rounded in the app, Nunito on the web).

## Sprites

Both are 11 x 11, one cell per pixel, drawn without smoothing.

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
####.......
.#####.....
.#########.
..#######..
....###....
```

## Sound

A four-note arpeggio on a 25% pulse wave, like an old console's square channel:
E5, G#5, B5, E6, 55 ms apart, the last note ringing 160 ms. It climbs to switch
on and falls, a little softer, to switch off. No reverb, no effects. The source
of truth is `app/Sources/Chime.swift`.

## Motion

Springs from Punkmaker's cards: things arrive on a spring (ω 16, ζ 0.72),
rising a few points and growing from 0.92; they leave in 0.16 s, easing in.
Letters of a title drop in one after the other, 22 ms apart.
