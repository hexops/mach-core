// Check that the user's app matches the required interface.
comptime {
    if (!@import("builtin").is_test) @import("core").AppInterface(@import("app"));
}

// Forward "app" declarations into our namespace, such that @import("root").foo works as expected.
pub usingnamespace @import("app");
const App = @import("app").App;

const std = @import("std");
const builtin = @import("builtin");
const core = @import("core");
const dusk = @import("mach-dusk");
const glfw = @import("mach-glfw");
const gpu = core.gpu;

pub const GPUInterface = if (@hasDecl(App, "GPUInterface")) App.GPUInterface else dusk.Interface;

fn baseLoader(_: u32, name: [*:0]const u8) ?*const fn () callconv(.C) void {
    return glfw.getInstanceProcAddress(null, name);
}

pub fn main() !void {
    // Run from the directory where the executable is located so relative assets can be found.
    var buffer: [1024]u8 = undefined;
    const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
    std.os.chdir(path) catch {};

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    core.allocator = gpa.allocator();

    // Initialize GPU implementation
    if (builtin.target.os.tag == .linux) try gpu.Impl.init(gpa.allocator(), .{ .baseLoader = @ptrCast(&baseLoader) });
    if (builtin.target.isDarwin()) try gpu.Impl.init(gpa.allocator(), .{});
    if (builtin.target.os.tag == .windows) try gpu.Impl.init(gpa.allocator(), .{});

    var app: App = undefined;
    try app.init();
    defer app.deinit();
    while (!try core.update(&app)) {}
}
