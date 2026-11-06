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

        @MainActor static func item(_ key: String, _ english: String, _ chord: String) -> Entry {
            .init(title: MashMenus.localized(key, english), chord: chord)
        }
        static let separator = Entry(title: "", chord: nil)
    }

    static let file: [Entry] = [
        .item("herdr.menu.item.new_dev_tab", "New Dev Tab", "cmd+t"),
        .item("herdr.menu.item.new_agent_tab", "New Agent Tab", "cmd+alt+t"),
        .item("herdr.menu.item.new_review_tab", "New Review Tab", "cmd+shift+r"),
        .item("herdr.menu.item.new_shell_tab", "New Shell Tab", "cmd+shift+t"),
        .separator,
        .item("herdr.menu.item.new_workspace", "New Workspace…", "cmd+ctrl+n"),
        .item("herdr.menu.item.new_worktree", "New Worktree…", "cmd+ctrl+shift+n"),
        .item("herdr.menu.item.workspace_picker", "Workspace Picker…", "cmd+ctrl+o"),
        .separator,
        .item("herdr.menu.item.close_pane", "Close Pane", "cmd+alt+w"),
        .item("herdr.menu.item.close_tab", "Close Tab", "cmd+shift+w"),
        .item("herdr.menu.item.close_workspace", "Close Workspace", "cmd+ctrl+w"),
        .item("herdr.menu.item.remove_worktree", "Remove Worktree", "cmd+ctrl+backspace"),
    ]

    static let edit: [Entry] = [
        .item("herdr.menu.item.annotate_selection", "Annotate Selection", "cmd+k"),
        .item("herdr.menu.item.paste_annotations_into_agent", "Paste Annotations into Agent", "cmd+l"),
        .item("herdr.menu.item.manage_annotations", "Manage Annotations", "cmd+shift+l"),
        .separator,
        .item("herdr.menu.item.pick_link_or_id", "Pick Link or ID", "alt+g"),
    ]

    static let view: [Entry] = [
        .item("herdr.menu.item.toggle_sidebar", "Toggle Sidebar", "cmd+b"),
        .item("herdr.menu.item.zoom_pane", "Zoom Pane", "cmd+alt+z"),
        .separator,
        .item("herdr.menu.item.split_pane_right", "Split Pane Right", "cmd+alt+backslash"),
        .item("herdr.menu.item.split_pane_down", "Split Pane Down", "cmd+alt+minus"),
        .item("herdr.menu.item.resize_mode", "Resize Mode", "cmd+alt+r"),
    ]

    static let go: [Entry] = [
        .item("herdr.menu.item.goto", "Goto…", "cmd+ctrl+g"),
        .separator,
        .item("herdr.menu.item.previous_workspace", "Previous Workspace", "cmd+ctrl+bracket_left"),
        .item("herdr.menu.item.next_workspace", "Next Workspace", "cmd+ctrl+bracket_right"),
        .item("herdr.menu.item.previous_tab", "Previous Tab", "cmd+shift+bracket_left"),
        .item("herdr.menu.item.next_tab", "Next Tab", "cmd+shift+bracket_right"),
        .item("herdr.menu.item.previous_pane", "Previous Pane", "cmd+alt+bracket_left"),
        .item("herdr.menu.item.next_pane", "Next Pane", "cmd+alt+bracket_right"),
        .item("herdr.menu.item.previous_agent", "Previous Agent", "ctrl+shift+arrow_up"),
        .item("herdr.menu.item.next_agent", "Next Agent", "ctrl+shift+arrow_down"),
        .separator,
        .item("herdr.menu.item.open_notification_target", "Open Notification Target", "cmd+y"),
    ]

    static let tools: [Entry] = [
        .item("herdr.menu.item.command_palette", "Command Palette…", "cmd+shift+p"),
        .item("herdr.menu.item.file_finder", "File Finder…", "cmd+p"),
        .item("herdr.menu.item.source_control", "Source Control", "ctrl+shift+g"),
        .item("herdr.menu.item.session_search", "Session Search…", "cmd+alt+l"),
        .item("herdr.menu.item.snippets", "Snippets…", "cmd+alt+p"),
        .item("herdr.menu.item.container_status", "Container Status", "cmd+shift+o"),
        .item("herdr.menu.item.plugin_manager", "Plugin Manager", "cmd+shift+x"),
        .separator,
        .item("herdr.menu.item.fork_agent_from_message", "Fork Agent from Message…", "cmd+alt+y"),
    ]

    static let help: [Entry] = [
        .item("herdr.menu.item.mash_help", "Mash Help", "cmd+shift+i"),
        .item("herdr.menu.item.check_for_updates", "Check for Updates…", "cmd+shift+u"),
    ]

    /// Herdr's own settings, reload and detach chords, used by the app menu.
    static var settingsChord: String { native ? "ctrl+b>s" : "cmd+i" }
    static var reloadChord: String { native ? "ctrl+b>shift+r" : "cmd+r" }
    static var detachChord: String { native ? "ctrl+b>q" : "cmd+u" }

    // MARK: Native tables -- Herdr's stock prefix keys plus keys.native.toml.

    static let nativeFile: [Entry] = [
        .item("herdr.menu.item.new_dev_tab", "New Dev Tab", "ctrl+b>t"),
        .item("herdr.menu.item.new_agent_tab", "New Agent Tab", "ctrl+b>a"),
        .item("herdr.menu.item.new_review_tab", "New Review Tab", "ctrl+b>shift+v"),
        .item("herdr.menu.item.new_shell_tab", "New Shell Tab", "ctrl+b>shift+c"),
        .separator,
        .item("herdr.menu.item.new_workspace", "New Workspace…", "ctrl+b>shift+n"),
        .item("herdr.menu.item.new_worktree", "New Worktree…", "ctrl+b>shift+g"),
        .item("herdr.menu.item.workspace_picker", "Workspace Picker…", "ctrl+b>shift+f"),
        .separator,
        .item("herdr.menu.item.close_pane", "Close Pane", "ctrl+b>x"),
        .item("herdr.menu.item.close_tab", "Close Tab", "ctrl+b>shift+x"),
        .item("herdr.menu.item.close_workspace", "Close Workspace", "ctrl+b>shift+d"),
    ]

    static let nativeEdit: [Entry] = [
        .item("herdr.menu.item.annotate_selection", "Annotate Selection", "ctrl+b>i"),
        .item("herdr.menu.item.paste_annotations_into_agent", "Paste Annotations into Agent", "ctrl+b>shift+i"),
        .item("herdr.menu.item.manage_annotations", "Manage Annotations", "ctrl+b>m"),
        .separator,
        .item("herdr.menu.item.pick_link_or_id", "Pick Link or ID", "ctrl+b>u"),
    ]

    static let nativeView: [Entry] = [
        .item("herdr.menu.item.toggle_sidebar", "Toggle Sidebar", "ctrl+b>b"),
        .item("herdr.menu.item.zoom_pane", "Zoom Pane", "ctrl+b>z"),
        .separator,
        .item("herdr.menu.item.split_pane_right", "Split Pane Right", "ctrl+b>v"),
        .item("herdr.menu.item.split_pane_down", "Split Pane Down", "ctrl+b>minus"),
        .item("herdr.menu.item.resize_mode", "Resize Mode", "ctrl+b>r"),
    ]

    static let nativeGo: [Entry] = [
        .item("herdr.menu.item.goto", "Goto…", "ctrl+b>g"),
        .separator,
        .item("herdr.menu.item.previous_tab", "Previous Tab", "ctrl+b>p"),
        .item("herdr.menu.item.next_tab", "Next Tab", "ctrl+b>n"),
        .item("herdr.menu.item.previous_pane", "Previous Pane", "ctrl+b>shift+tab"),
        .item("herdr.menu.item.next_pane", "Next Pane", "ctrl+b>tab"),
        .separator,
        .item("herdr.menu.item.open_notification_target", "Open Notification Target", "ctrl+b>o"),
    ]

    static let nativeTools: [Entry] = [
        .item("herdr.menu.item.command_palette", "Command Palette…", "ctrl+b>semicolon"),
        .item("herdr.menu.item.file_finder", "File Finder…", "ctrl+b>f"),
        .item("herdr.menu.item.source_control", "Source Control", "ctrl+b>y"),
        .item("herdr.menu.item.session_search", "Session Search…", "ctrl+b>shift+e"),
        .item("herdr.menu.item.snippets", "Snippets…", "ctrl+b>shift+s"),
        .item("herdr.menu.item.container_status", "Container Status", "ctrl+b>shift+o"),
        .item("herdr.menu.item.plugin_manager", "Plugin Manager", "ctrl+b>shift+u"),
        .separator,
        .item("herdr.menu.item.fork_agent_from_message", "Fork Agent from Message…", "ctrl+b>shift+y"),
    ]

    static let nativeHelp: [Entry] = [
        .item("herdr.menu.item.mash_help", "Mash Help", "ctrl+b>shift+slash"),
        .item("herdr.menu.item.check_for_updates", "Check for Updates…", "ctrl+b>shift+z"),
    ]

    static func localized(_ key: String, _ english: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: english, comment: "Mash menu item")
    }

    private static let fileMenuTitle = String(localized: "menu.file", defaultValue: "File", comment: "File menu title")
    private static let editMenuTitle = String(localized: "menu.edit", defaultValue: "Edit", comment: "Edit menu title")
    private static let viewMenuTitle = String(localized: "menu.view", defaultValue: "View", comment: "View menu title")
    private static let goMenuTitle = String(localized: "menu.go", defaultValue: "Go", comment: "Go menu title")
    private static let toolsMenuTitle = String(
        localized: "menu.tools",
        defaultValue: "Tools",
        comment: "Tools menu title"
    )
    private static let helpMenuTitle = String(localized: "menu.help", defaultValue: "Help", comment: "Help menu title")
    private static let windowMenuTitle = String(
        localized: "menu.window",
        defaultValue: "Window",
        comment: "Window menu title"
    )

    // MainMenu.xib order: application menu, File, Edit, View, Window.
    private static let fileMenuIndex = 1
    private static let editMenuIndex = 2
    private static let viewMenuIndex = 3
    private static let windowMenuIndex = 4
    private static let menuIdentifierPrefix = "mash.menu."

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
        for (index, title, entries, nativeEntries) in [
            (fileMenuIndex, fileMenuTitle, file, nativeFile),
            (editMenuIndex, editMenuTitle, edit, nativeEdit),
            (viewMenuIndex, viewMenuTitle, view, nativeView),
        ] {
            guard let item = mainMenu.item(at: index), let menu = item.submenu else { continue }
            item.title = title
            menu.title = title
            remove(entries + nativeEntries, from: menu)
            append(native ? nativeEntries : entries, to: menu, target: target)
        }

        for index in mainMenu.items.indices.reversed() {
            guard let item = mainMenu.item(at: index),
                  item.identifier?.rawValue.hasPrefix(menuIdentifierPrefix) == true else { continue }
            mainMenu.removeItem(at: index)
        }

        if let windowItem = mainMenu.item(at: windowMenuIndex) {
            windowItem.title = windowMenuTitle
            windowItem.submenu?.title = windowMenuTitle
        }

        let insertAt = windowMenuIndex
        let menus = native
            ? [("go", goMenuTitle, nativeGo), ("tools", toolsMenuTitle, nativeTools)]
            : [("go", goMenuTitle, go), ("tools", toolsMenuTitle, tools)]
        for (offset, (identifier, title, entries)) in menus.enumerated() {
            let menu = NSMenu(title: title)
            append(entries, to: menu, target: target)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(menuIdentifierPrefix + identifier)
            item.submenu = menu
            mainMenu.insertItem(item, at: insertAt + offset)
        }

        let helpMenu = NSMenu(title: helpMenuTitle)
        append(native ? nativeHelp : help, to: helpMenu, target: target)
        let helpItem = NSMenuItem(title: helpMenuTitle, action: nil, keyEquivalent: "")
        helpItem.identifier = NSUserInterfaceItemIdentifier(menuIdentifierPrefix + "help")
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)
        NSApp.helpMenu = helpMenu
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
