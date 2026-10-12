# The Homebrew cask, published to gwendall/homebrew-tap by scripts/release.sh,
# which fills in the version and the zip's checksum.
cask "wham" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/gwendall/wham/releases/download/v#{version}/Wham.zip",
      verified: "github.com/gwendall/wham/"
  name "Wham"
  desc "Menu bar switch that keeps the Mac awake, even with the lid closed"
  homepage "https://wham.sh/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :big_sur"

  app "Wham.app"
  binary "#{appdir}/Wham.app/Contents/MacOS/Wham", target: "wham"

  # Quitting Wham gives sleep back. On `brew upgrade` the new copy opens right
  # after and turns itself back on.
  uninstall quit: "sh.wham.app"

  zap delete: "/private/etc/sudoers.d/wham",
      trash:  [
        "~/Library/LaunchAgents/sh.wham.app.plist",
        "~/Library/Preferences/sh.wham.app.plist",
      ]

  caveats <<~EOS
    Wham is in your menu bar: click its switch and your Mac stays awake,
    even with the lid closed. The first time, macOS asks for your password,
    once, to let Wham change that one setting.

    `brew uninstall --zap wham` also removes that permission
    (/private/etc/sudoers.d/wham).
  EOS
end
