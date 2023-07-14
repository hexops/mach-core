const std = @import("std");
const Core = @import("Core.zig");
const ArrayBitSet = std.bit_set.ArrayBitSet;
const IntegerBitSet = std.bit_set.IntegerBitSet;
const KeyBitSet = ArrayBitSet(usize, @intFromEnum(Core.Key.max));
const MouseButtonSet = IntegerBitSet(@intFromEnum(Core.MouseButton.max));
const InputState = @This();

keys: KeyBitSet = KeyBitSet.initEmpty(),
mouse_buttons: MouseButtonSet = MouseButtonSet.initEmpty(),
mouse_position: Core.Position = .{ .x = 0, .y = 0 },

/// Updates the input state with the corresponding event.
pub fn update(self: *InputState, ev: Core.Event) void {
    switch (ev) {
        .key_press => |k| self.keys.set(@intFromEnum(k.key)),
        .key_release => |k| self.keys.unset(@intFromEnum(k.key)),
        .mouse_motion => |mm| self.mouse_position = mm.pos,
        .mouse_press => |mb| {
            self.mouse_buttons.set(@intFromEnum(mb.button));
            self.mouse_position = mb.pos;
        },
        .mouse_release => |mb| {
            self.mouse_buttons.unset(@intFromEnum(mb.button));
            self.mouse_position = mb.pos;
        },
        else => {},
    }
}

/// Checks if the given key is held pressed.
pub inline fn isKeyPressed(self: InputState, key: Core.Key) bool {
    return self.keys.isSet(@intFromEnum(key));
}

/// Checks if the given key is released.
pub inline fn isKeyReleased(self: InputState, key: Core.Key) bool {
    return !self.isKeyPressed(key);
}

/// Checks if the given mouse button is held pressed.
pub inline fn isMouseButtonPressed(self: InputState, button: Core.MouseButton) bool {
    return self.mouse_buttons.isSet(@intFromEnum(button));
}

/// Checks if the given mouse button is released.
pub inline fn isMouseButtonReleased(self: InputState, button: Core.MouseButton) bool {
    return !self.isMouseButtonPressed(button);
}

/// Retreives the last known mouse position.
pub inline fn getMousePosition(self: InputState) Core.Position {
    return self.mouse_position;
}
