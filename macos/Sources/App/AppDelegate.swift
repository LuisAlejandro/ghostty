import AppKit
import SwiftUI
import UserNotifications
import OSLog
import GhosttyKit

class AppDelegate: NSObject,
                    ObservableObject,
                    NSApplicationDelegate,
                    UNUserNotificationCenterDelegate,
                    GhosttyAppDelegate {
    // The application logger. We should probably move this at some point to a dedicated
    // class/struct but for now it lives here! 🤷‍♂️
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AppDelegate.self)
    )

    /// Various menu items so that we can programmatically sync the keyboard shortcut with the Ghostty config
    @IBOutlet private var menuAbout: NSMenuItem?
    @IBOutlet private var menuServices: NSMenu?
    @IBOutlet private var menuOpenConfig: NSMenuItem?
    @IBOutlet private var menuReloadConfig: NSMenuItem?
    @IBOutlet private var menuSecureInput: NSMenuItem?
    @IBOutlet private var menuQuit: NSMenuItem?

    @IBOutlet private var menuNewTab: NSMenuItem?
    @IBOutlet private var menuSplitRight: NSMenuItem?
    @IBOutlet private var menuSplitLeft: NSMenuItem?
    @IBOutlet private var menuSplitDown: NSMenuItem?
    @IBOutlet private var menuSplitUp: NSMenuItem?
    @IBOutlet private var menuClose: NSMenuItem?
    @IBOutlet private var menuCloseTab: NSMenuItem?
    @IBOutlet private var menuCloseWindow: NSMenuItem?
    @IBOutlet private var menuCloseAllWindows: NSMenuItem?

    @IBOutlet private var menuCopy: NSMenuItem?
    @IBOutlet private var menuPaste: NSMenuItem?
    @IBOutlet private var menuPasteSelection: NSMenuItem?
    @IBOutlet private var menuSelectAll: NSMenuItem?
    @IBOutlet private var menuFindParent: NSMenuItem?
    @IBOutlet private var menuFind: NSMenuItem?
    @IBOutlet private var menuSelectionForFind: NSMenuItem?
    @IBOutlet private var menuScrollToSelection: NSMenuItem?
    @IBOutlet private var menuFindNext: NSMenuItem?
    @IBOutlet private var menuFindPrevious: NSMenuItem?
    @IBOutlet private var menuHideFindBar: NSMenuItem?

    @IBOutlet private var menuToggleVisibility: NSMenuItem?
    @IBOutlet private var menuToggleFullScreen: NSMenuItem?
    @IBOutlet private var menuBringAllToFront: NSMenuItem?
    @IBOutlet private var menuZoomSplit: NSMenuItem?
    @IBOutlet private var menuPreviousSplit: NSMenuItem?
    @IBOutlet private var menuNextSplit: NSMenuItem?
    @IBOutlet private var menuSelectSplitAbove: NSMenuItem?
    @IBOutlet private var menuSelectSplitBelow: NSMenuItem?
    @IBOutlet private var menuSelectSplitLeft: NSMenuItem?
    @IBOutlet private var menuSelectSplitRight: NSMenuItem?
    @IBOutlet private var menuReturnToDefaultSize: NSMenuItem?

    @IBOutlet private var menuIncreaseFontSize: NSMenuItem?
    @IBOutlet private var menuDecreaseFontSize: NSMenuItem?
    @IBOutlet private var menuResetFontSize: NSMenuItem?
    @IBOutlet private var menuReadonly: NSMenuItem?

    @IBOutlet private var menuEqualizeSplits: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerUp: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerDown: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerLeft: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerRight: NSMenuItem?

    /// The dock menu
    private var dockMenu: NSMenu = NSMenu()

    /// This is only true before application has become active.
    private var applicationHasBecomeActive: Bool = false

    /// This is set in applicationDidFinishLaunching with the system uptime so we can determine the
    /// seconds since the process was launched.
    private var applicationLaunchTime: TimeInterval = 0

    /// AppKit treats positional command-line arguments as documents to open. This
    /// filter consumes the corresponding open-file events for arguments following
    /// `-e`. It is initialized lazily because most launches never open a file.
    private lazy var commandLineOpenFileFilter = CommandLineOpenFileFilter(
        arguments: CommandLine.arguments,
        workingDirectory: FileManager.default.currentDirectoryPath,
        fileExists: { FileManager.default.fileExists(atPath: $0) }
    )

    /// This is the current configuration from the Ghostty configuration that we need.
    private var derivedConfig: DerivedConfig = DerivedConfig()

    /// The ghostty global state. Only one per process.
    let ghostty: Ghostty.App

    /// The global undo manager for app-level state such as window restoration.
    lazy var undoManager = ExpiringUndoManager()

    /// The elapsed time since the process was started
    var timeSinceLaunch: TimeInterval {
        return ProcessInfo.processInfo.systemUptime - applicationLaunchTime
    }

    /// Tracks the windows that we hid for toggleVisibility.
    private(set) var hiddenState: ToggleVisibilityState?

    /// The observer for the app appearance.
    private var appearanceObserver: NSKeyValueObservation?

    /// Signals
    private var signals: [DispatchSourceSignal] = []

    private let appIconUpdater = AppIconUpdater()

    @MainActor private lazy var menuShortcutManager = Ghostty.MenuShortcutManager()

    override init() {
#if DEBUG
        ghostty = Ghostty.App(configPath: ProcessInfo.processInfo.environment["GHOSTTY_CONFIG_PATH"])
#else
        ghostty = Ghostty.App()
#endif
        super.init()

        ghostty.delegate = self
    }

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if
            let suite = UserDefaults.ghosttySuite,
            let clear = ProcessInfo.processInfo.environment["GHOSTTY_CLEAR_USER_DEFAULTS"],
            (clear as NSString).boolValue {
            UserDefaults.ghostty.removePersistentDomain(forName: suite)
        }
        #endif
        UserDefaults.ghostty.register(defaults: [
            // Disable the automatic full screen menu item because we handle
            // it manually.
            "NSFullScreenMenuItemEverywhere": false,

            // On macOS 26 RC1, the autofill heuristic controller causes unusable levels
            // of slowdowns and CPU usage in the terminal window under certain [unknown]
            // conditions. We don't know exactly why/how. This disables the full heuristic
            // controller.
            //
            // Practically, this means things like SMS autofill don't work, but that is
            // a desirable behavior to NOT have happen for a terminal, so this is a win.
            // Manual autofill via the `Edit => AutoFill` menu item still work as expected.
            "NSAutoFillHeuristicControllerEnabled": false,
        ])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // System settings overrides
        UserDefaults.ghostty.register(defaults: [
            // Disable this so that repeated key events make it through to our terminal views.
            "ApplePressAndHoldEnabled": false,
        ])

        // Store our start time
        applicationLaunchTime = ProcessInfo.processInfo.systemUptime

        // Check if secure input was enabled when we last quit.
        if UserDefaults.ghostty.bool(forKey: "SecureInput") != SecureInput.shared.enabled {
            toggleSecureInput(self)
        }

        // Initial config loading
        ghosttyConfigDidChange(config: ghostty.config)

        // Register our service provider. This must happen after everything is initialized.
        NSApp.servicesProvider = ServiceProvider()

        // This registers the Ghostty => Services menu to exist.
        NSApp.servicesMenu = menuServices

        // Setup a local event monitor for app-level keyboard shortcuts. See
        // localEventHandler for more info why.
        _ = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown],
            handler: localEventHandler)

        // Notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyConfigDidChange(_:)),
            name: .ghosttyConfigDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardSelectionDidChange(_:)),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyBellDidRing(_:)),
            name: .ghosttyBellDidRing,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(terminalWindowHasBell(_:)),
            name: .terminalWindowBellDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyNewWindow(_:)),
            name: Ghostty.Notification.ghosttyNewWindow,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyNewTab(_:)),
            name: Ghostty.Notification.ghosttyNewTab,
            object: nil)

        // Configure user notifications
        let actions = [
            UNNotificationAction(identifier: Ghostty.userNotificationActionShow, title: "Show")
        ]

        let center = UNUserNotificationCenter.current()

        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Ghostty.userNotificationCategory,
                actions: actions,
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        ])
        center.delegate = self

        // Observe our appearance so we can report the correct value to libghostty.
        self.appearanceObserver = NSApplication.shared.observe(
            \.effectiveAppearance,
             options: [.new, .initial]
        ) { _, change in
            guard let appearance = change.newValue else { return }
            guard let app = self.ghostty.app else { return }
            let scheme: ghostty_color_scheme_e
            if appearance.isDark {
                scheme = GHOSTTY_COLOR_SCHEME_DARK
            } else {
                scheme = GHOSTTY_COLOR_SCHEME_LIGHT
            }

            ghostty_app_set_color_scheme(app, scheme)
        }

        // Setup our menu
        setupMenuImages()
        if let mainMenu = NSApp.mainMenu {
            MashMenus.install(into: mainMenu, target: self, native: ghostty.config.mashKeybindings == "native")
            installMashAppMenuItems(into: mainMenu)
        }

        // Setup signal handlers
        setupSignals()

        switch Ghostty.launchSource {
        case .app:
            // Don't have to do anything.
            break

        case .zig_run, .cli:
            // Part of launch services (clicking an app, using `open`, etc.) activates
            // the application and brings it to the front. When using the CLI we don't
            // get this behavior, so we have to do it manually.

            // This never gets called until we click the dock icon. This forces it
            // activate immediately.
            applicationDidBecomeActive(.init(name: NSApplication.didBecomeActiveNotification))

            // We run in the background, this forces us to the front.
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.unhide(nil)
                NSApp.arrangeInFront(nil)
            }
        }
    }

    func applicationDidHide(_ notification: Notification) {
        // Keep track of our hidden state to restore properly
        self.hiddenState = .init()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // If we're back manually then clear the hidden state because macOS handles it.
        self.hiddenState = nil

        // First launch stuff
        if !applicationHasBecomeActive {
            applicationHasBecomeActive = true

            // Let's launch our first window. We only do this if we have no other windows. It
            // is possible to have other windows in a few scenarios:
            //   - if we're opening a URL since `application(_:openFile:)` is called before this.
            //   - if we're restoring from persisted state
            if TerminalController.all.isEmpty && derivedConfig.initialWindow {
                undoManager.disableUndoRegistration()
                _ = TerminalController.newWindow(ghostty)
                undoManager.enableUndoRegistration()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return derivedConfig.shouldQuitAfterLastWindowClosed
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let windows = NSApplication.shared.windows
        if windows.isEmpty { return .terminateNow }

        // If the user is shutting down, restarting, or logging out, we don't confirm quit.
        why: if let event = NSAppleEventManager.shared().currentAppleEvent {
            // If all Ghostty windows are in the background (i.e. you Cmd-Q from the Cmd-Tab
            // view), then this is null. I don't know why (pun intended) but we have to
            // guard against it.
            guard let keyword = AEKeyword("why?") else { break why }

            if let why = event.attributeDescriptor(forKeyword: keyword) {
                switch why.typeCodeValue {
                case kAEShutDown, kAERestart, kAEReallyLogOut:
                    return .terminateNow

                default:
                    break
                }
            }
        }

        // If our app says we don't need to confirm, we can exit now.
        if !ghostty.needsConfirmQuit { return .terminateNow }

        return terminate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // We have no notifications we want to persist after death,
        // so remove them all now. In the future we may want to be
        // more selective and only remove surface-targeted notifications.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// This is called when the application is already open and someone double-clicks the icon
    /// or clicks the dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If we have visible windows then we allow macOS to do its default behavior
        // of focusing one of them.
        guard !flag else { return true }

        // If we have any windows in our terminal manager we don't do anything.
        // This is possible with flag set to false if there a race where the
        // window is still initializing and is not visible but the user clicked
        // the dock icon.
        guard TerminalController.all.isEmpty else { return true }

        // If the application isn't active yet then we don't want to process
        // this because we're not ready. This happens sometimes in Xcode runs
        // but I haven't seen it happen in releases. I'm unsure why.
        guard applicationHasBecomeActive else { return true }

        if #available(macOS 27.0, *) {
            // It seems that with macOS 27, running an App Intent against an already
            // running app (from Shortcuts, Spotlight, the `shortcuts` CLI, ...)
            // opens the app through LaunchServices in the background before the
            // intent is delivered, which we receive as a reopen event.
            //
            // Ignore reopens from the intents runner unless it asked for us to come to
            // the front to prevent creating two windows (#14107).
            let appIntentsRunnerBundleIdentifiers: Set<String> = [
                "com.apple.WorkflowKit.BackgroundShortcutRunner",
                "com.apple.shortcuts",
                "com.apple.siriactionsd",
            ]

            if let event = NSAppleEventManager.shared().currentAppleEvent,
               let sender = event.senderBundleIdentifier,
               appIntentsRunnerBundleIdentifiers.contains(sender),
               !event.expectsActivation {
                AppDelegate.logger.info("reopen triggered by shortcuts (\(sender)), ignoring...")
                return true
            }
        }

        // No visible windows, open a new one.
        _ = TerminalController.newWindow(ghostty)
        return false
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // `-e` makes existing path arguments part of the child command, but
        // AppKit also reports those paths as documents to open. Only consume
        // matching command arguments so unrelated Finder or Dock requests work.
        if commandLineOpenFileFilter.shouldIgnore(filename) {
            Self.logger.debug("ignoring command argument open-file event path=\(filename, privacy: .public)")
            return true
        }

        // Ghostty will validate as well but we can avoid creating an entirely new
        // surface by doing our own validation here. We can also show a useful error
        // this way.

        var isDirectory = ObjCBool(true)
        guard FileManager.default.fileExists(atPath: filename, isDirectory: &isDirectory) else { return false }

        // Set to true if confirmation is required before starting up the
        // new terminal.
        var requiresConfirm: Bool = false

        // Initialize the surface config which will be used to create the tab or window for the opened file.
        var config = Ghostty.SurfaceConfiguration()

        if isDirectory.boolValue {
            // When opening a directory, check the configuration to decide
            // whether to open in a new tab or new window.
            config.workingDirectory = filename
        } else {
            // Unconditionally require confirmation in the file execution case.
            // In the future I have ideas about making this more fine-grained if
            // we can not inherit of unsandboxed state. For now, we need to confirm
            // because there is a sandbox escape possible if a sandboxed application
            // somehow is tricked into `open`-ing a non-sandboxed application.
            requiresConfirm = true

            // When opening a file, we want to execute the file. To do this, we
            // don't override the command directly, because it won't load the
            // profile/rc files for the shell, which is super important on macOS
            // due to things like Homebrew. Instead, we set the command to
            // `<filename>; exit` which is what Terminal and iTerm2 do.
            config.initialInput = "\(Ghostty.Shell.quote(filename)); exit\n"

            // For commands executed directly, we want to ensure we wait after exit
            // because in most cases scripts don't block on exit and we don't want
            // the window to just flash closed once complete.
            config.waitAfterCommand = true

            // Set the parent directory to our working directory so that relative
            // paths in scripts work.
            config.workingDirectory = (filename as NSString).deletingLastPathComponent
        }

        if requiresConfirm {
            // Confirmation required. We use an app-wide NSAlert for now. In the future we
            // may want to show this as a sheet on the focused window (especially if we're
            // opening a tab). I'm not sure.
            let alert = NSAlert()
            alert.messageText = "Allow Mash Terminal to execute \"\(filename)\"?"
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                break

            default:
                return false
            }
        }

        // Mash ships no Ghostty tabs, so every dock drop opens a window.
        _ = TerminalController.newWindow(ghostty, withBaseConfig: config)

        return true
    }

    /// Setup signal handlers
    private func setupSignals() {
        // Register a signal handler for config reloading. It appears that all
        // of this is required. I've commented each line because its a bit unclear.
        // Warning: signal handlers don't work when run via Xcode. They have to be
        // run on a real app bundle.

        // We need to ignore signals we register with makeSignalSource or they
        // don't seem to handle.
        signal(SIGUSR2, SIG_IGN)

        // Make the signal source and register our event handle. We keep a weak
        // ref to ourself so we don't create a retain cycle.
        let sigusr2 = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        sigusr2.setEventHandler { [weak self] in
            guard let self else { return }
            Ghostty.logger.info("reloading configuration in response to SIGUSR2")
            self.ghostty.reloadConfig()
        }

        // The signal source starts unactivated, so we have to resume it once
        // we setup the event handler.
        sigusr2.resume()

        // We need to keep a strong reference to it so it isn't disabled.
        signals.append(sigusr2)
    }

    // MARK: Notifications and Events

    /// This handles events from the NSEvent.addLocalEventMonitor. We use this so we can get
    /// events without any terminal windows open.
    private func localEventHandler(_ event: NSEvent) -> NSEvent? {
        return switch event.type {
        case .keyDown:
            localEventKeyDown(event)

        default:
            event
        }
    }

    private func localEventKeyDown(_ event: NSEvent) -> NSEvent? {
        // If the tab overview is visible and escape is pressed, close it.
        // This can't POSSIBLY be right and is probably a FirstResponder problem
        // that we should handle elsewhere in our program. But this works and it
        // is guarded by the tab overview currently showing.
        if event.keyCode == 0x35, // Escape key
           let window = NSApp.keyWindow,
           let tabGroup = window.tabGroup,
           tabGroup.isOverviewVisible {
            window.toggleTabOverview(nil)
            return nil
        }

        // If we have a main window then we don't process any of the keys
        // because we let it capture and propagate.
        guard NSApp.mainWindow == nil else { return event }

        // If this event as-is would result in a key binding then we send it.
        if let app = ghostty.app, let config = ghostty.config.config {
            var ghosttyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
            let match = (event.characters ?? "").withCString { ptr in
                ghosttyEvent.text = ptr
                if !ghostty_config_key_is_binding(config, ghosttyEvent) {
                    return false
                }

                return ghostty_app_key(app, ghosttyEvent)
            }

            // If the key was handled by Ghostty we stop the event chain. If
            // the key wasn't handled then we let it fall through and continue
            // processing. This is important because some bindings may have no
            // affect at this scope.
            if match {
                return nil
            }
        }

        // If this event would be handled by our menu then we do nothing.
        if let mainMenu = NSApp.mainMenu,
           mainMenu.performKeyEquivalent(with: event) {
            return nil
        }

        // If we reach this point then we try to process the key event
        // through the Ghostty key mechanism.

        // Ghostty must be loaded
        guard let ghostty = self.ghostty.app else { return event }

        // Build our event input and call ghostty
        if ghostty_app_key(ghostty, event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)) {
            // The key was used so we want to stop it from going to our Mac app
            Ghostty.logger.debug("local key event handled event=\(event, privacy: .public)")
            return nil
        }

        return event
    }

    @objc private func ghosttyConfigDidChange(_ notification: Notification) {
        // We only care if the configuration is a global configuration, not a surface one.
        guard notification.object == nil else { return }

        // Get our managed configuration object out
        guard let config = notification.userInfo?[
            Notification.Name.GhosttyConfigChangeKey
        ] as? Ghostty.Config else { return }

        ghosttyConfigDidChange(config: config)
    }

    @MainActor @objc private func keyboardSelectionDidChange(_ notification: Notification) {
        syncMenuShortcuts(ghostty.config)
        TerminalController.all.forEach { $0.relabelTabs() }
    }

    @objc private func ghosttyBellDidRing(_ notification: Notification) {
        if ghostty.config.bellFeatures.contains(.system) {
            NSSound.beep()
        }

        if ghostty.config.bellFeatures.contains(.audio) {
            if let configPath = ghostty.config.bellAudioPath,
               let sound = NSSound(contentsOfFile: configPath.path, byReference: false) {
                sound.volume = ghostty.config.bellAudioVolume
                sound.play()
            }
        }

        if ghostty.config.bellFeatures.contains(.attention) {
            // Bounce the dock icon if we're not focused.
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    @objc private func terminalWindowHasBell(_ notification: Notification) {
        guard notification.object is BaseTerminalController else { return }
        syncDockBadge()
    }

    private func requestBadgeAuthorizationAndSet(_ center: UNUserNotificationCenter) {
        center.requestAuthorization(options: [.badge]) { granted, error in
            if let error = error {
                Self.logger.warning("Error requesting badge authorization: \(error, privacy: .public)")
                return
            }

            // Permission granted, set the badge
            if granted {
                DispatchQueue.main.async {
                    self.setDockBadge()
                }
            }
        }
    }

    private func syncDockBadge() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized:
                // If we're authorized and allow badges, then set the badge.
                if settings.badgeSetting == .enabled {
                    DispatchQueue.main.async {
                        self.setDockBadge()
                    }
                } else if settings.badgeSetting == .notSupported {
                    // If badge setting is not supported, we may be in a sandbox that doesn't allow it.
                    // We can still attempt to set the badge and hope for the best, but we should also
                    // request authorization just in case it is a permissions issue.
                    self.requestBadgeAuthorizationAndSet(center)
                }

            case .notDetermined:
                // Not determined yet, request authorization for badge
                self.requestBadgeAuthorizationAndSet(center)

            case .denied, .provisional, .ephemeral:
                // In these known non-authorized states, do not attempt to set the badge.
                break

            @unknown default:
                // Handle future unknown states by doing nothing.
                break
            }
        }
    }

    @objc private func ghosttyNewWindow(_ notification: Notification) {
        let configAny = notification.userInfo?[Ghostty.Notification.NewSurfaceConfigKey]
        let config = configAny as? Ghostty.SurfaceConfiguration
        _ = TerminalController.newWindow(ghostty, withBaseConfig: config)
    }

    @objc private func ghosttyNewTab(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
        guard let window = surfaceView.window else { return }

        // We only want to listen to new tabs if the focused parent is
        // a regular terminal controller.
        guard window.windowController is TerminalController else { return }

        let configAny = notification.userInfo?[Ghostty.Notification.NewSurfaceConfigKey]
        let config = configAny as? Ghostty.SurfaceConfiguration

        _ = TerminalController.newWindow(ghostty, withBaseConfig: config, withParent: window)
    }

    private func setDockBadge() {
        let bellCount = NSApp.windows
            .compactMap { $0.windowController as? BaseTerminalController }
            .reduce(0) { $0 + ($1.bell ? 1 : 0) }
        let wantsBadge = ghostty.config.bellFeatures.contains(.attention) && bellCount > 0
        let label = wantsBadge ? (bellCount > 99 ? "99+" : String(bellCount)) : nil
        NSApp.dockTile.badgeLabel = label
        NSApp.dockTile.display()
    }

    private func ghosttyConfigDidChange(config: Ghostty.Config) {
        // Update the config we need to store
        self.derivedConfig = DerivedConfig(config)

        // Depending on the "window-save-state" setting we have to set the NSQuitAlwaysKeepsWindows
        // configuration. This is the only way to carefully control whether macOS invokes the
        // state restoration system.
        switch config.windowSaveState {
        case "never": UserDefaults.ghostty.setValue(false, forKey: "NSQuitAlwaysKeepsWindows")
        case "always": UserDefaults.ghostty.setValue(true, forKey: "NSQuitAlwaysKeepsWindows")
        case "default": fallthrough
        default: UserDefaults.ghostty.removeObject(forKey: "NSQuitAlwaysKeepsWindows")
        }

        // Config could change keybindings, so update everything that depends on that
        DispatchQueue.main.async {
            // The Mash first-launch wizard picks the keybinding mode after this
            // app has already built its menus, then reloads the config. Rebuild
            // Mash's menus so the chosen mode's chords are the ones shown.
            let native = config.mashKeybindings == "native"
            if native != MashMenus.native, let mainMenu = NSApp.mainMenu {
                MashMenus.install(into: mainMenu, target: self, native: native)
                self.installMashAppMenuItems(into: mainMenu)
            }
            self.syncMenuShortcuts(config)
        }
        TerminalController.all.forEach { $0.relabelTabs() }

        // Update our badge since config can change what we show.
        syncDockBadge()

        // Config could change window appearance. We wrap this in an async queue because when
        // this is called as part of application launch it can deadlock with an internal
        // AppKit mutex on the appearance.
        DispatchQueue.main.async { self.syncAppearance(config: config) }

        // Decide whether to hide/unhide app from dock and app switcher
        switch config.macosHidden {
        case .never:
            NSApp.setActivationPolicy(.regular)

        case .always:
            NSApp.setActivationPolicy(.accessory)
        }

        // If we have configuration errors, we need to show them.
        let c = ConfigurationErrorsController.sharedInstance
        c.errors = config.errors
        if c.errors.count > 0 {
            if c.window == nil || !c.window!.isVisible {
                c.showWindow(self)
            }
        }

        // We need to handle our global event tap depending on if there are global
        // events that we care about in Ghostty.
        if ghostty_app_has_global_keybinds(ghostty.app!) {
            if timeSinceLaunch > 5 {
                // If the process has been running for awhile we enable right away
                // because no windows are likely to pop up.
                GlobalEventTap.shared.enable()
            } else {
                // If the process just started, we wait a couple seconds to allow
                // the initial windows and so on to load so our permissions dialog
                // doesn't get buried.
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                    GlobalEventTap.shared.enable()
                }
            }
        } else {
            GlobalEventTap.shared.disable()
        }

        updateAppIcon(from: config)
    }

    /// Sync the appearance of our app with the theme specified in the config.
    private func syncAppearance(config: Ghostty.Config) {
        NSApplication.shared.appearance = .init(ghosttyConfig: config)
    }

    private func updateAppIcon(from config: Ghostty.Config) {
        Task.detached {
            await self.appIconUpdater.update(icon: AppIcon(config: config))
        }
    }

    // MARK: - Restorable State

    /// We support NSSecureCoding for restorable state. Required as of macOS Sonoma (14) but a good idea anyways.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive: UNNotificationResponse,
        withCompletionHandler: () -> Void
    ) {
        ghostty.handleUserNotification(response: didReceive)
        withCompletionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent: UNNotification,
        withCompletionHandler: (UNNotificationPresentationOptions) -> Void
    ) {
        let shouldPresent = ghostty.shouldPresentNotification(notification: willPresent)
        let options: UNNotificationPresentationOptions = shouldPresent ? [.banner, .sound] : []
        withCompletionHandler(options)
    }

    // MARK: - GhosttyAppDelegate

    func findSurface(forUUID uuid: UUID) -> Ghostty.SurfaceView? {
        for c in TerminalController.all {
            for view in c.surfaceTree where view.id == uuid {
                return view
            }
        }

        return nil
    }

    // MARK: - Global State

    func setSecureInput(_ mode: Ghostty.SetSecureInput) {
        let input = SecureInput.shared
        switch mode {
        case .on:
            input.global = true

        case .off:
            input.global = false

        case .toggle:
            input.global.toggle()
        }
        self.menuSecureInput?.state = if input.global { .on } else { .off }
        UserDefaults.ghostty.set(input.global, forKey: "SecureInput")
    }

    // MARK: - IB Actions

    /// Settings opens Herdr's settings: Ghostty's own config is managed by
    /// Mash and edited as a file.
    @IBAction func openConfig(_ sender: Any?) {
        MashMenus.send(MashMenus.settingsChord)
    }

    /// Reloads everything Mash can reload in place: Ghostty here, and Herdr
    /// through its own reload chord. Fresh is left alone; it has no config
    /// reload, only a script re-run that drops its timers and commands.
    @IBAction func reloadConfig(_ sender: Any?) {
        ghostty.reloadConfig()
        MashMenus.send(MashMenus.reloadChord)
    }

    /// Detach ends this window's Herdr client; the window then closes and its
    /// Mash instance is released, as with Close Window.
    @IBAction func detachHerdr(_ sender: Any?) {
        MashMenus.send(MashMenus.detachChord)
    }

    /// Target of every Mash menu item; the item carries its chord.
    @IBAction func sendMashChord(_ sender: NSMenuItem) {
        guard let chord = sender.representedObject as? String else { return }
        MashMenus.send(chord)
    }

    /// The app menu's Mash entries: Settings and Reload show Herdr's chords,
    /// and Detach sits after them. Safe to call again after a config reload:
    /// the first-launch wizard can change the keybinding mode after these items
    /// exist, so the old Detach item is dropped before the new one goes in.
    @MainActor private func installMashAppMenuItems(into mainMenu: NSMenu) {
        guard let appMenu = mainMenu.items.first?.submenu else { return }
        if let settings = menuOpenConfig { MashMenus.applyShortcut(MashMenus.settingsChord, to: settings) }
        if let reload = menuReloadConfig {
            MashMenus.applyShortcut(MashMenus.reloadChord, to: reload)
            for item in appMenu.items where item.action == #selector(detachHerdr(_:)) {
                appMenu.removeItem(item)
            }
            let detach = NSMenuItem(title: "Detach", action: #selector(detachHerdr(_:)), keyEquivalent: "")
            detach.target = self
            MashMenus.applyShortcut(MashMenus.detachChord, to: detach)
            appMenu.insertItem(detach, at: appMenu.index(of: reload) + 1)
        }
    }

    @IBAction func newWindow(_ sender: Any?) {
        _ = TerminalController.newWindow(ghostty)
    }

    @IBAction func closeAllWindows(_ sender: Any?) {
        TerminalController.closeAllWindows()
        AboutController.shared.hide()
    }

    @IBAction func showAbout(_ sender: Any?) {
        AboutController.shared.show()
    }

    @IBAction func toggleSecureInput(_ sender: Any) {
        setSecureInput(.toggle)
    }

    /// Toggles visibility of all Ghosty Terminal windows. When hidden, activates Ghostty as the frontmost application
    @IBAction func toggleVisibility(_ sender: Any) {
        // If we have focus, then we hide all windows.
        if NSApp.isActive {
            // Toggle visibility doesn't do anything if the focused window is native
            // fullscreen. This is only relevant if Ghostty is active.
            guard let keyWindow = NSApp.keyWindow,
                  !keyWindow.styleMask.contains(.fullScreen) else { return }

            NSApp.hide(nil)
            return
        }

        // If we're not active, we want to become active
        NSApp.activate(ignoringOtherApps: true)

        // Bring all windows to the front. Note: we don't use NSApp.unhide because
        // that will unhide ALL hidden windows. We want to only bring forward the
        // ones that we hid.
        hiddenState?.restore()
        hiddenState = nil
    }

    @IBAction func bringAllToFront(_ sender: Any) {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }

        NSApplication.shared.arrangeInFront(sender)
    }

    private struct DerivedConfig {
        let initialWindow: Bool
        let shouldQuitAfterLastWindowClosed: Bool

        init() {
            self.initialWindow = true
            self.shouldQuitAfterLastWindowClosed = false
        }

        init(_ config: Ghostty.Config) {
            self.initialWindow = config.initialWindow
            self.shouldQuitAfterLastWindowClosed = config.shouldQuitAfterLastWindowClosed
        }
    }

    struct ToggleVisibilityState {
        let hiddenWindows: [Weak<NSWindow>]
        let keyWindow: Weak<NSWindow>?

        fileprivate init() {
            // We need to know the key window so that we can bring focus back to the
            // right window if it was hidden.
            self.keyWindow = if let keyWindow = NSApp.keyWindow {
                .init(keyWindow)
            } else {
                nil
            }

            // We need to keep track of the windows that were visible because we only
            // want to bring back these windows if we remove the toggle.
            //
            // We also ignore fullscreen windows because they don't hide anyways.
            var visibleWindows = [Weak<NSWindow>]()
            NSApp.windows.filter {
                $0.isVisible &&
                !$0.styleMask.contains(.fullScreen)
            }.forEach { window in
                // We only keep track of selectedWindow if it's in a tabGroup,
                // so we can keep its selection state when restoring
                let windowToHide = window.tabGroup?.selectedWindow ?? window
                if !visibleWindows.contains(where: { $0.value === windowToHide }) {
                    visibleWindows.append(Weak(windowToHide))
                }
            }
            self.hiddenWindows = visibleWindows
        }

        func restore() {
            hiddenWindows.forEach { $0.value?.orderFrontRegardless() }
            keyWindow?.value?.makeKey()
        }
    }
}

// MARK: Menu

extension AppDelegate {
    /// This is called for the dock right-click menu.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        return dockMenu
    }

    private func reloadDockMenu() {
        // Mash has one window, so the Dock menu offers no New Window.
        dockMenu.removeAllItems()
    }

    /// Setup all the images for our menu items.
    private func setupMenuImages() {
        // Note: This COULD Be done all in the xib file, but I find it easier to
        // modify this stuff as code.
        self.menuAbout?.setImageIfDesired(systemSymbolName: "info.circle")
        self.menuOpenConfig?.setImageIfDesired(systemSymbolName: "gear")
        self.menuReloadConfig?.setImageIfDesired(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90")
        self.menuSecureInput?.setImageIfDesired(systemSymbolName: "lock.display")
        self.menuNewTab?.setImageIfDesired(systemSymbolName: "macwindow")
        self.menuSplitRight?.setImageIfDesired(systemSymbolName: "rectangle.righthalf.inset.filled")
        self.menuSplitLeft?.setImageIfDesired(systemSymbolName: "rectangle.leadinghalf.inset.filled")
        self.menuSplitUp?.setImageIfDesired(systemSymbolName: "rectangle.tophalf.inset.filled")
        self.menuSplitDown?.setImageIfDesired(systemSymbolName: "rectangle.bottomhalf.inset.filled")
        self.menuClose?.setImageIfDesired(systemSymbolName: "xmark")
        self.menuPasteSelection?.setImageIfDesired(systemSymbolName: "doc.on.clipboard.fill")
        self.menuIncreaseFontSize?.setImageIfDesired(systemSymbolName: "textformat.size.larger")
        self.menuResetFontSize?.setImageIfDesired(systemSymbolName: "textformat.size")
        self.menuDecreaseFontSize?.setImageIfDesired(systemSymbolName: "textformat.size.smaller")
        self.menuReadonly?.setImageIfDesired(systemSymbolName: "eye.fill")
        self.menuToggleFullScreen?.setImageIfDesired(systemSymbolName: "square.arrowtriangle.4.outward")
        self.menuToggleVisibility?.setImageIfDesired(systemSymbolName: "eye")
        self.menuZoomSplit?.setImageIfDesired(systemSymbolName: "arrow.up.left.and.arrow.down.right")
        self.menuPreviousSplit?.setImageIfDesired(systemSymbolName: "chevron.backward.2")
        self.menuNextSplit?.setImageIfDesired(systemSymbolName: "chevron.forward.2")
        self.menuEqualizeSplits?.setImageIfDesired(systemSymbolName: "inset.filled.topleft.topright.bottomleft.bottomright.rectangle")
        self.menuSelectSplitLeft?.setImageIfDesired(systemSymbolName: "arrow.left")
        self.menuSelectSplitRight?.setImageIfDesired(systemSymbolName: "arrow.right")
        self.menuSelectSplitAbove?.setImageIfDesired(systemSymbolName: "arrow.up")
        self.menuSelectSplitBelow?.setImageIfDesired(systemSymbolName: "arrow.down")
        self.menuMoveSplitDividerUp?.setImageIfDesired(systemSymbolName: "arrow.up.to.line")
        self.menuMoveSplitDividerDown?.setImageIfDesired(systemSymbolName: "arrow.down.to.line")
        self.menuMoveSplitDividerLeft?.setImageIfDesired(systemSymbolName: "arrow.left.to.line")
        self.menuMoveSplitDividerRight?.setImageIfDesired(systemSymbolName: "arrow.right.to.line")
        self.menuFindParent?.setImageIfDesired(systemSymbolName: "text.page.badge.magnifyingglass")
    }

    /// Sync all of our menu item keyboard shortcuts with the Ghostty configuration.
    @MainActor private func syncMenuShortcuts(_ config: Ghostty.Config) {
        guard ghostty.readiness == .ready else { return }

        menuShortcutManager.reset()

        syncMenuShortcut(config, action: "quit", menuItem: self.menuQuit)

        syncMenuShortcut(config, action: "new_tab", menuItem: self.menuNewTab)
        syncMenuShortcut(config, action: "close_surface", menuItem: self.menuClose)
        syncMenuShortcut(config, action: "close_tab", menuItem: self.menuCloseTab)
        syncMenuShortcut(config, action: "close_window", menuItem: self.menuCloseWindow)
        syncMenuShortcut(config, action: "close_all_windows", menuItem: self.menuCloseAllWindows)
        syncMenuShortcut(config, action: "new_split:right", menuItem: self.menuSplitRight)
        syncMenuShortcut(config, action: "new_split:left", menuItem: self.menuSplitLeft)
        syncMenuShortcut(config, action: "new_split:down", menuItem: self.menuSplitDown)
        syncMenuShortcut(config, action: "new_split:up", menuItem: self.menuSplitUp)

        syncMenuShortcut(config, action: "copy_to_clipboard", menuItem: self.menuCopy)
        syncMenuShortcut(config, action: "paste_from_clipboard", menuItem: self.menuPaste)
        syncMenuShortcut(config, action: "paste_from_selection", menuItem: self.menuPasteSelection)
        syncMenuShortcut(config, action: "select_all", menuItem: self.menuSelectAll)
        syncMenuShortcut(config, action: "start_search", menuItem: self.menuFind)
        syncMenuShortcut(config, action: "end_search", menuItem: self.menuHideFindBar)
        syncMenuShortcut(config, action: "search_selection", menuItem: self.menuSelectionForFind)
        syncMenuShortcut(config, action: "scroll_to_selection", menuItem: self.menuScrollToSelection)
        syncMenuShortcut(config, action: "navigate_search:next", menuItem: self.menuFindNext)
        syncMenuShortcut(config, action: "navigate_search:previous", menuItem: self.menuFindPrevious)

        syncMenuShortcut(config, action: "toggle_split_zoom", menuItem: self.menuZoomSplit)
        syncMenuShortcut(config, action: "goto_split:previous", menuItem: self.menuPreviousSplit)
        syncMenuShortcut(config, action: "goto_split:next", menuItem: self.menuNextSplit)
        syncMenuShortcut(config, action: "goto_split:up", menuItem: self.menuSelectSplitAbove)
        syncMenuShortcut(config, action: "goto_split:down", menuItem: self.menuSelectSplitBelow)
        syncMenuShortcut(config, action: "goto_split:left", menuItem: self.menuSelectSplitLeft)
        syncMenuShortcut(config, action: "goto_split:right", menuItem: self.menuSelectSplitRight)
        syncMenuShortcut(config, action: "resize_split:up,10", menuItem: self.menuMoveSplitDividerUp)
        syncMenuShortcut(config, action: "resize_split:down,10", menuItem: self.menuMoveSplitDividerDown)
        syncMenuShortcut(config, action: "resize_split:right,10", menuItem: self.menuMoveSplitDividerRight)
        syncMenuShortcut(config, action: "resize_split:left,10", menuItem: self.menuMoveSplitDividerLeft)
        syncMenuShortcut(config, action: "equalize_splits", menuItem: self.menuEqualizeSplits)
        syncMenuShortcut(config, action: "reset_window_size", menuItem: self.menuReturnToDefaultSize)

        syncMenuShortcut(config, action: "increase_font_size:1", menuItem: self.menuIncreaseFontSize)
        syncMenuShortcut(config, action: "decrease_font_size:1", menuItem: self.menuDecreaseFontSize)
        syncMenuShortcut(config, action: "reset_font_size", menuItem: self.menuResetFontSize)
        syncMenuShortcut(config, action: "toggle_visibility", menuItem: self.menuToggleVisibility)

        syncMenuShortcut(config, action: "toggle_secure_input", menuItem: self.menuSecureInput)

        // This menu item is NOT synced with the configuration because it disables macOS
        // global fullscreen keyboard shortcut. The shortcut in the Ghostty config will continue
        // to work but it won't be reflected in the menu item.
        //
        // syncMenuShortcut(config, action: "toggle_fullscreen", menuItem: self.menuToggleFullScreen)

        // Dock menu
        reloadDockMenu()
    }

    @MainActor private func syncMenuShortcut(_ config: Ghostty.Config, action: String, menuItem: NSMenuItem?) {
        menuShortcutManager.syncMenuShortcut(config, action: action, menuItem: menuItem)
    }

    @MainActor func performGhosttyBindingMenuKeyEquivalent(with event: NSEvent) -> Bool {
        menuShortcutManager.performGhosttyBindingMenuKeyEquivalent(with: event)
    }
}

// MARK: - Termination Flow

extension AppDelegate {
    func terminate() -> NSApplication.TerminateReply {
        let controllersNeedConfirmation = NSApplication.shared.windows
            .compactMap { $0.windowController as? BaseTerminalController }
            .filter { !$0.windowCanBeClosedWithoutConfirmation() }

        guard !controllersNeedConfirmation.isEmpty else {
            return .terminateNow
        }

        if controllersNeedConfirmation.count == 1 {
            Task {
                let response = await controllersNeedConfirmation[0].confirmCloseAsync(
                    messageText: "Quit Mash Terminal?",
                    informativeText: "The terminal still has a running process. If you quit, the process will be killed.",
                    confirmButtonTitle: "Terminate",
                )

                if [.OK, .alertFirstButtonReturn].contains(response) {
                    await NSApp.reply(toApplicationShouldTerminate: true)
                } else {
                    await NSApp.reply(toApplicationShouldTerminate: false)
                }
            }

            return .terminateLater
        } else {
            let alert = NSAlert.reviewWindowsAlert(
                messageText: "You have \(controllersNeedConfirmation.count) windows with running processes. Do you want to review these windows before quitting?"
            )

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                reviewWindows(controllersNeedConfirmation)
                return .terminateLater
            case .alertSecondButtonReturn:
                return .terminateNow
            default:
                return .terminateCancel
            }
        }
    }

    private func reviewWindows(_ controllers: [BaseTerminalController]) {
        Task {
            for controller in controllers {
                let response = await controller.confirmCloseAsync(
                    messageText: "Quit Mash Terminal?",
                    informativeText: "The terminal still has a running process. If you quit, the process will be killed.",
                    confirmButtonTitle: "Terminate",
                )

                if [.OK, .alertFirstButtonReturn].contains(response) {
                    // Close this window and until next review is cancelled
                    await controller.window?.close()
                    continue
                } else {
                    await NSApp.reply(toApplicationShouldTerminate: false)
                    // Cancel the review
                    return
                }
            }
            await NSApp.reply(toApplicationShouldTerminate: true)
        }
    }
}
