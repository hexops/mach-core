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

const RegistryHandlerUserData = struct {
    interfaces: Interfaces,
    libwaylandclient: LibWaylandClient,
};

const Interfaces = struct {
    wl_compositor: *c.wl_compositor,
    wl_subcompositor: *c.wl_subcompositor,
    wl_shm: *c.wl_shm,
    wl_output: *c.wl_output,
    // TODO
    // wl_seat: *c.wl_seat,
    wl_data_device_manager: *c.wl_data_device_manager,
    xdg_wm_base: *c.xdg_wm_base,
    // zxdg_decoration_manager_v1: *c.zxdg_decoration_manager_v1,
    // wp_viewporter: *c.wp_viewporter,
    // zwp_relative_pointer_manager_v1: *c.zwp_relative_pointer_manager_v1,
    // zwp_pointer_constraints_v1: *c.zwp_pointer_constraints_v1,
    // zwp_idle_inhibit_manager_v1: *c.zwp_idle_inhibit_manager_v1,
    // xdg_activation_v1: *c.xdg_activation_v1,
};

fn registryHandleGlobal(user_data_ptr: ?*anyopaque, registry: ?*c.struct_wl_registry, name: u32, interface_ptr: [*:0]const u8, version: u32) callconv(.C) void {
    const user_data: *RegistryHandlerUserData = @ptrCast(@alignCast(user_data_ptr));
    const interface = std.mem.span(interface_ptr);

    log.debug("Got interface: {s}", .{interface});

    if (std.mem.eql(u8, "wl_compositor", interface)) {
        user_data.interfaces.wl_compositor = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            user_data.libwaylandclient.wl_compositor_interface,
            @min(3, version),
        ) orelse @panic("uh idk how to proceed"));
        log.debug("Bound wl_compositor :)", .{});
    } else if (std.mem.eql(u8, "wl_subcompositor", interface)) {
        user_data.interfaces.wl_subcompositor = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            user_data.libwaylandclient.wl_subcompositor_interface,
            @min(3, version),
        ) orelse @panic("uh idk how to proceed"));
        log.debug("Bound wl_subcompositor :)", .{});
    } else if (std.mem.eql(u8, "wl_shm", interface)) {
        user_data.interfaces.wl_shm = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            user_data.libwaylandclient.wl_shm_interface,
            @min(3, version),
        ) orelse @panic("uh idk how to proceed"));
        log.debug("Bound wl_shm :)", .{});
    } else if (std.mem.eql(u8, "wl_output", interface)) {
        user_data.interfaces.wl_output = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            user_data.libwaylandclient.wl_output_interface,
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
    }
}

fn wmBaseHandlePing(user_data_ptr: ?*anyopaque, wm_base: ?*c.struct_xdg_wm_base, serial: u32) callconv(.C) void {
    const user_data: *RegistryHandlerUserData = @ptrCast(@alignCast(user_data_ptr));
    _ = user_data;

    log.debug("Got wm base {*} with serial {d}", .{ wm_base, serial });
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

fn xdgSurfaceHandleConfigure(user_data: ?*anyopaque, xdg_surface: ?*c.struct_xdg_surface, serial: u32) callconv(.C) void {
    _ = user_data;

    c.xdg_surface_ack_configure(xdg_surface, serial);
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

pub const Core = @This();

libwaylandclient: LibWaylandClient,

display: *c.struct_wl_display,
registry: *c.struct_wl_registry,
interfaces: Interfaces,
surface: *c.struct_wl_surface,
xdg_surface: *c.xdg_surface,
toplevel: *c.xdg_toplevel,
tag: [*]c_char,

// Called on the main thread
pub fn init(
    core: *Core,
    allocator: std.mem.Allocator,
    frame: *Frequency,
    input: *Frequency,
    options: Options,
) !void {
    libwaylandclient = try LibWaylandClient.load();
    _ = allocator;
    _ = frame;
    _ = input;

    const display = libwaylandclient.wl_display_connect(null) orelse return error.FailedToConnectToWaylandDisplay;

    var registry_handler_user_data: RegistryHandlerUserData = .{
        .interfaces = undefined,
        .libwaylandclient = libwaylandclient,
    };

    const registry = c.wl_display_get_registry(display) orelse return error.FailedToGetDisplayRegistry;
    _ = c.wl_registry_add_listener(registry, &registry_listener, &registry_handler_user_data); // TODO: handle error return value here

    //Round trip to get all the registry objects
    _ = libwaylandclient.wl_display_roundtrip(display);

    //Round trip to get all initial output events
    _ = libwaylandclient.wl_display_roundtrip(display);

    const wl_surface = c.wl_compositor_create_surface(registry_handler_user_data.interfaces.wl_compositor) orelse return error.UnableToCreateSurface;
    log.debug("Got surface {*}", .{wl_surface});

    var tag: [*:0]c_char = undefined;
    libwaylandclient.wl_proxy_set_tag(@ptrCast(wl_surface), @ptrCast(&tag));

    const xdg_surface = c.xdg_wm_base_get_xdg_surface(registry_handler_user_data.interfaces.xdg_wm_base, wl_surface) orelse return error.UnableToCreateXdgSurface;
    log.debug("Got xdg surface {*}", .{xdg_surface});

    //TODO: handle this return value
    _ = c.xdg_surface_add_listener(xdg_surface, &.{ .configure = &xdgSurfaceHandleConfigure }, null);

    const toplevel = c.xdg_surface_get_toplevel(xdg_surface) orelse return error.UnableToGetXdgTopLevel;
    log.debug("Got xdg toplevel {*}", .{toplevel});

    //TODO: handle this return value
    _ = c.xdg_toplevel_add_listener(toplevel, &.{
        .configure = &xdgToplevelHandleConfigure,
        .close = &xdgToplevelHandleClose,
    }, null);

    c.xdg_toplevel_set_title(toplevel, options.title);

    const instance = gpu.createInstance(null) orelse {
        log.err("failed to create GPU instance", .{});
        std.process.exit(1);
    };
    const surface = instance.createSurface(&gpu.Surface.Descriptor{
        .next_in_chain = .{
            .from_wayland_surface = &.{
                .display = display,
                .surface = undefined,
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
        .width = undefined,
        .height = undefined,
        .present_mode = .mailbox,
    };
    const swap_chain = gpu_device.createSwapChain(surface, &swap_chain_desc);

    mach_core.adapter = response.adapter.?;
    mach_core.device = gpu_device;
    mach_core.queue = gpu_device.getQueue();
    mach_core.swap_chain = swap_chain;
    mach_core.descriptor = swap_chain_desc;

    core.* = .{
        .libwaylandclient = libwaylandclient,
        .display = display,
        .registry = registry,
        .interfaces = registry_handler_user_data.interfaces,
        .surface = wl_surface,
        .tag = tag,
        .xdg_surface = xdg_surface,
        .toplevel = toplevel,
    };
}

pub fn deinit(self: *Core) void {
    _ = self;
}

// Called on the main thread
pub fn update(_: *Core, _: anytype) !bool {
    @panic("TODO: implement update for X11");
}

// Secondary app-update thread
pub fn appUpdateThread(_: *Core, _: anytype) void {
    @panic("TODO: implement appUpdateThread for X11");
}

// May be called from any thread.
pub inline fn pollEvents(_: *Core) EventIterator {
    @panic("TODO: implement pollEvents for X11");
}

// May be called from any thread.
pub fn setTitle(_: *Core, _: [:0]const u8) void {
    @panic("TODO: implement setTitle for X11");
}

// May be called from any thread.
pub fn setDisplayMode(_: *Core, _: DisplayMode) void {
    @panic("TODO: implement setDisplayMode for X11");
}

// May be called from any thread.
pub fn displayMode(_: *Core) DisplayMode {
    @panic("TODO: implement displayMode for X11");
}

// May be called from any thread.
pub fn setBorder(_: *Core, _: bool) void {
    @panic("TODO: implement setBorder for X11");
}

// May be called from any thread.
pub fn border(_: *Core) bool {
    @panic("TODO: implement border for X11");
}

// May be called from any thread.
pub fn setHeadless(_: *Core, _: bool) void {
    @panic("TODO: implement setHeadless for X11");
}

// May be called from any thread.
pub fn headless(_: *Core) bool {
    @panic("TODO: implement headless for X11");
}

// May be called from any thread.
pub fn setVSync(_: *Core, _: VSyncMode) void {
    @panic("TODO: implement setVSync for X11");
}

// May be called from any thread.
pub fn vsync(_: *Core) VSyncMode {
    @panic("TODO: implement vsync for X11");
}

// May be called from any thread.
pub fn setSize(_: *Core, _: Size) void {
    @panic("TODO: implement setSize for X11");
}

// May be called from any thread.
pub fn size(_: *Core) Size {
    @panic("TODO: implement size for X11");
}

// May be called from any thread.
pub fn setSizeLimit(_: *Core, _: SizeLimit) void {
    @panic("TODO: implement setSizeLimit for X11");
}

// May be called from any thread.
pub fn sizeLimit(_: *Core) SizeLimit {
    @panic("TODO: implement sizeLimit for X11");
}

// May be called from any thread.
pub fn setCursorMode(_: *Core, _: CursorMode) void {
    @panic("TODO: implement setCursorMode for X11");
}

// May be called from any thread.
pub fn cursorMode(_: *Core) CursorMode {
    @panic("TODO: implement cursorMode for X11");
}

// May be called from any thread.
pub fn setCursorShape(_: *Core, _: CursorShape) void {
    @panic("TODO: implement setCursorShape for X11");
}

// May be called from any thread.
pub fn cursorShape(_: *Core) CursorShape {
    @panic("TODO: implement cursorShape for X11");
}

// May be called from any thread.
pub fn joystickPresent(_: *Core, _: Joystick) bool {
    @panic("TODO: implement joystickPresent for X11");
}

// May be called from any thread.
pub fn joystickName(_: *Core, _: Joystick) ?[:0]const u8 {
    @panic("TODO: implement joystickName for X11");
}

// May be called from any thread.
pub fn joystickButtons(_: *Core, _: Joystick) ?[]const bool {
    @panic("TODO: implement joystickButtons for X11");
}

// May be called from any thread.
pub fn joystickAxes(_: *Core, _: Joystick) ?[]const f32 {
    @panic("TODO: implement joystickAxes for X11");
}

// May be called from any thread.
pub fn keyPressed(_: *Core, _: Key) bool {
    @panic("TODO: implement keyPressed for X11");
}

// May be called from any thread.
pub fn keyReleased(_: *Core, _: Key) bool {
    @panic("TODO: implement keyReleased for X11");
}

// May be called from any thread.
pub fn mousePressed(_: *Core, _: MouseButton) bool {
    @panic("TODO: implement mousePressed for X11");
}

// May be called from any thread.
pub fn mouseReleased(_: *Core, _: MouseButton) bool {
    @panic("TODO: implement mouseReleased for X11");
}

// May be called from any thread.
pub fn mousePosition(_: *Core) mach_core.Position {
    @panic("TODO: implement mousePosition for X11");
}

// May be called from any thread.
pub inline fn outOfMemory(_: *Core) bool {
    @panic("TODO: implement outOfMemory for X11");
}

// TODO(important): expose device loss to users, this can happen especially in the web and on mobile
// devices. Users will need to re-upload all assets to the GPU in this event.
fn deviceLostCallback(reason: gpu.Device.LostReason, msg: [*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
    _ = userdata;
    _ = reason;
    log.err("mach: device lost: {s}", .{msg});
    @panic("mach: device lost");
}
