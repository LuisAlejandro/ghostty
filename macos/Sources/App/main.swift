import AppKit
import Cocoa
import GhosttyKit

import MachO

// AppKit caches Bundle.main's preferred localizations on first access. Mash
// reads Bundle metadata below before Ghostty initializes, so install the
// process-only AppleLanguages override before that first bundle lookup.
private func mashRegisterLanguage() {
    guard let language = ProcessInfo.processInfo.environment["MASH_LANGUAGE"], !language.isEmpty else { return }
    let defaults = UserDefaults.standard
    var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
    arguments["AppleLanguages"] = [language]
    defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
}

mashRegisterLanguage()

// Capture the loaded image and version before a replacement can change disk
// metadata. A marker or rereading VERSION is not evidence of this runtime.
let mashUpdateLoadedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
let mashUpdateLoadedUUID: String = {
    guard let header = _dyld_get_image_header(0) else { return "" }
    let h = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self).pointee
    guard h.magic == MH_MAGIC_64 else { return "" }
    var cursor = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
    var remaining = Int(h.sizeofcmds)
    for _ in 0..<h.ncmds {
        guard remaining >= MemoryLayout<load_command>.size else { return "" }
        let command = cursor.load(as: load_command.self)
        guard command.cmdsize >= MemoryLayout<load_command>.size, Int(command.cmdsize) <= remaining else { return "" }
        if command.cmd == LC_UUID, command.cmdsize >= MemoryLayout<uuid_command>.size {
            var value = cursor.load(as: uuid_command.self).uuid
            return withUnsafeBytes(of: &value) { $0.map { String(format: "%02X", $0) }.joined() }
        }
        cursor = cursor.advanced(by: Int(command.cmdsize))
        remaining -= Int(command.cmdsize)
    }
    return ""
}()

func mashUpdateState() -> (URL, [String: String])? {
    let data = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mash")
    let path = data.appendingPathComponent("local/state/update-transaction.plist")
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
          attrs[.type] as? FileAttributeType == .typeRegular,
          (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
          let bytes = try? Data(contentsOf: path),
          let state = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: String],
          state["schema"] == "1", let id = state["id"], UUID(uuidString: id) != nil,
          let app = state["app"], app.hasPrefix("/"), URL(fileURLWithPath: app).pathExtension == "app",
          let phase = state["phase"],
          ["preparing", "ready", "handoff", "quiescing", "swap-intent", "awaiting-ready", "recovery-required", "confirmed", "restored-previous", "cancelled", "failed-before-swap"].contains(phase) else { return nil }
    return (data, state)
}

func mashUpdateApplies(_ state: [String: String]) -> Bool {
    guard let app = state["app"] else { return false }
    return URL(fileURLWithPath: app).resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath()
}

func mashUpdateRegister(_ role: String) {
    let data = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mash")
    do { try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    catch { mashSetupFailed("Mash could not prepare its private process registry.") }
    let process = Process()
    process.executableURL = Bundle.main.resourceURL?.appendingPathComponent("bin/mash-update-processes")
    process.arguments = ["register", data.path, Bundle.main.bundleURL.path, String(getpid()), role]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { mashSetupFailed("Mash's process identity helper is unavailable.") }
    process.waitUntilExit()
    if process.terminationStatus != 0 { mashSetupFailed("Mash could not register its startup ownership.") }
}

func mashUpdateOwnerIsLive(_ state: [String: String]) -> Bool {
    guard let pid = state["owner_pid"], let start = state["owner_start"], let boot = state["boot"] else { return false }
    let process = Process()
    process.executableURL = Bundle.main.resourceURL?.appendingPathComponent("bin/mash-update-processes")
    process.arguments = ["owner-alive", pid, start, boot]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

func mashUpdateWait(_ data: URL, _ state: [String: String], action: String = "wait") -> Never {
    guard let id = state["id"] else { mashSetupFailed("The update attempt has no identity.") }
    // Recovery must survive reboot and old TMPDIR cleanup. The installed,
    // signed helper can stage a rescue waiter outside the bundle if necessary.
    var helper = Bundle.main.resourceURL?.appendingPathComponent("bin/mash-update-gate").path ?? ""
    if let work = state["work"], work.hasPrefix("/"),
       URL(fileURLWithPath: work).lastPathComponent.range(of: "^mash-update-[A-Za-z0-9]{6}$", options: .regularExpression) != nil,
       (try? String(contentsOfFile: work + "/.mash-update-owner", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) == id,
       let attrs = try? FileManager.default.attributesOfItem(atPath: work),
       attrs[.type] as? FileAttributeType == .typeDirectory,
       (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
       FileManager.default.isExecutableFile(atPath: work + "/mash-update-gate") {
        helper = work + "/mash-update-gate"
    }
    guard !helper.isEmpty, FileManager.default.isExecutableFile(atPath: helper) else {
        mashSetupFailed("The installed update recovery helper is unavailable. No app was removed.")
    }
    mashUpdateRegister("waiter")
    let args = ["/bin/bash", helper, action, Bundle.main.bundleURL.path, data.path, id] + CommandLine.arguments.dropFirst()
    var argv = args.map { strdup($0) }
    argv.append(nil)
    execv("/bin/bash", argv)
    mashSetupFailed("Could not wait for the active update. See mash-update.log.")
}

func mashUpdateEntry() {
    if CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("+") }) { return }
    setenv("MASH_RUNNING_VERSION", mashUpdateLoadedVersion, 1)
    guard let (data, state) = mashUpdateState(), let phase = state["phase"] else {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mash/local/state/update-transaction.plist")
        if FileManager.default.fileExists(atPath: path.path) { mashSetupFailed("Mash's update record is invalid. See mash-update.log before retrying.") }
        mashUpdateRegister(ProcessInfo.processInfo.environment["MASH_BIN"] == nil ? "setup" : "runtime")
        return
    }
    if !mashUpdateApplies(state) {
        if ["confirmed", "restored-previous", "cancelled", "failed-before-swap"].contains(phase) {
            mashUpdateRegister(ProcessInfo.processInfo.environment["MASH_BIN"] == nil ? "setup" : "runtime")
            return
        }
        mashSetupFailed("An update for another Mash location needs recovery. See mash-update.log before retrying.")
    }
    if phase == "quiescing" || phase == "swap-intent" ||
        (phase == "awaiting-ready" && (state["expected_uuid"] != mashUpdateLoadedUUID || state["candidate"] != mashUpdateLoadedVersion || !mashUpdateOwnerIsLive(state))) {
        mashUpdateWait(data, state)
    }
    if phase == "recovery-required" { mashUpdateWait(data, state, action: "recover") }
    mashUpdateRegister(ProcessInfo.processInfo.environment["MASH_BIN"] == nil ? "setup" : "runtime")
}

private var mashUpdateReadinessTimer: Timer?
func mashUpdateObserveReadiness() {
    guard mashUpdateReadinessTimer == nil, let (data, initial) = mashUpdateState(), mashUpdateApplies(initial),
          ["awaiting-ready", "recovery-required"].contains(initial["phase"] ?? ""), let id = initial["id"],
          initial["expected_uuid"] == mashUpdateLoadedUUID,
          initial["candidate"] == mashUpdateLoadedVersion else { return }
    func now() -> Int64 {
        var clock = timespec()
        guard clock_gettime(CLOCK_MONOTONIC, &clock) == 0 else { return -1 }
        return Int64(clock.tv_sec)
    }
    let started = now()
    guard started >= 0 else { return }
    let deadline = initial["readiness_deadline"].flatMap(Int64.init) ?? started + 180
    guard now() < deadline else { return }
    mashUpdateReadinessTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
        guard now() >= 0, now() < deadline,
              let (_, current) = mashUpdateState(), mashUpdateApplies(current), current["id"] == id,
              ["awaiting-ready", "recovery-required"].contains(current["phase"] ?? "") else { timer.invalidate(); return }
        guard TerminalController.all.contains(where: { $0.window?.isVisible == true }) else { return }
        let process = Process()
        process.executableURL = Bundle.main.resourceURL?.appendingPathComponent("bin/mash-update-processes")
        process.arguments = ["stamp", String(getpid())]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { timer.invalidate(); return }
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let stamp = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !stamp.isEmpty else { timer.invalidate(); return }
        let ack = ["id": id, "pid": String(getpid()), "start": stamp,
                   "uuid": mashUpdateLoadedUUID, "version": mashUpdateLoadedVersion]
        let target = data.appendingPathComponent("local/state/update-gui-\(id).plist")
        do {
            let encoded = try PropertyListSerialization.data(fromPropertyList: ack, format: .binary, options: 0)
            try encoded.write(to: target, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch { }
        timer.invalidate()
    }
}

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
mashUpdateEntry()
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
