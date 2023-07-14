const std = @import("std");
const Core = @import("Core.zig");
const KeyBitSet = std.StaticBitSet(@intFromEnum(Core.Key.max));
const MouseButtonSet = std.StaticBitSet(@intFromEnum(Core.MouseButton.max));
const InputState = @This();

keys: KeyBitSet = KeyBitSet.initEmpty(),
mouse_buttons: MouseButtonSet = MouseButtonSet.initEmpty(),
mouse_position: Core.Position = .{ .x = 0, .y = 0 },

pub inline fn isKeyPressed(self: InputState, key: Core.Key) bool {
    return self.keys.isSet(@intFromEnum(key));
}

pub inline fn isKeyReleased(self: InputState, key: Core.Key) bool {
    return !self.isKeyPressed(key);
}

pub inline fn isMouseButtonPressed(self: InputState, button: Core.MouseButton) bool {
    return self.mouse_buttons.isSet(@intFromEnum(button));
}

pub inline fn isMouseButtonReleased(self: InputState, button: Core.MouseButton) bool {
    return !self.isMouseButtonPressed(button);
}
