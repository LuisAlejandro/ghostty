import AppKit
import Cocoa
import GhosttyKit

// Mash: this binary is Mash.app's own executable. Whatever starts it -- the
// Dock, Finder, Spotlight, `open -a`, or macOS reopening apps after a restart
// -- starts it without Mash's isolated environment. So the first thing it does
// is hand this process to the bundle's setup script, which seeds ~/.mash,
// exports the environment and execs this binary again. Same pid throughout:
// macOS still sees one app, and a relaunched app is a real Mash.
//
// MASH_BIN is the setup's mark. A `+action` (the wizard runs `+list-fonts`)
// prints and exits, so it never needs the setup.
//
// A setup that fails must say so rather than leave the user with an app that
// vanished: the script execs this binary back with MASH_SETUP_ERROR, and this
// shows it in an alert before quitting. The same alert covers a script that
// cannot run, and one that returned without MASH_BIN -- execing it again
// would loop forever.
mashHandOffToSetup()

func mashHandOffToSetup() {
    let env = ProcessInfo.processInfo.environment
    if CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("+") }) { return }
    if let error = env["MASH_SETUP_ERROR"] { mashSetupFailed(error) }
    if env["MASH_BIN"] != nil { return }
    if env["MASH_SETUP_HANDOFF"] != nil {
        mashSetupFailed("The setup finished without preparing Mash's environment.")
    }
    setenv("MASH_SETUP_HANDOFF", "1", 1)

    let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    let script = exe.deletingLastPathComponent()
        .appendingPathComponent("../Resources/bin/mash-launch")
        .standardizedFileURL.path
    var argv: [UnsafeMutablePointer<CChar>?] = [strdup(script)]
    for arg in CommandLine.arguments.dropFirst() { argv.append(strdup(arg)) }
    argv.append(nil)
    execv(script, argv)
    mashSetupFailed("Could not run \(script): \(String(cString: strerror(errno))).")
}

func mashSetupFailed(_ reason: String) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Mash could not start"
    alert.informativeText = reason + "\n\nDetails are in ~/.mash/local/state/mash-launch.log."
    alert.addButton(withTitle: "Quit")
    alert.runModal()
    exit(1)
}

// Initialize Ghostty global state. We do this once right away because the
// CLI APIs require it and it lets us ensure it is done immediately for the
// rest of the app.
if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
    Ghostty.logger.critical("ghostty_init failed")

    // We also write to stderr if this is executed from the CLI or zig run
    switch Ghostty.launchSource {
    case .cli, .zig_run:
        let stderrHandle = FileHandle.standardError
        stderrHandle.write(
            "Mash Terminal failed to initialize! If you're executing it from the command line\n" +
            "then this is usually because an invalid action or multiple actions were specified.\n" +
            "Actions start with the `+` character.\n\n" +
            "View all available actions by running `mash-terminal +help`.\n")
        exit(1)

    case .app:
        // For the app we exit immediately. We should handle this case more
        // gracefully in the future.
        exit(1)
    }
}

// This will run the CLI action and exit if one was specified. A CLI
// action is a command starting with a `+`, such as `mash-terminal +boo`.
ghostty_cli_try_action()

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
