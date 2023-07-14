const std = @import("std");
const gpu = @import("gpu");
const js = @import("js.zig");
const Timer = @import("Timer.zig");
const Options = @import("../../Core.zig").Options;
const Event = @import("../../Core.zig").Event;
const KeyEvent = @import("../../Core.zig").KeyEvent;
const MouseButtonEvent = @import("../../Core.zig").MouseButtonEvent;
const MouseButton = @import("../../Core.zig").MouseButton;
const Size = @import("../../Core.zig").Size;
const Position = @import("../../Core.zig").Position;
const DisplayMode = @import("../../Core.zig").DisplayMode;
const SizeLimit = @import("../../Core.zig").SizeLimit;
const CursorShape = @import("../../Core.zig").CursorShape;
const VSyncMode = @import("../../Core.zig").VSyncMode;
const CursorMode = @import("../../Core.zig").CursorMode;
const Key = @import("../../Core.zig").Key;
const KeyMods = @import("../../Core.zig").KeyMods;
const Joystick = @import("../../Core.zig").Joystick;
const InputState = @import("../../InputState.zig");

pub const Core = @This();

allocator: std.mem.Allocator,
id: js.CanvasId,

input_state: InputState,
joysticks: [JoystickData.max_joysticks]JoystickData,

pub const EventIterator = struct {
    core: *Core,

    pub inline fn next(self: *EventIterator) ?Event {
        while (true) {
            const event_int = js.machEventShift();
            if (event_int == -1) return null;

            const event_type = @as(std.meta.Tag(Event), @enumFromInt(event_int));
            return switch (event_type) {
                .key_press, .key_repeat, .key_release => blk: {
                    const key = @as(Key, @enumFromInt(js.machEventShift()));

                    switch (event_type) {
                        .key_press => {
                            self.core.input_state.keys.set(@intFromEnum(key));
                            break :blk Event {
                                .key_press = .{
                                    .key = key,
                                    .mods = self.makeKeyMods(),
                                },
                            };
                        },
                        .key_repeat => break :blk Event{
                            .key_repeat = .{
                                .key = key,
                                .mods = self.makeKeyMods(),
                            },
                        },
                        .key_release => {
                            self.core.input_state.keys.unset(@intFromEnum(key));
                            break :blk Event{
                                .key_release = .{
                                    .key = key,
                                    .mods = self.makeKeyMods(),
                                },
                            };
                        },
                        else => unreachable,
                    }

                    continue;
                },
                .mouse_motion => blk: {
                    const x = @as(f64, @floatFromInt(js.machEventShift()));
                    const y = @as(f64, @floatFromInt(js.machEventShift()));

                    self.core.input_state.mouse_position = .{ .x = x, .y = y };

                    break :blk Event{
                        .mouse_motion = .{
                            .pos = .{
                                .x = x,
                                .y = y,
                            },
                        },
                    };
                },
                .mouse_press => blk: {
                    const button = toMachButton(js.machEventShift());
                    self.core.input_state.mouse_buttons.set(@intFromEnum(button));

                    break :blk Event{
                        .mouse_press = .{
                            .button = button,
                            .pos = self.core.input_state.mouse_position,
                            .mods = self.makeKeyMods(),
                        },
                    };
                },
                .mouse_release => blk: {
                    const button = toMachButton(js.machEventShift());
                    self.core.input_state.mouse_buttons.unset(@intFromEnum(button));

                    break :blk Event{
                        .mouse_release = .{
                            .button = button,
                            .pos = self.core.input_state.mouse_position,
                            .mods = self.makeKeyMods(),
                        },
                    };
                },
                .mouse_scroll => Event{
                    .mouse_scroll = .{
                        .xoffset = @as(f32, @floatCast(std.math.sign(js.machEventShiftFloat()))),
                        .yoffset = @as(f32, @floatCast(std.math.sign(js.machEventShiftFloat()))),
                    },
                },
                .joystick_connected => blk: {
                    const idx: u8 = @intCast(js.machEventShift());
                    const btn_count: usize = @intCast(js.machEventShift());
                    const axis_count: usize = @intCast(js.machEventShift());

                    if( idx >= JoystickData.max_joysticks )
                        continue;
                    
                    var data = &self.core.joysticks[idx];
                    data.present = true;
                    data.button_count = @min(JoystickData.max_button_count, btn_count);
                    data.axis_count = @min(JoystickData.max_axis_count, axis_count);

                    js.machJoystickName(idx, &data.name, JoystickData.max_name_len);

                    break :blk Event {
                        .joystick_connected = @enumFromInt(idx),
                    };
                },
                .joystick_disconnected => blk: {
                    const idx: u8 = @intCast(js.machEventShift());  

                    if( idx >= JoystickData.max_joysticks )
                        continue;
                    
                    var data = &self.core.joysticks[idx];
                    data.present = false;
                    data.button_count = 0;
                    data.axis_count = 0;

                    @memset(&data.buttons, false);
                    @memset(&data.axes, 0);

                    break :blk Event {
                        .joystick_disconnected = @enumFromInt(idx),
                    };
                },
                .framebuffer_resize => blk: {
                    const width = @as(u32, @intCast(js.machEventShift()));
                    const height = @as(u32, @intCast(js.machEventShift()));
                    const pixel_ratio = @as(u32, @intCast(js.machEventShift()));
                    break :blk Event{
                        .framebuffer_resize = .{
                            .width = width * pixel_ratio,
                            .height = height * pixel_ratio,
                        },
                    };
                },
                .focus_gained => Event.focus_gained,
                .focus_lost => Event.focus_lost,
                else => null,
            };
        }
    }

    fn makeKeyMods(self: EventIterator) KeyMods {
        const is = self.core.input_state;

        return .{
            .shift = is.isKeyPressed(.left_shift) or is.isKeyPressed(.right_shift),
            .control = is.isKeyPressed(.left_control) or is.isKeyPressed(.right_control),
            .alt = is.isKeyPressed(.left_alt) or is.isKeyPressed(.right_alt),
            .super = is.isKeyPressed(.left_super) or is.isKeyPressed(.right_super),
            // FIXME(estel): I think the logic for these two are wrong, but unlikely it matters
            // in a browser. To correct them we need to actually use `KeyboardEvent.getModifierState`
            // in javascript and bring back that info in here.
            .caps_lock = is.isKeyPressed(.caps_lock),
            .num_lock = is.isKeyPressed(.num_lock),
        };
    }
};

const JoystickData = struct {
    present: bool,
    button_count: usize,
    axis_count: usize,

    name: [max_name_len:0]u8,
    buttons: [max_button_count]bool,
    axes: [max_axis_count]f32,

    // 16 as it's the maximum number of joysticks supported by GLFW.
    const max_joysticks = 16;
    const max_name_len = 64;
    const max_button_count = 32;
    const max_axis_count = 16;
};

pub fn init(core: *Core, allocator: std.mem.Allocator, options: Options) !void {
    _ = options;
    var selector = [1]u8{0} ** 15;
    const id = js.machCanvasInit(&selector[0]);

    core.* = Core{
        .allocator = allocator,
        .id = id,
        .input_state = .{},
        .joysticks = std.mem.zeroes([JoystickData.max_joysticks]JoystickData),
    };
}

pub fn deinit(self: *Core) void {
    js.machCanvasDeinit(self.id);
}

pub inline fn pollEvents(self: *Core) EventIterator {
    return EventIterator{
        .core = self,
    };
}

pub fn framebufferSize(self: *Core) Size {
    return .{
        .width = js.machCanvasFramebufferWidth(self.id),
        .height = js.machCanvasFramebufferHeight(self.id),
    };
}

pub fn setWaitTimeout(_: *Core, timeout: f64) void {
    js.machSetWaitTimeout(timeout);
}

pub fn setTitle(self: *Core, title: [:0]const u8) void {
    js.machCanvasSetTitle(self.id, title.ptr, title.len);
}

pub fn setDisplayMode(self: *Core, mode: DisplayMode, monitor: ?usize) void {
    _ = monitor;
    if (mode == .borderless) {
        // borderless fullscreen window has no meaning in web
        mode = .fullscreen;
    }
    js.machCanvasSetDisplayMode(self.id, @intFromEnum(mode));
}

pub fn displayMode(self: *Core) DisplayMode {
    return @as(DisplayMode, @enumFromInt(js.machDisplayMode(self.id)));
}

pub fn setBorder(self: *Core, value: bool) void {
    _ = self;
    _ = value;
}

pub fn border(self: *Core) bool {
    _ = self;
    return false;
}

pub fn setHeadless(self: *Core, value: bool) void {
    _ = self;
    _ = value;
}

pub fn headless(self: *Core) bool {
    _ = self;
    return false;
}

pub fn setVSync(self: *Core, mode: VSyncMode) void {
    _ = self;
    _ = mode;
}

// TODO: https://github.com/gpuweb/gpuweb/issues/1224
pub fn vsync(self: *Core) VSyncMode {
    _ = self;
    return .double;
}

pub fn setSize(self: *Core, value: Size) void {
    js.machCanvasSetSize(self.id, value.width, value.height);
}

pub fn size(self: *Core) Size {
    return .{
        .width = js.machCanvasWidth(self.id),
        .height = js.machCanvasHeight(self.id),
    };
}

pub fn setSizeLimit(self: *Core, limit: SizeLimit) void {
    js.machCanvasSetSizeLimit(
        self.id,
        if (limit.min.width) |val| @as(i32, @intCast(val)) else -1,
        if (limit.min.height) |val| @as(i32, @intCast(val)) else -1,
        if (limit.max.width) |val| @as(i32, @intCast(val)) else -1,
        if (limit.max.height) |val| @as(i32, @intCast(val)) else -1,
    );
}

pub fn sizeLimit(self: *Core) SizeLimit {
    return .{
        .min = .{
            .width = js.machCanvasMinWidth(self.id),
            .height = js.machCanvasMinHeight(self.id),
        },
        .max = .{
            .width = js.machCanvasMaxWidth(self.id),
            .height = js.machCanvasMaxHeight(self.id),
        },
    };
}

pub fn setCursorMode(self: *Core, mode: CursorMode) void {
    js.machSetCursorMode(self.id, @intFromEnum(mode));
}

pub fn cursorMode(self: *Core) CursorMode {
    return @as(CursorMode, @enumFromInt(js.machCursorMode(self.id)));
}

pub fn setCursorShape(self: *Core, shape: CursorShape) void {
    js.machSetCursorShape(self.id, @intFromEnum(shape));
}

pub fn cursorShape(self: *Core) CursorShape {
    return @as(CursorShape, @enumFromInt(js.machCursorShape(self.id)));
}

pub fn joystickPresent(core: *Core, joystick: Joystick) bool {
    const idx: u8 = @intFromEnum(joystick);
    return core.joysticks[idx].present;
}

pub fn joystickName(core: *Core, joystick: Joystick) ?[:0]const u8 {
    const idx: u8 = @intFromEnum(joystick);
    var data = &core.joysticks[idx];

    if( !data.present )
        return null;
    
    return std.mem.span(&data.name);
}

pub fn joystickButtons(core: *Core, joystick: Joystick) ?[]const bool {
    const idx: u8 = @intFromEnum(joystick);
    var data = &core.joysticks[idx];

    if( !data.present )
        return null;

    js.machJoystickButtons(idx, &data.buttons, JoystickData.max_button_count);
    return data.buttons[0..data.button_count];
}

pub fn joystickAxes(core: *Core, joystick: Joystick) ?[]const f32 {
    const idx: u8 = @intFromEnum(joystick);
    var data = &core.joysticks[idx];

    if( !data.present )
        return null;

    js.machJoystickAxes(idx, &data.axes, JoystickData.max_axis_count);
    return data.buttons[0..data.button_count];
}

pub fn keyPressed(self: *Core, key: Key) bool {
    return self.input_state.isKeyPressed(key);
}

pub fn keyReleased(self: *Core, key: Key) bool {
    return self.input_state.isKeyReleased(key);
}

pub fn mousePressed(self: *Core, button: MouseButton) bool {
    return self.input_state.isMouseButtonPressed(button);
}

pub fn mouseReleased(self: *Core, button: MouseButton) bool {
    return self.input_state.isMouseButtonReleased(button);
}

pub fn mousePosition(self: *Core) Core.Position {
    return self.input_state.mouse_position;
}

pub fn adapter(_: *Core) *gpu.Adapter {
    unreachable;
}

pub fn device(_: *Core) *gpu.Device {
    unreachable;
}

pub fn swapChain(_: *Core) *gpu.SwapChain {
    unreachable;
}

pub fn descriptor(_: *Core) gpu.SwapChain.Descriptor {
    unreachable;
}

fn toMachButton(button: i32) MouseButton {
    return switch (button) {
        0 => .left,
        1 => .middle,
        2 => .right,
        3 => .four,
        4 => .five,
        else => unreachable,
    };
}
