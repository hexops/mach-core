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

// For compatibility with the wasm platform. Allows one to define custom std_options without having
// to deal with a platform-specific logFn:
//
// ```
// pub const std_options = struct {
//     pub const logFn = @import("root").machLogFn;
// };
// ```
pub fn machLogFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    std.log.defaultLog(message_level, scope, format, args);
}

pub fn main() !void {
    gpu.Impl.init();

    var app: App = undefined;
    try app.init();
    defer app.deinit();

    while (true) {
        if (try app.core.internal.update(&app)) return;
    }
}
