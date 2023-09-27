// Check that the user's app matches the required interface.
comptime {
    if (!@import("builtin").is_test) @import("mach-core").AppInterface(@import("app"));
}

// Forward "app" declarations into our namespace, such that @import("root").foo works as expected.
pub usingnamespace @import("app");
const App = @import("app").App;

const std = @import("std");
const core = @import("mach-core");
const build_options = @import("build-options");
const gpu = core.gpu;
const dusk = core.dusk;

pub const GPUInterface = if (@hasDecl(App, "GPUInterface"))
    App.GPUInterface
else if (build_options.use_dusk)
    dusk.Interface
else
    gpu.dawn.Interface;

pub fn main() !void {
    // Run from the directory where the executable is located so relative assets can be found.
    var buffer: [1024]u8 = undefined;
    const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
    std.os.chdir(path) catch {};

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    core.allocator = gpa.allocator();

    // Initialize GPU implementation
    if (build_options.use_dusk) {
        // Dusk
        try gpu.Impl.init(core.allocator, .{});
    } else {
        // Dawn
        gpu.Impl.init();
    }

    var app: App = undefined;
    try app.init();
    defer app.deinit();
    while (!try core.update(&app)) {}
}
