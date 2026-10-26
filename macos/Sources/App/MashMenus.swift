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
/// Chords are the shipped defaults in Mash's `config/herdr/config.toml`,
/// written with Ghostty's key names (`bracket_left`, `arrow_up`). A user who rebinds one in Herdr loses that menu item; that
/// is accepted and documented rather than tracked at runtime.
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
    static let settingsChord = "cmd+i"
    static let reloadChord = "cmd+r"
    static let detachChord = "cmd+u"

    /// Adds Mash's items to the main menu: appended to File, Edit and View, and
    /// new Go, Tools and Help menus inserted before Window.
    static func install(into mainMenu: NSMenu, target: AppDelegate) {
        append(file, to: submenu(named: "File", in: mainMenu), target: target)
        append(edit, to: submenu(named: "Edit", in: mainMenu), target: target)
        append(view, to: submenu(named: "View", in: mainMenu), target: target)

        let windowIndex = mainMenu.indexOfItem(withTitle: "Window")
        let insertAt = windowIndex >= 0 ? windowIndex : mainMenu.numberOfItems
        for (offset, (title, entries)) in [("Go", go), ("Tools", tools)].enumerated() {
            let menu = NSMenu(title: title)
            append(entries, to: menu, target: target)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            mainMenu.insertItem(item, at: insertAt + offset)
        }

        let helpMenu = NSMenu(title: "Help")
        append(help, to: helpMenu, target: target)
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)
        NSApp.helpMenu = helpMenu
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
