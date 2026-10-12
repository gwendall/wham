# dmgbuild settings for Wham.dmg, used by scripts/release.sh:
#
#   dmgbuild -s scripts/dmg.py -D app=build/Wham.app -D background=build/dmg/background.tiff Wham build/Wham.dmg
import os

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents/Resources/AppIcon.icns")

background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 200),
    "Applications": (490, 200),
}
