const builtin = @import("builtin");
const std = @import("std");
const gpu = @import("gpu");
const platform = @import("platform.zig");
const Frequency = @import("Frequency.zig");

pub const Core = @This();

/// A buffer which you may use to write the window title to.
title: [256:0]u8,

frame: Frequency,
input: Frequency,
internal: platform.Core,

/// All memory will be copied or returned to the caller once init() finishes.
pub const Options = struct {
    is_app: bool = false,
    headless: bool = false,
    display_mode: DisplayMode = .windowed,
    border: bool = true,
    title: [:0]const u8 = "Mach core",
    size: Size = .{ .width = 1920 / 2, .height = 1080 / 2 },
    power_preference: gpu.PowerPreference = .undefined,
    required_features: ?[]const gpu.FeatureName = null,
    required_limits: ?gpu.Limits = null,
};

pub fn init(core: *Core, allocator: std.mem.Allocator, options: Options) !void {
    // Copy window title into owned buffer.
    var opt = options;
    if (opt.title.len < core.title.len) {
        std.mem.copy(u8, core.title[0..], opt.title);
        core.title[opt.title.len] = 0;
        opt.title = core.title[0..opt.title.len :0];
    }

    core.frame = .{ .target = 0 };
    core.input = .{ .target = 1 };

    try platform.Core.init(
        &core.internal,
        allocator,
        &core.frame,
        &core.input,
        opt,
    );
}

pub fn deinit(core: *Core) void {
    return core.internal.deinit();
}

pub const EventIterator = struct {
    internal: platform.Core.EventIterator,

    pub inline fn next(self: *EventIterator) ?Event {
        return self.internal.next();
    }
};

pub inline fn pollEvents(core: *Core) EventIterator {
    return .{ .internal = core.internal.pollEvents() };
}

/// Sets the window title. The string must be owned by Core, and will not be copied or freed. It is
/// advised to use the Core.title buffer for this purpose, e.g.:
///
/// ```
/// const title = try std.fmt.bufPrintZ(&core.title, "Hello, world!", .{});
/// core.setTitle(title);
/// ```
pub fn setTitle(core: *Core, title: [:0]const u8) void {
    return core.internal.setTitle(title);
}

/// Set the window mode
pub fn setDisplayMode(core: *Core, mode: DisplayMode, monitor: ?usize) void {
    return core.internal.setDisplayMode(mode, monitor);
}

/// Returns the window mode
pub fn displayMode(core: *Core) DisplayMode {
    return core.internal.displayMode();
}

pub fn setBorder(core: *Core, value: bool) void {
    return core.internal.setBorder(value);
}

pub fn border(core: *Core) bool {
    return core.internal.border();
}

pub fn setHeadless(core: *Core, value: bool) void {
    return core.internal.setHeadless(value);
}

pub fn headless(core: *Core) bool {
    return core.internal.headless();
}

pub const VSyncMode = enum {
    /// Potential screen tearing.
    /// No synchronization with monitor, render frames as fast as possible.
    ///
    /// Not available on WASM, fallback to double
    none,

    /// No tearing, synchronizes rendering with monitor refresh rate, rendering frames when ready.
    ///
    /// Tries to stay one frame ahead of the monitor, so when it's ready for the next frame it is
    /// already prepared.
    double,

    /// No tearing, synchronizes rendering with monitor refresh rate, rendering frames when ready.
    ///
    /// Tries to stay two frames ahead of the monitor, so when it's ready for the next frame it is
    /// already prepared.
    ///
    /// Not available on WASM, fallback to double
    triple,
};

/// Set refresh rate synchronization mode. Default `.triple`
pub fn setVSync(core: *Core, mode: VSyncMode) void {
    return core.internal.setVSync(mode);
}

/// Returns refresh rate synchronization mode.
pub fn vsync(core: *Core) VSyncMode {
    return core.internal.vsync();
}

/// Sets the frame rate limit. Default 0 (unlimited)
/// 
/// This is applied *in addition* to the vsync mode.
pub fn setFrameRateLimit(core: *Core, limit: u32) void {
    core.frame.target = limit;
}

/// Returns the frame rate limit, or zero if unlimited.
pub fn frameRateLimit(core: *Core) u32 {
    return core.frame.target;
}

/// Set the window size, in subpixel units.
pub fn setSize(core: *Core, value: Size) void {
    return core.internal.setSize(value);
}

/// Returns the window size, in subpixel units.
pub fn size(core: *Core) Size {
    return core.internal.size();
}

/// Set the minimum and maximum allowed size for the window.
pub fn setSizeLimit(core: *Core, size_limit: SizeLimit) void {
    return core.internal.setSizeLimit(size_limit);
}

/// Returns the minimum and maximum allowed size for the window.
pub fn sizeLimit(core: *Core) SizeLimit {
    return core.internal.sizeLimit();
}

pub fn setCursorMode(core: *Core, mode: CursorMode) void {
    return core.internal.setCursorMode(mode);
}

pub fn cursorMode(core: *Core) CursorMode {
    return core.internal.cursorMode();
}

pub fn setCursorShape(core: *Core, cursor: CursorShape) void {
    return core.internal.setCursorShape(cursor);
}

pub fn cursorShape(core: *Core) CursorShape {
    return core.internal.cursorShape();
}

// TODO(feature): add joystick/gamepad support https://github.com/hexops/mach/issues/884

// /// Checks if the given joystick is still connected.
// pub fn joystickPresent(core: *Core, joystick: Joystick) bool {
//     return core.internal.joystickPresent(joystick);
// }

// /// Retreives the name of the joystick.
// /// Returns `null` if the joystick isnt connected.
// pub fn joystickName(core: *Core, joystick: Joystick) ?[:0]const u8 {
//     return core.internal.joystickName(joystick);
// }

// /// Retrieves the state of the buttons of the given joystick.
// /// A value of `true` indicates the button is pressed, `false` the button is released.
// /// No remapping is done, so the order of these buttons are joystick-dependent and should be
// /// consistent across platforms.
// ///
// /// Returns `null` if the joystick isnt connected.
// ///
// /// Note: For WebAssembly, the remapping is done directly by the web browser, so on that platform
// /// the order of these buttons might be different than on others.
// pub fn joystickButtons(core: *Core, joystick: Joystick) ?[]const bool {
//     return core.internal.joystickButtons(joystick);
// }

// /// Retreives the state of the axes of the given joystick.
// /// The values are always from -1 to 1.
// /// No remapping is done, so the order of these axes are joytstick-dependent and should be
// /// consistent acrsoss platforms.
// ///
// /// Returns `null` if the joystick isnt connected.
// ///
// /// Note: For WebAssembly, the remapping is done directly by the web browser, so on that platform
// /// the order of these axes might be different than on others.
// pub fn joystickAxes(core: *Core, joystick: Joystick) ?[]const f32 {
//     return core.internal.joystickAxes(joystick);
// }

pub fn keyPressed(core: *Core, key: Key) bool {
    return core.internal.keyPressed(key);
}

pub fn keyReleased(core: *Core, key: Key) bool {
    return core.internal.keyReleased(key);
}

pub fn mousePressed(core: *Core, button: MouseButton) bool {
    return core.internal.mousePressed(button);
}

pub fn mouseReleased(core: *Core, button: MouseButton) bool {
    return core.internal.mouseReleased(button);
}

pub fn mousePosition(core: *Core) Position {
    return core.internal.mousePosition();
}

pub fn adapter(core: *Core) *gpu.Adapter {
    return core.internal.adapter();
}

pub fn device(core: *Core) *gpu.Device {
    return core.internal.device();
}

pub fn swapChain(core: *Core) *gpu.SwapChain {
    return core.internal.swapChain();
}

pub fn descriptor(core: *Core) gpu.SwapChain.Descriptor {
    return core.internal.descriptor();
}

/// Whether mach core has run out of memory. If true, freeing memory should restore it to a
/// functional state.
///
/// Once called, future calls will return false until another OOM error occurs.
///
/// Note that if an App.update function returns any error, including errors.OutOfMemory, it will
/// exit the application.
pub fn outOfMemory(core: *Core) bool {
    return core.internal.outOfMemory();
}

/// Sets the minimum target frequency of the input handling thread.
/// 
/// Input handling (the main thread) runs at a variable frequency. The thread blocks until there are
/// input events available, or until it needs to unblock in order to achieve the minimum target
/// frequency which is your collaboration point of opportunity with the main thread.
/// 
/// For example, by default (`setInputFrequency(1)`) mach-core will aim to invoke `updateMainThread`
/// at least once per second (but potentially much more, e.g. once per every mouse movement or
/// keyboard button press.) If you were to increase the input frequency to say 60hz e.g.
/// `setInputFrequency(60)` then mach-core will aim to invoke your `updateMainThread` 60 times per
/// second.
/// 
/// An input frequency of zero implies unlimited, in which case the main thread will busy-wait.
/// 
/// # Multithreaded mach-core behavior
/// 
/// On some platforms, mach-core is able to handle input and rendering independently for
/// improved performance and responsiveness.
/// 
/// | Platform | Threading       |
/// |----------|-----------------|
/// | Desktop  | Multi threaded  |
/// | Browser  | Single threaded |
/// | Mobile   | TBD             |
/// 
/// On single-threaded platforms, `update` and the (optional) `updateMainThread` callback are
/// invoked in sequence, one after the other, on the same thread.
/// 
/// On multi-threaded platforms, `init` and `deinit` are called on the main thread, while `update`
/// is called on a separate rendering thread. The (optional) `updateMainThread` callback can be
/// used in cases where you must run a function on the main OS thread (such as to open a native
/// file dialog on macOS, since many system GUI APIs must be run on the main OS thread.) It is
/// advised you do not use this callback to run any code except when absolutely neccessary, as
/// it is in direct contention with input handling.
/// 
/// It is illegal to use the `core.device()` or `core.swapchain()` from the main thread, and all
/// other APIs are internally synchronized with a mutex for you.
pub fn setInputFrequency(core: *Core, input_frequency: u32) void {
    core.input.target = input_frequency;
}

/// Returns the input frequency, or zero if unlimited (busy-waiting mode)
pub fn inputFrequency(core: *Core) u32 {
    return core.input.target;
}

/// Returns the actual number of frames rendered (`update` calls that returned) in the last second.
/// 
/// This is updated once per second.
pub fn frameRate(core: *Core) u32 {
    return core.frame.rate;
}

/// Returns the actual number of input thread iterations in the last second. See setInputFrequency
/// for what this means.
/// 
/// This is updated once per second.
pub fn inputRate(core: *Core) u32 {
    return core.input.rate;
}

pub const Size = struct {
    width: u32,
    height: u32,
};

pub const SizeOptional = struct {
    width: ?u32 = null,
    height: ?u32 = null,

    pub inline fn equals(a: SizeOptional, b: SizeOptional) bool {
        if ((a.width != null) != (b.width != null)) return false;
        if ((a.height != null) != (b.height != null)) return false;

        if (a.width != null and a.width.? != b.width.?) return false;
        if (a.height != null and a.height.? != b.height.?) return false;
        return true;
    }
};

pub const SizeLimit = struct {
    min: SizeOptional,
    max: SizeOptional,

    pub inline fn equals(a: SizeLimit, b: SizeLimit) bool {
        return a.min.equals(b.min) and a.max.equals(b.max);
    }
};

pub const Position = struct {
    x: f64,
    y: f64,
};

pub const Event = union(enum) {
    key_press: KeyEvent,
    key_repeat: KeyEvent,
    key_release: KeyEvent,
    char_input: struct {
        codepoint: u21,
    },
    mouse_motion: struct {
        pos: Position,
    },
    mouse_press: MouseButtonEvent,
    mouse_release: MouseButtonEvent,
    mouse_scroll: struct {
        xoffset: f32,
        yoffset: f32,
    },
    joystick_connected: Joystick,
    joystick_disconnected: Joystick,
    framebuffer_resize: Size,
    focus_gained,
    focus_lost,
    close,
};

pub const KeyEvent = struct {
    key: Key,
    mods: KeyMods,
};

pub const MouseButtonEvent = struct {
    button: MouseButton,
    pos: Position,
    mods: KeyMods,
};

pub const MouseButton = enum {
    left,
    right,
    middle,
    four,
    five,
    six,
    seven,
    eight,

    pub const max = MouseButton.eight;
};

pub const Key = enum {
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,

    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,

    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    f25,

    kp_divide,
    kp_multiply,
    kp_subtract,
    kp_add,
    kp_0,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_decimal,
    kp_equal,
    kp_enter,

    enter,
    escape,
    tab,
    left_shift,
    right_shift,
    left_control,
    right_control,
    left_alt,
    right_alt,
    left_super,
    right_super,
    menu,
    num_lock,
    caps_lock,
    print,
    scroll_lock,
    pause,
    delete,
    home,
    end,
    page_up,
    page_down,
    insert,
    left,
    right,
    up,
    down,
    backspace,
    space,
    minus,
    equal,
    left_bracket,
    right_bracket,
    backslash,
    semicolon,
    apostrophe,
    comma,
    period,
    slash,
    grave,

    unknown,

    pub const max = Key.unknown;
};

pub const KeyMods = packed struct(u8) {
    shift: bool,
    control: bool,
    alt: bool,
    super: bool,
    caps_lock: bool,
    num_lock: bool,
    _padding: u2 = 0,
};

pub const DisplayMode = enum {
    /// Windowed mode.
    windowed,

    /// Fullscreen mode, using this option may change the display's video mode.
    fullscreen,

    /// Borderless fullscreen window.
    ///
    /// Beware that true .fullscreen is also a hint to the OS that is used in various contexts, e.g.
    ///
    /// * macOS: Moving to a virtual space dedicated to fullscreen windows as the user expects
    /// * macOS: .borderless windows cannot prevent the system menu bar from being displayed
    ///
    /// Always allow users to choose their preferred display mode.
    borderless,
};

pub const CursorMode = enum {
    /// Makes the cursor visible and behaving normally.
    normal,

    /// Makes the cursor invisible when it is over the content area of the window but does not
    /// restrict it from leaving.
    hidden,

    /// Hides and grabs the cursor, providing virtual and unlimited cursor movement. This is useful
    /// for implementing for example 3D camera controls.
    disabled,
};

pub const CursorShape = enum {
    arrow,
    ibeam,
    crosshair,
    pointing_hand,
    resize_ew,
    resize_ns,
    resize_nwse,
    resize_nesw,
    resize_all,
    not_allowed,
};

pub const Joystick = enum(u8) {};
