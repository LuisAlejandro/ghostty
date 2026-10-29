import AppKit
import GhosttyKit

/// Mash's own commands in the menu bar.
///
/// Every item runs a Herdr (or Mash launcher) command by sending the chord a
/// user would type into the focused terminal, through the `mash_send_key`
/// binding action. Herdr has no API for many of these, and a keystroke carries
/// Herdr's own context (active pane, its directory, the workspace) that a CLI
/// call would lose. Each window's surface talks to that window's Herdr, so an
/// item only ever reaches its own Mash instance.
///
/// Chords are the shipped defaults of the keybinding mode Mash seeded, read
/// from Ghostty's `mash-keybindings` config. Cursor-style chords come from
/// Mash's `config/herdr/config.toml`; Native ones are Herdr's stock Ctrl+B
/// prefix keys and Mash's `keys.native.toml`, sent as a sequence (`ctrl+b>n`).
/// Both use Ghostty's key names (`bracket_left`, `arrow_up`). A user who
/// rebinds one in Herdr loses that menu item; that is accepted and documented
/// rather than tracked at runtime.
@MainActor
enum MashMenus {
    struct Entry {
        let title: String
        /// Herdr chord, e.g. "cmd+ctrl+g". nil makes a separator.
        let chord: String?

        static func item(_ title: String, _ chord: String) -> Entry { .init(title: title, chord: chord) }
        static let separator = Entry(title: "", chord: nil)
    }

    static let file: [Entry] = [
        .item("New Dev Tab", "cmd+t"),
        .item("New Agent Tab", "cmd+alt+t"),
        .item("New Review Tab", "cmd+shift+r"),
        .item("New Shell Tab", "cmd+shift+t"),
        .separator,
        .item("New Workspace…", "cmd+ctrl+n"),
        .item("New Worktree…", "cmd+ctrl+shift+n"),
        .item("Workspace Picker…", "cmd+ctrl+o"),
        .separator,
        .item("Close Pane", "cmd+alt+w"),
        .item("Close Tab", "cmd+shift+w"),
        .item("Close Workspace", "cmd+ctrl+w"),
        .item("Remove Worktree", "cmd+ctrl+backspace"),
    ]

    static let edit: [Entry] = [
        .item("Annotate Selection", "cmd+k"),
        .item("Paste Annotations into Agent", "cmd+l"),
        .item("Manage Annotations", "cmd+shift+l"),
        .separator,
        .item("Pick Link or ID", "alt+g"),
    ]

    static let view: [Entry] = [
        .item("Toggle Sidebar", "cmd+b"),
        .item("Zoom Pane", "cmd+alt+z"),
        .separator,
        .item("Split Pane Right", "cmd+alt+backslash"),
        .item("Split Pane Down", "cmd+alt+minus"),
        .item("Resize Mode", "cmd+alt+r"),
    ]

    static let go: [Entry] = [
        .item("Goto…", "cmd+ctrl+g"),
        .separator,
        .item("Previous Workspace", "cmd+ctrl+bracket_left"),
        .item("Next Workspace", "cmd+ctrl+bracket_right"),
        .item("Previous Tab", "cmd+shift+bracket_left"),
        .item("Next Tab", "cmd+shift+bracket_right"),
        .item("Previous Pane", "cmd+alt+bracket_left"),
        .item("Next Pane", "cmd+alt+bracket_right"),
        .item("Previous Agent", "ctrl+shift+arrow_up"),
        .item("Next Agent", "ctrl+shift+arrow_down"),
        .separator,
        .item("Open Notification Target", "cmd+y"),
    ]

    static let tools: [Entry] = [
        .item("Command Palette…", "cmd+shift+p"),
        .item("File Finder…", "cmd+p"),
        .item("Source Control", "ctrl+shift+g"),
        .item("Session Search…", "cmd+alt+l"),
        .item("Snippets…", "cmd+alt+p"),
        .item("Container Status", "cmd+shift+o"),
        .item("Plugin Manager", "cmd+shift+x"),
        .separator,
        .item("Fork Agent from Message…", "cmd+alt+y"),
    ]

    static let help: [Entry] = [
        .item("Mash Help", "cmd+shift+i"),
    ]

    /// Herdr's own settings, reload and detach chords, used by the app menu.
    static var settingsChord: String { native ? "ctrl+b>s" : "cmd+i" }
    static var reloadChord: String { native ? "ctrl+b>shift+r" : "cmd+r" }
    static var detachChord: String { native ? "ctrl+b>q" : "cmd+u" }

    // MARK: Native tables -- Herdr's stock prefix keys plus keys.native.toml.

    static let nativeFile: [Entry] = [
        .item("New Dev Tab", "ctrl+b>t"),
        .item("New Agent Tab", "ctrl+b>a"),
        .item("New Review Tab", "ctrl+b>shift+v"),
        .item("New Shell Tab", "ctrl+b>shift+c"),
        .separator,
        .item("New Workspace…", "ctrl+b>shift+n"),
        .item("New Worktree…", "ctrl+b>shift+g"),
        .item("Workspace Picker…", "ctrl+b>shift+f"),
        .separator,
        .item("Close Pane", "ctrl+b>x"),
        .item("Close Tab", "ctrl+b>shift+x"),
        .item("Close Workspace", "ctrl+b>shift+d"),
    ]

    static let nativeEdit: [Entry] = [
        .item("Annotate Selection", "ctrl+b>i"),
        .item("Paste Annotations into Agent", "ctrl+b>shift+i"),
        .item("Manage Annotations", "ctrl+b>m"),
        .separator,
        .item("Pick Link or ID", "ctrl+b>u"),
    ]

    static let nativeView: [Entry] = [
        .item("Toggle Sidebar", "ctrl+b>b"),
        .item("Zoom Pane", "ctrl+b>z"),
        .separator,
        .item("Split Pane Right", "ctrl+b>v"),
        .item("Split Pane Down", "ctrl+b>minus"),
        .item("Resize Mode", "ctrl+b>r"),
    ]

    static let nativeGo: [Entry] = [
        .item("Goto…", "ctrl+b>g"),
        .separator,
        .item("Previous Tab", "ctrl+b>p"),
        .item("Next Tab", "ctrl+b>n"),
        .item("Previous Pane", "ctrl+b>shift+tab"),
        .item("Next Pane", "ctrl+b>tab"),
        .separator,
        .item("Open Notification Target", "ctrl+b>o"),
    ]

    static let nativeTools: [Entry] = [
        .item("Command Palette…", "ctrl+b>semicolon"),
        .item("File Finder…", "ctrl+b>f"),
        .item("Source Control", "ctrl+b>y"),
        .item("Session Search…", "ctrl+b>shift+e"),
        .item("Snippets…", "ctrl+b>shift+s"),
        .item("Container Status", "ctrl+b>shift+o"),
        .item("Plugin Manager", "ctrl+b>shift+u"),
        .separator,
        .item("Fork Agent from Message…", "ctrl+b>shift+y"),
    ]

    static let nativeHelp: [Entry] = [
        .item("Mash Help", "ctrl+b>shift+slash"),
    ]

    /// Whether Mash seeded the Native keymap. Set at menu install. The
    /// first-launch wizard runs inside an already-open window and then reloads
    /// the config, so this can flip once and the menus are rebuilt.
    static var native = false

    /// Adds Mash's items to the main menu: appended to File, Edit and View, and
    /// new Go, Tools and Help menus inserted before Window.
    ///
    /// Safe to call again after a config reload: the first-launch wizard runs
    /// inside an already-open terminal, so the mode can change after the menus
    /// were first built. Previously inserted Mash items are removed first.
    static func install(into mainMenu: NSMenu, target: AppDelegate, native: Bool) {
        self.native = native
        for (title, entries) in [("File", file), ("Edit", edit), ("View", view)] {
            let menu = submenu(named: title, in: mainMenu)
            remove(entries + nativeEntries(for: title), from: menu)
            append(native ? nativeEntries(for: title) : entries, to: menu, target: target)
        }

        for title in ["Go", "Tools", "Help"] {
            let index = mainMenu.indexOfItem(withTitle: title)
            if index >= 0 { mainMenu.removeItem(at: index) }
        }

        let windowIndex = mainMenu.indexOfItem(withTitle: "Window")
        let insertAt = windowIndex >= 0 ? windowIndex : mainMenu.numberOfItems
        let menus = native
            ? [("Go", nativeGo), ("Tools", nativeTools)]
            : [("Go", go), ("Tools", tools)]
        for (offset, (title, entries)) in menus.enumerated() {
            let menu = NSMenu(title: title)
            append(entries, to: menu, target: target)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            mainMenu.insertItem(item, at: insertAt + offset)
        }

        let helpMenu = NSMenu(title: "Help")
        append(native ? nativeHelp : help, to: helpMenu, target: target)
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)
        NSApp.helpMenu = helpMenu
    }

    /// The Native counterpart of one of the three appended system menus.
    private static func nativeEntries(for title: String) -> [Entry] {
        switch title {
        case "File": return nativeFile
        case "Edit": return nativeEdit
        default: return nativeView
        }
    }

    /// Drop items a previous install() appended, so a mode change does not
    /// leave the other mode's items behind.
    private static func remove(_ entries: [Entry], from menu: NSMenu?) {
        guard let menu else { return }
        let titles = Set(entries.compactMap { $0.chord == nil ? nil : $0.title })
        for item in menu.items.reversed() {
            let base = item.title.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? item.title
            if titles.contains(base) { menu.removeItem(item) }
        }
        while let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
    }

    /// Sends a Herdr chord to the key window's focused terminal.
    static func send(_ chord: String) {
        // The Help menu's search field becomes key while it is open, so fall
        // back to the main window: the terminal the user was last in.
        let window = [NSApp.keyWindow, NSApp.mainWindow].lazy
            .compactMap { $0?.windowController as? BaseTerminalController }
            .first
        guard let surface = window?.focusedSurface?.surface else { return }
        // Chords use Ghostty's key names, and Ghostty already reads Herdr's
        // `cmd` as `super`, so the table entry passes through unchanged.
        let action = "mash_send_key:" + chord
        _ = ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
    }

    /// Shows the chord on the menu item without making it a Ghostty-owned
    /// shortcut. The menu then consumes the key, and the item's action re-sends
    /// the same chord, so the net effect is the typed key reaching Herdr.
    static func applyShortcut(_ chord: String, to item: NSMenuItem) {
        // Drop a sequence shown by an earlier call, so re-applying after a mode
        // change does not stack two chords in one title.
        if let tab = item.title.firstIndex(of: "\t") {
            item.title = String(item.title[item.title.startIndex..<tab])
        }
        // A key equivalent holds one chord. A Native prefix sequence is shown
        // in the title instead, and the item has no key equivalent: the typed
        // sequence already reaches Herdr without the menu.
        if chord.contains(">") {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            let shown = chord.split(separator: ">").map { displayChord(String($0)) }.joined(separator: " ")
            item.title += "\t" + shown
            return
        }
        var mods: NSEvent.ModifierFlags = []
        var key = ""
        for part in chord.split(separator: "+").map(String.init) {
            switch part {
            case "cmd": mods.insert(.command)
            case "ctrl": mods.insert(.control)
            case "alt": mods.insert(.option)
            case "shift": mods.insert(.shift)
            default: key = keyEquivalent(part)
            }
        }
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = mods
        item.allowsAutomaticKeyEquivalentLocalization = false
        item.allowsAutomaticKeyEquivalentMirroring = false
    }

    /// A chord as macOS writes shortcuts, e.g. "⌃B" or "⇧N".
    private static func displayChord(_ chord: String) -> String {
        var out = ""
        var key = ""
        for part in chord.split(separator: "+").map(String.init) {
            switch part {
            case "ctrl": out += "⌃"
            case "alt": out += "⌥"
            case "shift": out += "⇧"
            case "cmd": out += "⌘"
            case "minus": key = "-"
            case "semicolon": key = ";"
            case "slash": key = "/"
            case "tab": key = "⇥"
            default: key = part.uppercased()
            }
        }
        return out + key
    }

    private static func keyEquivalent(_ name: String) -> String {
        switch name {
        case "backslash": return "\\"
        case "minus": return "-"
        case "bracket_left": return "["
        case "bracket_right": return "]"
        case "backspace": return String(UnicodeScalar(NSBackspaceCharacter)!)
        case "arrow_up": return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case "arrow_down": return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        default: return name
        }
    }

    private static func submenu(named title: String, in mainMenu: NSMenu) -> NSMenu? {
        mainMenu.item(withTitle: title)?.submenu
    }

    private static func append(_ entries: [Entry], to menu: NSMenu?, target: AppDelegate) {
        guard let menu else { return }
        if menu.numberOfItems > 0, menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }
        for entry in entries {
            guard let chord = entry.chord else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: entry.title, action: #selector(AppDelegate.sendMashChord(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = chord
            applyShortcut(chord, to: item)
            menu.addItem(item)
        }
    }
}
