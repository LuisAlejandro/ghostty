//! Wayland protocol implementation for the Ghostty GTK apprt.
const std = @import("std");
const Allocator = std.mem.Allocator;

const gdk = @import("gdk");
const gdk_wayland = @import("gdk_wayland");
const gobject = @import("gobject");
const gtk = @import("gtk");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const ext = wayland.client.ext;
const kde = wayland.client.kde;
const org = wayland.client.org;
const xdg = wayland.client.xdg;

const Config = @import("../../../config.zig").Config;
const Globals = @import("wayland/Globals.zig");
const Hotkeys = @import("wayland/Hotkeys.zig");
const input = @import("../../../input.zig");
const ApprtWindow = @import("../class/window.zig").Window;
const GlobalShortcuts = @import("../class/global_shortcuts.zig").GlobalShortcuts;
const BlurRegion = @import("BlurRegion.zig");
const gtk_version = @import("../gtk_version.zig");

const log = std.log.scoped(.winproto_wayland);

/// Wayland state that contains application-wide Wayland objects (e.g. wl_display).
pub const App = struct {
    display: *wl.Display,
    globals: *Globals,
    hotkeys: Hotkeys,

    pub fn init(
        alloc: Allocator,
        gdk_display: *gdk.Display,
        app_id: [:0]const u8,
        config: *const Config,
    ) !?App {
        _ = config;

        const gdk_wayland_display = gobject.ext.cast(
            gdk_wayland.WaylandDisplay,
            gdk_display,
        ) orelse return null;

        const display: *wl.Display = @ptrCast(@alignCast(
            gdk_wayland_display.getWlDisplay() orelse return error.NoWaylandDisplay,
        ));

        const globals: *Globals = try .init(alloc, display);
        errdefer globals.deinit();

        var hotkeys: Hotkeys = try .init(alloc, app_id);
        errdefer hotkeys.deinit();

        return .{
            .display = display,
            .globals = globals,
            .hotkeys = hotkeys,
        };
    }

    pub fn deinit(self: *App) void {
        self.hotkeys.deinit();
        self.globals.deinit();
    }

    pub fn bindGlobalShortcuts(
        self: *App,
        shortcuts: *GlobalShortcuts,
        config: *const Config,
    ) bool {
        const manager = self.globals.get(.vicinae_hotkey_manager) orelse return false;
        self.hotkeys.bind(manager, shortcuts, config);
        return true;
    }

    pub fn clearGlobalShortcuts(self: *App) void {
        self.hotkeys.clear();
    }

    pub fn eventMods(
        _: *App,
        _: ?*gdk.Device,
        _: gdk.ModifierType,
    ) ?input.Mods {
        return null;
    }

    // Mash ships no quick terminal.
    pub fn supportsQuickTerminal(_: App) bool {
        return false;
    }

    pub fn initQuickTerminal(_: *App, _: *ApprtWindow) !void {}
};

/// Per-window (wl_surface) state for the Wayland protocol.
pub const Window = struct {
    apprt_window: *ApprtWindow,

    /// The Wayland surface for this window.
    surface: *wl.Surface,

    /// The context from the app where we can load our Wayland interfaces.
    globals: *Globals,

    /// Object that controls background effects like background blur.
    bg_effect: ?*ext.BackgroundEffectSurfaceV1 = null,

    /// Object that controls the decoration mode (client/server/auto)
    /// of the window.
    decoration: ?*org.KdeKwinServerDecoration = null,

    /// Object that, when present, denotes that the window is currently
    /// requesting attention from the user.
    activation_token: ?*xdg.ActivationTokenV1 = null,

    blur_region: BlurRegion = .empty,

    pub fn init(
        alloc: Allocator,
        app: *App,
        apprt_window: *ApprtWindow,
    ) !Window {
        _ = alloc;

        const gtk_native = apprt_window.as(gtk.Native);
        const gdk_surface = gtk_native.getSurface() orelse return error.NotWaylandSurface;

        // This should never fail, because if we're being called at this point
        // then we've already asserted that our app state is Wayland.
        const gdk_wl_surface = gobject.ext.cast(
            gdk_wayland.WaylandSurface,
            gdk_surface,
        ) orelse return error.NoWaylandSurface;

        const wl_surface: *wl.Surface = @ptrCast(@alignCast(
            gdk_wl_surface.getWlSurface() orelse return error.NoWaylandSurface,
        ));

        // Get our decoration object so we can control the
        // CSD vs SSD status of this surface.
        const deco: ?*org.KdeKwinServerDecoration = deco: {
            const mgr = app.globals.get(.kde_decoration_manager) orelse
                break :deco null;

            const deco: *org.KdeKwinServerDecoration = mgr.create(
                wl_surface,
            ) catch |err| {
                log.warn("could not create decoration object={}", .{err});
                break :deco null;
            };

            break :deco deco;
        };

        const bg_effect: ?*ext.BackgroundEffectSurfaceV1 = bg: {
            if (gtk_version.runtimeAtLeast(4, 23, 3)) {
                // GTK 4.23.3 added an official way to do background blur,
                // so we don't need to do anything on our own.
                break :bg null;
            }

            const mgr = app.globals.get(.ext_background_effect) orelse
                break :bg null;

            const bg_effect: *ext.BackgroundEffectSurfaceV1 = mgr.getBackgroundEffect(
                wl_surface,
            ) catch |err| {
                log.warn("could not create background effect object={}", .{err});
                break :bg null;
            };

            break :bg bg_effect;
        };

        return .{
            .apprt_window = apprt_window,
            .surface = wl_surface,
            .globals = app.globals,
            .decoration = deco,
            .bg_effect = bg_effect,
        };
    }

    pub fn deinit(self: *Window) void {
        self.blur_region.deinit(self.globals.alloc);
        if (self.bg_effect) |bg| bg.destroy();
        if (self.decoration) |deco| deco.release();
    }

    pub fn resizeEvent(self: *Window) !void {
        self.syncBlur() catch |err| {
            log.err("failed to sync blur={}", .{err});
        };
    }

    pub fn syncAppearance(self: *Window) !void {
        self.syncBlur() catch |err| {
            log.err("failed to sync blur={}", .{err});
        };
        self.syncDecoration() catch |err| {
            log.err("failed to sync decoration={}", .{err});
        };
    }

    pub fn clientSideDecorationEnabled(self: Window) bool {
        return switch (self.getDecorationMode()) {
            .Client => true,
            // If we support SSDs, then we should *not* enable CSDs if we prefer SSDs.
            // However, if we do not support SSDs (e.g. GNOME) then we should enable
            // CSDs even if the user prefers SSDs.
            .Server => if (self.globals.get(.kde_decoration_manager)) |_| false else true,
            .None => false,
            else => unreachable,
        };
    }

    pub fn addSubprocessEnv(self: *Window, env: *std.process.Environ.Map) !void {
        _ = self;
        _ = env;
    }

    pub fn setUrgent(self: *Window, urgent: bool) !void {
        const activation = self.globals.get(.xdg_activation) orelse return;

        // If there already is a token, destroy and unset it
        if (self.activation_token) |token| token.destroy();

        self.activation_token = if (urgent) token: {
            const token = try activation.getActivationToken();
            token.setSurface(self.surface);
            token.setListener(*Window, onActivationTokenEvent, self);
            token.commit();
            break :token token;
        } else null;
    }

    /// Update the blur state of the window.
    fn syncBlur(self: *Window) !void {
        const compositor = self.globals.get(.compositor) orelse return;
        const bg = self.bg_effect orelse return;
        if (!self.globals.state.bg_effect_capabilities.blur) return;

        const config = if (self.apprt_window.getConfig()) |v|
            v.get()
        else
            return;
        const blur = config.@"background-blur";

        if (!blur.enabled()) {
            self.blur_region.deinit(self.globals.alloc);
            bg.setBlurRegion(null);
            return;
        }

        var region: BlurRegion = try .calcForWindow(
            self.globals.alloc,
            self.apprt_window,
            self.clientSideDecorationEnabled(),
            false,
        );
        errdefer region.deinit(self.globals.alloc);

        if (region.eql(self.blur_region)) {
            // Region didn't change. Don't do anything.
            region.deinit(self.globals.alloc);
            return;
        }

        const wl_region = try compositor.createRegion();
        defer wl_region.destroy();
        for (region.slices.items) |s| wl_region.add(
            @intCast(s.x),
            @intCast(s.y),
            @intCast(s.width),
            @intCast(s.height),
        );

        bg.setBlurRegion(wl_region);
        self.blur_region.deinit(self.globals.alloc);
        self.blur_region = region;
    }

    fn syncDecoration(self: *Window) !void {
        const deco = self.decoration orelse return;

        // The protocol requests uint instead of enum so we have
        // to convert it.
        deco.requestMode(@intCast(@intFromEnum(self.getDecorationMode())));
    }

    fn getDecorationMode(self: Window) org.KdeKwinServerDecorationManager.Mode {
        return switch (self.apprt_window.getWindowDecoration()) {
            .auto => self.globals.state.default_deco_mode orelse .Client,
            .client => .Client,
            .server => .Server,
            .none => .None,
        };
    }

    fn onActivationTokenEvent(
        token: *xdg.ActivationTokenV1,
        event: xdg.ActivationTokenV1.Event,
        self: *Window,
    ) void {
        const activation = self.globals.get(.xdg_activation) orelse return;
        const current_token = self.activation_token orelse return;

        if (token.getId() != current_token.getId()) {
            log.warn("received event for unknown activation token; ignoring", .{});
            return;
        }

        switch (event) {
            .done => |done| {
                activation.activate(done.token, self.surface);
                token.destroy();
                self.activation_token = null;
            },
        }
    }
};
