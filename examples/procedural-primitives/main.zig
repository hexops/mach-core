const std = @import("std");
const mach = @import("core");
const gpu = mach.gpu;
const renderer = @import("renderer.zig");

pub const App = @This();
core: mach.Core,

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn init(app: *App) !void {
    var allocator = gpa.allocator();
    try app.core.init(allocator, .{ .required_limits = gpu.Limits{
        .max_vertex_buffers = 1,
        .max_vertex_attributes = 2,
        .max_bind_groups = 1,
        .max_uniform_buffers_per_shader_stage = 1,
        .max_uniform_buffer_binding_size = 16 * 1 * @sizeOf(f32),
    } });

    const timer = try mach.Timer.start();

    try renderer.init(&app.core, allocator, timer);
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();
    defer renderer.deinit();
}

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
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

    renderer.update(&app.core);

    return false;
}
