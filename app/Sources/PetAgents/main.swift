import AppKit

setvbuf(stdout, nil, _IOLBF, 0)
// `PetAgents --hindi "gaana chalao" …` prints how Hindi / Hinglish commands are understood, then exits.
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--hindi" {
    for t in CommandLine.arguments.dropFirst(2) { print("\(t)  →  \(Hindi.toEnglishCommand(t) ?? "(not a rule; goes to translation / AI)")") }
    exit(0)
}

// `PetAgents --export-icon out.png` writes the app icon (used by build.sh).
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--export-icon" {
    try? AppIcon.png()?.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

// `PetAgents --when "call mom tomorrow at 5"` prints how a date is understood, then exits.
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--when" {
    for t in CommandLine.arguments.dropFirst(2) {
        let w = When.parse(t)
        print("\(t)  →  " + (w.map { "\"\($0.rest)\" \($0.spoken)" + ($0.duration.map { " for \(Int($0 / 60)) min" } ?? "") } ?? "no date"))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar app: no Dock icon
app.run()
