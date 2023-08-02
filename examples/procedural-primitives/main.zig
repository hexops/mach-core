const std = @import("std");
const core = @import("core");
const gpu = core.gpu;
const renderer = @import("renderer.zig");

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn init(app: *App) !void {
    try core.init(.{ .required_limits = gpu.Limits{
        .max_vertex_buffers = 1,
        .max_vertex_attributes = 2,
        .max_bind_groups = 1,
        .max_uniform_buffers_per_shader_stage = 1,
        .max_uniform_buffer_binding_size = 16 * 1 * @sizeOf(f32),
    } });

    var allocator = gpa.allocator();
    const timer = try core.Timer.start();
    try renderer.init(allocator, timer);
    app.* = .{};
}

pub fn deinit(app: *App) void {
    _ = app;
    defer _ = gpa.deinit();
    defer core.deinit();
    defer renderer.deinit();
}

pub fn update(app: *App) !bool {
    _ = app;
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                if (ev.key == .space) return true;
                if (ev.key == .right) {
                    renderer.curr_primitive_index += 1;
                    renderer.curr_primitive_index %= 7;
                }
            },
            .close => return true,
            else => {},
        }
    }

    renderer.update();

    return false;
}
