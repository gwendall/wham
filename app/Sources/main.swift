import AppKit

let args = Array(CommandLine.arguments.dropFirst())

// `Wham --render-sounds <dir>` writes every sound as a WAV file, numbered, to listen to them.
if args.first == "--render-sounds", args.count > 1 {
    let dir = URL(fileURLWithPath: args[1])
    for (index, sound) in Chime.Sound.all.enumerated() {
        let name = String(format: "%02d %@.wav", index + 1, sound.name.replacingOccurrences(of: "%", with: ""))
        try Chime.wav(Chime.samples(sound)).write(to: dir.appendingPathComponent(name))
    }
    exit(0)
}

// Called as `wham` (the link the installers create) or with a command: answer
// in the terminal. Launched from Finder or at login: run the menu bar app.
let calledAsCommand = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "wham"
if calledAsCommand || args.first.map(CLI.commands.contains) == true {
    exit(CLI.run(args))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = Wham()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
