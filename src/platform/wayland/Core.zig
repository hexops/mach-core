const std = @import("std");
const mach_core = @import("../../main.zig");
const gpu = mach_core.gpu;
const Options = @import("../../main.zig").Options;
const Event = @import("../../main.zig").Event;
const KeyEvent = @import("../../main.zig").KeyEvent;
const MouseButtonEvent = @import("../../main.zig").MouseButtonEvent;
const MouseButton = @import("../../main.zig").MouseButton;
const Size = @import("../../main.zig").Size;
const DisplayMode = @import("../../main.zig").DisplayMode;
const SizeLimit = @import("../../main.zig").SizeLimit;
const CursorShape = @import("../../main.zig").CursorShape;
const VSyncMode = @import("../../main.zig").VSyncMode;
const CursorMode = @import("../../main.zig").CursorMode;
const Key = @import("../../main.zig").Key;
const KeyMods = @import("../../main.zig").KeyMods;
const Joystick = @import("../../main.zig").Joystick;
const InputState = @import("../../InputState.zig");
const Frequency = @import("../../Frequency.zig");
const RequestAdapterResponse = @import("../common.zig").RequestAdapterResponse;
const printUnhandledErrorCallback = @import("../common.zig").printUnhandledErrorCallback;
const detectBackendType = @import("../common.zig").detectBackendType;
const wantGamemode = @import("../common.zig").wantGamemode;
const initLinuxGamemode = @import("../common.zig").initLinuxGamemode;
const deinitLinuxGamemode = @import("../common.zig").deinitLinuxGamemode;
const requestAdapterCallback = @import("../common.zig").requestAdapterCallback;

const log = std.log.scoped(.mach);

pub const c = @cImport({
    @cInclude("wayland-client-protocol.h");
    @cInclude("wayland-xdg-shell-client-protocol.h");
    @cInclude("wayland-xdg-decoration-client-protocol.h");
    @cInclude("wayland-viewporter-client-protocol.h");
    @cInclude("wayland-relative-pointer-unstable-v1-client-protocol.h");
    @cInclude("wayland-pointer-constraints-unstable-v1-client-protocol.h");
    @cInclude("wayland-idle-inhibit-unstable-v1-client-protocol.h");
});

var libwaylandclient: LibWaylandClient = undefined;

export fn wl_proxy_add_listener(proxy: ?*c.struct_wl_proxy, implementation: [*c]?*const fn () callconv(.C) void, data: ?*anyopaque) c_int {
    return @call(.always_tail, libwaylandclient.wl_proxy_add_listener, .{ proxy, implementation, data });
}

export fn wl_proxy_get_version(proxy: ?*c.struct_wl_proxy) u32 {
    return @call(.always_tail, libwaylandclient.wl_proxy_get_version, .{proxy});
}

export fn wl_proxy_marshal_flags(proxy: ?*c.struct_wl_proxy, opcode: u32, interface: [*c]const c.struct_wl_interface, version: u32, flags: u32, ...) ?*c.struct_wl_proxy {
    var arg_list: std.builtin.VaList = @cVaStart();
    defer @cVaEnd(&arg_list);

    return @call(.always_tail, libwaylandclient.wl_proxy_marshal_flags, .{ proxy, opcode, interface, version, flags, arg_list });
}

const LibWaylandClient = struct {
    handle: std.DynLib,

    wl_display_connect: *const @TypeOf(c.wl_display_connect),
    wl_proxy_add_listener: *const @TypeOf(c.wl_proxy_add_listener),
    wl_proxy_get_version: *const @TypeOf(c.wl_proxy_get_version),
    wl_proxy_marshal_flags: *const @TypeOf(c.wl_proxy_marshal_flags),
    wl_proxy_set_tag: *const @TypeOf(c.wl_proxy_set_tag),
    wl_display_roundtrip: *const @TypeOf(c.wl_display_roundtrip),
    wl_display_dispatch: *const @TypeOf(c.wl_display_dispatch),
    wl_display_flush: *const @TypeOf(c.wl_display_flush),
    wl_display_get_fd: *const @TypeOf(c.wl_display_get_fd),

    //Interfaces
    wl_compositor_interface: *@TypeOf(c.wl_compositor_interface),
    wl_subcompositor_interface: *@TypeOf(c.wl_subcompositor_interface),
    wl_shm_interface: *@TypeOf(c.wl_subcompositor_interface),
    wl_data_device_manager_interface: *@TypeOf(c.wl_data_device_manager_interface),

    wl_buffer_interface: *@TypeOf(c.wl_buffer_interface),
    wl_callback_interface: *@TypeOf(c.wl_callback_interface),
    wl_data_device_interface: *@TypeOf(c.wl_data_device_interface),
    wl_data_offer_interface: *@TypeOf(c.wl_data_offer_interface),
    wl_data_source_interface: *@TypeOf(c.wl_data_source_interface),
    wl_keyboard_interface: *@TypeOf(c.wl_keyboard_interface),
    wl_output_interface: *@TypeOf(c.wl_output_interface),
    wl_pointer_interface: *@TypeOf(c.wl_pointer_interface),
    wl_region_interface: *@TypeOf(c.wl_region_interface),
    wl_registry_interface: *@TypeOf(c.wl_registry_interface),
    wl_seat_interface: *@TypeOf(c.wl_seat_interface),
    wl_shell_surface_interface: *@TypeOf(c.wl_shell_surface_interface),
    wl_shm_pool_interface: *@TypeOf(c.wl_shm_pool_interface),
    wl_subsurface_interface: *@TypeOf(c.wl_subsurface_interface),
    wl_surface_interface: *@TypeOf(c.wl_surface_interface),
    wl_touch_interface: *@TypeOf(c.wl_touch_interface),

    pub extern const xdg_wm_base_interface: @TypeOf(c.xdg_wm_base_interface);
    pub extern const zxdg_decoration_manager_v1_interface: @TypeOf(c.zxdg_decoration_manager_v1_interface);

    pub fn load() !LibWaylandClient {
        var lib: LibWaylandClient = undefined;
        lib.handle = std.DynLib.openZ("libwayland-client.so.0") catch return error.LibraryNotFound;
        inline for (@typeInfo(LibWaylandClient).Struct.fields[1..]) |field| {
            const name = std.fmt.comptimePrint("{s}\x00", .{field.name});
            const name_z: [:0]const u8 = @ptrCast(name[0 .. name.len - 1]);
            @field(lib, field.name) = lib.handle.lookup(field.type, name_z) orelse {
                log.err("Symbol lookup failed for {s}", .{name});
                return error.SymbolLookup;
            };
        }
        return lib;
    }
};

const EventQueue = std.fifo.LinearFifo(Event, .Dynamic);

pub const EventIterator = struct {
    events_mu: *std.Thread.RwLock,
    queue: *EventQueue,

    pub inline fn next(self: *EventIterator) ?Event {
        self.events_mu.lockShared();
        defer self.events_mu.unlockShared();
        return self.queue.readItem();
    }
};

const Interfaces = struct {
    wl_compositor: ?*c.wl_compositor = null,
    wl_subcompositor: ?*c.wl_subcompositor = null,
    wl_shm: ?*c.wl_shm = null,
    wl_output: ?*c.wl_output = null,
    // TODO
    // wl_seat: *c.wl_seat,
    wl_data_device_manager: ?*c.wl_data_device_manager = null,
    xdg_wm_base: ?*c.xdg_wm_base = null,
    zxdg_decoration_manager_v1: ?*c.zxdg_decoration_manager_v1 = null,
    // wp_viewporter: *c.wp_viewporter,
    // zwp_relative_pointer_manager_v1: *c.zwp_relative_pointer_manager_v1,
    // zwp_pointer_constraints_v1: *c.zwp_pointer_constraints_v1,
    // zwp_idle_inhibit_manager_v1: *c.zwp_idle_inhibit_manager_v1,
    // xdg_activation_v1: *c.xdg_activation_v1,
};

fn registryHandleGlobal(user_data_ptr: ?*anyopaque, registry: ?*c.struct_wl_registry, name: u32, interface_ptr: [*:0]const u8, version: u32) callconv(.C) void {
    const user_data: *Core = @ptrCast(@alignCast(user_data_ptr));
    const interface = std.mem.span(interface_ptr);

    log.debug("Got interface: {s}", .{interface});

    if (std.mem.eql(u8, "wl_compositor", interface)) {
        user_data.interfaces.wl_compositor = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            libwaylandclient.wl_compositor_interface,
            @min(3, version),
        ) orelse @panic("uh idk how to proceed"));
        log.debug("Bound wl_compositor :)", .{});
    } else if (std.mem.eql(u8, "wl_subcompositor", interface)) {
        user_data.interfaces.wl_subcompositor = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            libwaylandclient.wl_subcompositor_interface,
            @min(3, version),
        ) orelse @panic("uh idk how to proceed"));
        log.debug("Bound wl_subcompositor :)", .{});
    } else if (std.mem.eql(u8, "wl_shm", interface)) {
        user_data.interfaces.wl_shm = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            libwaylandclient.wl_shm_interface,
            @min(3, version),
        ) orelse @panic("uh idk how to proceed"));
        log.debug("Bound wl_shm :)", .{});
    } else if (std.mem.eql(u8, "wl_output", interface)) {
        user_data.interfaces.wl_output = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            libwaylandclient.wl_output_interface,
            @min(3, version),
        ) orelse @panic("uh idk how to proceed"));
        log.debug("Bound wl_output :)", .{});
        // } else if (std.mem.eql(u8, "wl_data_device_manager", interface)) {
        //     user_data.interfaces.wl_data_device_manager = @ptrCast(user_data.libwaylandclient.wl_registry_bind(
        //         registry,
        //         name,
        //         user_data.libwaylandclient.wl_data_device_manager_interface,
        //         @min(3, version),
        //     ) orelse @panic("uh idk how to proceed"));
        //     log.debug("Bound wl_data_device_manager :)", .{});
    } else if (std.mem.eql(u8, "xdg_wm_base", interface)) {
        user_data.interfaces.xdg_wm_base = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &LibWaylandClient.xdg_wm_base_interface,
            // &LibWaylandClient._glfw_xdg_wm_base_interface,
            @min(3, version),
        ) orelse @panic("uh idk how to proceed"));
        log.debug("Bound xdg_wm_base :)", .{});

        //TODO: handle return value
        _ = c.xdg_wm_base_add_listener(user_data.interfaces.xdg_wm_base, &.{ .ping = &wmBaseHandlePing }, user_data);
    } else if (std.mem.eql(u8, "zxdg_decoration_manager_v1", interface)) {
        user_data.interfaces.zxdg_decoration_manager_v1 = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &LibWaylandClient.zxdg_decoration_manager_v1_interface,
            @min(3, version),
        ) orelse @panic("uh idk how to proceed"));
        log.debug("Bound zxdg_decoration_manager_v1 :)", .{});
    }
}

fn wmBaseHandlePing(user_data_ptr: ?*anyopaque, wm_base: ?*c.struct_xdg_wm_base, serial: u32) callconv(.C) void {
    const user_data: *Core = @ptrCast(@alignCast(user_data_ptr));
    _ = user_data;

    log.debug("Got wm base {*} with serial {d}", .{ wm_base, serial });

    c.xdg_wm_base_pong(wm_base, serial);
}

fn registryHandleGlobalRemove(user_data: ?*anyopaque, registry: ?*c.struct_wl_registry, name: u32) callconv(.C) void {
    _ = user_data;
    _ = registry;
    _ = name;
}

const registry_listener = c.wl_registry_listener{
    // ptrcast is for the [*:0] -> [*c] conversion, silly yes
    .global = @ptrCast(&registryHandleGlobal),
    .global_remove = &registryHandleGlobalRemove,
};

fn xdgSurfaceHandleConfigure(user_data_ptr: ?*anyopaque, xdg_surface: ?*c.struct_xdg_surface, serial: u32) callconv(.C) void {
    const core: *Core = @ptrCast(@alignCast(user_data_ptr.?));

    c.xdg_surface_ack_configure(xdg_surface, serial);
    if (core.configured) {
        c.wl_surface_commit(core.surface);
    } else {
        log.debug("xdg surface configured", .{});
        core.configured = true;
    }
}

fn xdgToplevelHandleClose(user_data: ?*anyopaque, toplevel: ?*c.struct_xdg_toplevel) callconv(.C) void {
    _ = user_data;
    _ = toplevel;
}

fn xdgToplevelHandleConfigure(user_data: ?*anyopaque, toplevel: ?*c.struct_xdg_toplevel, width: i32, height: i32, states: [*c]c.struct_wl_array) callconv(.C) void {
    _ = user_data;
    _ = toplevel;
    _ = width;
    _ = height;
    _ = states;
}

fn Changable(comptime T: type, comptime uses_allocator: bool) type {
    return struct {
        current: T,
        last: if (uses_allocator) ?T else void,
        allocator: if (uses_allocator) std.mem.Allocator else void,
        changed: bool = false,

        const Self = @This();

        ///Initialize with a default value
        pub fn init(value: T, allocator: if (uses_allocator) std.mem.Allocator else void) !Self {
            if (uses_allocator) {
                return .{
                    .allocator = allocator,
                    .last = null,
                    .current = try allocator.dupeZ(std.meta.Child(T), value),
                };
            } else {
                return .{
                    .allocator = {},
                    .last = {},
                    .current = value,
                };
            }
        }

        /// Set a new value for the changable
        pub fn set(self: *Self, value: T) !void {
            if (uses_allocator) {
                //If we have a last value, free it
                if (self.last) |last_value| {
                    self.allocator.free(last_value);

                    self.last = null;
                }

                self.last = self.current;

                self.current = try self.allocator.dupeZ(std.meta.Child(T), value);
            } else {
                self.current = value;
            }
            self.changed = true;
        }

        /// Read the current value out, resetting the changed flag
        pub fn read(self: *Self) ?T {
            if (!self.changed)
                return null;

            self.changed = false;
            return self.current;
        }

        /// Free's the last allocation and resets the `last` value
        pub fn freeLast(self: *Self) void {
            if (uses_allocator) {
                if (self.last) |last_value| {
                    self.allocator.free(last_value);
                }

                self.last = null;
            }
        }

        pub fn deinit(self: *Self) void {
            if (uses_allocator) {
                if (self.last) |last_value| {
                    self.allocator.free(last_value);
                }

                self.allocator.free(self.current);
            }

            self.* = undefined;
        }
    };
}

pub const Core = @This();

display: *c.struct_wl_display,
registry: *c.struct_wl_registry,
interfaces: Interfaces,
surface: *c.struct_wl_surface,
xdg_surface: *c.xdg_surface,
toplevel: *c.xdg_toplevel,
tag: [*]c_char,
decoration: *c.zxdg_toplevel_decoration_v1,
configured: bool,

app_update_thread_started: bool = false,

gpu_device: *gpu.Device,

// Event queue; written from main thread; read from any
events_mu: std.Thread.RwLock = .{},
events: EventQueue,

// changables
state_mu: std.Thread.RwLock = .{},
title: Changable([:0]const u8, true),
window_size: Changable(Size, false),

// Called on the main thread
pub fn init(
    core: *Core,
    allocator: std.mem.Allocator,
    frame: *Frequency,
    input: *Frequency,
    options: Options,
) !void {
    //Init `configured` so that its defined
    core.configured = false;
    core.interfaces = .{};

    libwaylandclient = try LibWaylandClient.load();
    _ = frame;
    _ = input;

    core.display = libwaylandclient.wl_display_connect(null) orelse return error.FailedToConnectToWaylandDisplay;

    const registry = c.wl_display_get_registry(core.display) orelse return error.FailedToGetDisplayRegistry;
    // TODO: handle error return value here
    _ = c.wl_registry_add_listener(registry, &registry_listener, core);

    //Round trip to get all the registry objects
    _ = libwaylandclient.wl_display_roundtrip(core.display);

    //Round trip to get all initial output events
    _ = libwaylandclient.wl_display_roundtrip(core.display);

    core.surface = c.wl_compositor_create_surface(core.interfaces.wl_compositor) orelse return error.UnableToCreateSurface;
    log.debug("Got surface {*}", .{core.surface});

    var tag: [*:0]c_char = undefined;
    libwaylandclient.wl_proxy_set_tag(@ptrCast(core.surface), @ptrCast(&tag));

    {
        const region = c.wl_compositor_create_region(core.interfaces.wl_compositor) orelse return error.CouldntCreateWaylandRegtion;

        core.window_size = try @TypeOf(core.window_size).init(options.size, {});

        c.wl_region_add(
            region,
            0,
            0,
            @intCast(core.window_size.current.width),
            @intCast(core.window_size.current.height),
        );
        c.wl_surface_set_opaque_region(core.surface, region);
        c.wl_region_destroy(region);
    }

    const xdg_surface = c.xdg_wm_base_get_xdg_surface(core.interfaces.xdg_wm_base, core.surface) orelse return error.UnableToCreateXdgSurface;
    log.debug("Got xdg surface {*}", .{xdg_surface});

    const toplevel = c.xdg_surface_get_toplevel(xdg_surface) orelse return error.UnableToGetXdgTopLevel;
    log.debug("Got xdg toplevel {*}", .{toplevel});

    //TODO: handle this return value
    _ = c.xdg_surface_add_listener(xdg_surface, &.{ .configure = &xdgSurfaceHandleConfigure }, core);

    //TODO: handle this return value
    _ = c.xdg_toplevel_add_listener(toplevel, &.{
        .configure = &xdgToplevelHandleConfigure,
        .close = &xdgToplevelHandleClose,
    }, null);

    //Commit changes to surface
    c.wl_surface_commit(core.surface);

    while (libwaylandclient.wl_display_dispatch(core.display) != -1 and !core.configured) {
        // This space intentionally left blank
    }

    core.title = try @TypeOf(core.title).init(options.title, allocator);

    c.xdg_toplevel_set_title(toplevel, core.title.current);

    const decoration = c.zxdg_decoration_manager_v1_get_toplevel_decoration(
        core.interfaces.zxdg_decoration_manager_v1,
        toplevel,
    ) orelse return error.UnableToGetToplevelDecoration;
    log.debug("Got xdg toplevel decoration {*}", .{decoration});

    c.zxdg_toplevel_decoration_v1_set_mode(
        decoration,
        c.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE,
    );

    //Commit changes to surface
    c.wl_surface_commit(core.surface);
    //TODO: handle return value
    _ = libwaylandclient.wl_display_roundtrip(core.display);

    const instance = gpu.createInstance(null) orelse {
        log.err("failed to create GPU instance", .{});
        std.process.exit(1);
    };
    const surface = instance.createSurface(&gpu.Surface.Descriptor{
        .next_in_chain = .{
            .from_wayland_surface = &.{
                .display = core.display,
                .surface = core.surface,
            },
        },
    });

    var response: RequestAdapterResponse = undefined;
    instance.requestAdapter(&gpu.RequestAdapterOptions{
        .compatible_surface = surface,
        .power_preference = options.power_preference,
        .force_fallback_adapter = .false,
    }, &response, requestAdapterCallback);
    if (response.status != .success) {
        log.err("failed to create GPU adapter: {?s}", .{response.message});
        log.info("-> maybe try MACH_GPU_BACKEND=opengl ?", .{});
        std.process.exit(1);
    }

    // Print which adapter we are going to use.
    var props = std.mem.zeroes(gpu.Adapter.Properties);
    response.adapter.?.getProperties(&props);
    if (props.backend_type == .null) {
        log.err("no backend found for {s} adapter", .{props.adapter_type.name()});
        std.process.exit(1);
    }
    log.info("found {s} backend on {s} adapter: {s}, {s}\n", .{
        props.backend_type.name(),
        props.adapter_type.name(),
        props.name,
        props.driver_description,
    });

    // Create a device with default limits/features.
    const gpu_device = response.adapter.?.createDevice(&.{
        .next_in_chain = .{
            .dawn_toggles_descriptor = &gpu.dawn.TogglesDescriptor.init(.{
                .enabled_toggles = &[_][*:0]const u8{
                    "allow_unsafe_apis",
                },
            }),
        },

        .required_features_count = if (options.required_features) |v| @as(u32, @intCast(v.len)) else 0,
        .required_features = if (options.required_features) |v| @as(?[*]const gpu.FeatureName, v.ptr) else null,
        .required_limits = if (options.required_limits) |limits| @as(?*const gpu.RequiredLimits, &gpu.RequiredLimits{
            .limits = limits,
        }) else null,
        .device_lost_callback = &deviceLostCallback,
        .device_lost_userdata = null,
    }) orelse {
        log.err("failed to create GPU device\n", .{});
        std.process.exit(1);
    };
    gpu_device.setUncapturedErrorCallback({}, printUnhandledErrorCallback);

    const swap_chain_desc = gpu.SwapChain.Descriptor{
        .label = "main swap chain",
        .usage = .{ .render_attachment = true },
        .format = .bgra8_unorm,
        .width = options.size.width,
        .height = options.size.height,
        .present_mode = .mailbox,
    };
    const swap_chain = gpu_device.createSwapChain(surface, &swap_chain_desc);

    mach_core.adapter = response.adapter.?;
    mach_core.device = gpu_device;
    mach_core.queue = gpu_device.getQueue();
    mach_core.swap_chain = swap_chain;
    mach_core.descriptor = swap_chain_desc;

    log.debug("DONE", .{});

    core.* = .{
        .display = core.display,
        .registry = registry,
        .interfaces = core.interfaces,
        .surface = core.surface,
        .tag = tag,
        .xdg_surface = xdg_surface,
        .toplevel = toplevel,
        .decoration = decoration,
        .configured = core.configured,
        .gpu_device = gpu_device,
        .events = EventQueue.init(allocator),
        .title = core.title,
        .window_size = core.window_size,
    };
}

pub fn deinit(self: *Core) void {
    _ = self;
}

// Called on the main thread
pub fn update(self: *Core, app: anytype) !bool {
    if (!self.app_update_thread_started) {
        self.app_update_thread_started = true;
        const thread = try std.Thread.spawn(.{}, appUpdateThread, .{ self, app });
        thread.detach();
    }

    //State updates
    {
        self.state_mu.lock();
        defer self.state_mu.unlock();

        // Check if we have a new title
        if (self.title.read()) |new_title| {
            defer self.title.freeLast();

            c.xdg_toplevel_set_title(self.toplevel, new_title);
        }
    }

    while (libwaylandclient.wl_display_flush(self.display) == -1) {
        // if (std.os.errno() == std.os.E.AGAIN) {
        // log.err("flush error", .{});
        // return true;
        // }

        var pollfd = [_]std.os.pollfd{
            std.os.pollfd{
                .fd = libwaylandclient.wl_display_get_fd(self.display),
                .events = std.os.POLL.OUT,
                .revents = 0,
            },
        };

        while (try std.os.poll(&pollfd, -1) != 0) {
            // if (std.os.errno() == std.os.E.INTR or std.os.errno() == std.os.E.AGAIN) {
            // log.err("poll error", .{});
            // return true;
            // }
        }
    }

    if (@hasDecl(std.meta.Child(@TypeOf(app)), "updateMainThread")) {
        if (app.updateMainThread() catch unreachable) {
            // self.done.set();
            return true;
        }
    }

    _ = libwaylandclient.wl_display_roundtrip(self.display);

    return false;
}

// Secondary app-update thread
pub fn appUpdateThread(self: *Core, app: anytype) void {
    // @panic("TODO: implement appUpdateThread for Wayland");

    // self.frame.start() catch unreachable;
    while (true) {
        // if (self.swap_chain_update.isSet()) blk: {
        //     self.swap_chain_update.reset();

        //     if (self.current_vsync_mode != self.last_vsync_mode) {
        //         self.last_vsync_mode = self.current_vsync_mode;
        //         switch (self.current_vsync_mode) {
        //             .triple => self.frame.target = 2 * self.refresh_rate,
        //             else => self.frame.target = 0,
        //         }
        //     }

        //     if (self.current_size.width == 0 or self.current_size.height == 0) break :blk;

        //     self.swap_chain_mu.lock();
        //     defer self.swap_chain_mu.unlock();
        //     mach_core.swap_chain.release();
        //     self.swap_chain_desc.width = self.current_size.width;
        //     self.swap_chain_desc.height = self.current_size.height;
        //     self.swap_chain = self.gpu_device.createSwapChain(self.surface, &self.swap_chain_desc);

        //     mach_core.swap_chain = self.swap_chain;
        //     mach_core.descriptor = self.swap_chain_desc;

        //     self.pushEvent(.{
        //         .framebuffer_resize = .{
        //             .width = self.current_size.width,
        //             .height = self.current_size.height,
        //         },
        //     });
        // }

        if (app.update() catch unreachable) {
            // self.done.set();

            // Wake the main thread from any event handling, so there is not e.g. a one second delay
            // in exiting the application.
            // self.wakeMainThread();
            @panic("TODO");
            // return;
        }
        self.gpu_device.tick();
        self.gpu_device.machWaitForCommandsToBeScheduled();

        // self.frame.tick();
        // if (self.frame.delay_ns != 0) std.time.sleep(self.frame.delay_ns);
    }
}

// May be called from any thread.
pub inline fn pollEvents(self: *Core) EventIterator {
    // @panic("TODO: implement pollEvents for Wayland");
    return EventIterator{ .events_mu = &self.events_mu, .queue = &self.events };
}

// May be called from any thread.
pub fn setTitle(self: *Core, title: [:0]const u8) void {
    self.state_mu.lock();
    defer self.state_mu.unlock();

    self.title.set(title) catch unreachable;
}

// May be called from any thread.
pub fn setDisplayMode(_: *Core, _: DisplayMode) void {
    @panic("TODO: implement setDisplayMode for Wayland");
}

// May be called from any thread.
pub fn displayMode(_: *Core) DisplayMode {
    @panic("TODO: implement displayMode for Wayland");
}

// May be called from any thread.
pub fn setBorder(_: *Core, _: bool) void {
    @panic("TODO: implement setBorder for Wayland");
}

// May be called from any thread.
pub fn border(_: *Core) bool {
    @panic("TODO: implement border for Wayland");
}

// May be called from any thread.
pub fn setHeadless(_: *Core, _: bool) void {
    @panic("TODO: implement setHeadless for Wayland");
}

// May be called from any thread.
pub fn headless(_: *Core) bool {
    @panic("TODO: implement headless for Wayland");
}

// May be called from any thread.
pub fn setVSync(_: *Core, _: VSyncMode) void {
    @panic("TODO: implement setVSync for Wayland");
}

// May be called from any thread.
pub fn vsync(_: *Core) VSyncMode {
    @panic("TODO: implement vsync for Wayland");
}

// May be called from any thread.
pub fn setSize(_: *Core, _: Size) void {
    @panic("TODO: implement setSize for Wayland");
}

// May be called from any thread.
pub fn size(self: *Core) Size {
    self.state_mu.lock();
    defer self.state_mu.unlock();

    return self.window_size.current;
}

// May be called from any thread.
pub fn setSizeLimit(_: *Core, _: SizeLimit) void {
    @panic("TODO: implement setSizeLimit for Wayland");
}

// May be called from any thread.
pub fn sizeLimit(_: *Core) SizeLimit {
    @panic("TODO: implement sizeLimit for Wayland");
}

// May be called from any thread.
pub fn setCursorMode(_: *Core, _: CursorMode) void {
    @panic("TODO: implement setCursorMode for Wayland");
}

// May be called from any thread.
pub fn cursorMode(_: *Core) CursorMode {
    @panic("TODO: implement cursorMode for Wayland");
}

// May be called from any thread.
pub fn setCursorShape(_: *Core, _: CursorShape) void {
    @panic("TODO: implement setCursorShape for Wayland");
}

// May be called from any thread.
pub fn cursorShape(_: *Core) CursorShape {
    @panic("TODO: implement cursorShape for Wayland");
}

// May be called from any thread.
pub fn joystickPresent(_: *Core, _: Joystick) bool {
    @panic("TODO: implement joystickPresent for Wayland");
}

// May be called from any thread.
pub fn joystickName(_: *Core, _: Joystick) ?[:0]const u8 {
    @panic("TODO: implement joystickName for Wayland");
}

// May be called from any thread.
pub fn joystickButtons(_: *Core, _: Joystick) ?[]const bool {
    @panic("TODO: implement joystickButtons for Wayland");
}

// May be called from any thread.
pub fn joystickAxes(_: *Core, _: Joystick) ?[]const f32 {
    @panic("TODO: implement joystickAxes for Wayland");
}

// May be called from any thread.
pub fn keyPressed(_: *Core, _: Key) bool {
    @panic("TODO: implement keyPressed for Wayland");
}

// May be called from any thread.
pub fn keyReleased(_: *Core, _: Key) bool {
    @panic("TODO: implement keyReleased for Wayland");
}

// May be called from any thread.
pub fn mousePressed(_: *Core, _: MouseButton) bool {
    @panic("TODO: implement mousePressed for Wayland");
}

// May be called from any thread.
pub fn mouseReleased(_: *Core, _: MouseButton) bool {
    @panic("TODO: implement mouseReleased for Wayland");
}

// May be called from any thread.
pub fn mousePosition(_: *Core) mach_core.Position {
    @panic("TODO: implement mousePosition for Wayland");
}

// May be called from any thread.
pub inline fn outOfMemory(_: *Core) bool {
    @panic("TODO: implement outOfMemory for Wayland");
}

// TODO(important): expose device loss to users, this can happen especially in the web and on mobile
// devices. Users will need to re-upload all assets to the GPU in this event.
fn deviceLostCallback(reason: gpu.Device.LostReason, msg: [*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
    _ = userdata;
    _ = reason;
    log.err("mach: device lost: {s}", .{msg});
    @panic("mach: device lost");
}
