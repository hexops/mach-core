const std = @import("std");
const core = @import("core");
const gpu = core.gpu;

pub const App = @This();

pub fn init() !App {
    try core.init(.{});
    return App{};
}

pub fn deinit(app: *App) void {
    defer core.deinit();
    _ = app;
}

pub fn update(app: *App) !bool {
    _ = app;
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        std.log.debug("event: {}\n", .{event});
        switch (event) {
            .close => return true,
            .key_press => |ev| {
                if (ev.key == .p) @panic("p pressed, panic triggered");
                if (ev.key == .q) {
                    std.log.err("q pressed, exiting app", .{});
                    return true;
                }
            },
            else => {},
        }
    }
    return false;
}
