# wham.sh

Keeps your Mac awake, even with the lid closed.

```sh
npx wham.sh
```

installs (or updates) [Wham](https://wham.sh), a menu bar switch: click it and
your Mac stays awake with the lid closed, click again and it sleeps as usual.
It runs the same script as `curl -fsSL wham.sh | sh`.

Then, from a terminal:

```sh
npx wham.sh status     # or on, off, toggle
npx wham.sh uninstall
```

The installer also links a `wham` command (`wham on`, `wham off`,
`wham status`). macOS 11 Big Sur or later.

Source, docs and the other ways to install: https://github.com/gwendall/wham

Made by [Gwendall](https://gwendall.com). MIT License.
