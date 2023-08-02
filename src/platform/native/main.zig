// Check that the user's app matches the required interface.
comptime {
    if (!@import("builtin").is_test) @import("core").AppInterface(@import("app"));
}

// Forward "app" declarations into our namespace, such that @import("root").foo works as expected.
pub usingnamespace @import("app");
const App = @import("app").App;

const std = @import("std");
const core = @import("core");
const gpu = core.gpu;

pub const GPUInterface = if (@hasDecl(App, "GPUInterface")) App.GPUInterface else gpu.dawn.Interface;

pub fn main() !void {
    // Run from the directory where the executable is located so relative assets can be found.
    var buffer: [1024]u8 = undefined;
    const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
    std.os.chdir(path) catch {};

    // Initialize GPU implementation
    gpu.Impl.init();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    core.allocator = gpa.allocator();

    var app = try App.init();
    defer app.deinit();
    errdefer app.deinit();
    while (!try core.update(&app)) {}
}
