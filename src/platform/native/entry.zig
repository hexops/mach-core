// Check that the user's app matches the required interface.
comptime {
    if (!@import("builtin").is_test) @import("core").AppInterface(@import("app"));
}

const std = @import("std");
const App = @import("app").App;
const core = @import("core");
const gpu = core.gpu;

pub const GPUInterface = if (@hasDecl(App, "GPUInterface")) App.GPUInterface else gpu.dawn.Interface;

const app_std_options = if (@hasDecl(App, "std_options")) App.std_options else struct {};

pub const std_options = struct {
    pub const log_level = if (@hasDecl(app_std_options, "log_level"))
        app_std_options.log_level
    else
        std.log.default_level;

    pub const log_scope_levels = if (@hasDecl(App, "log_scope_levels"))
        app_std_options.log_scope_levels
    else
        &[0]std.log.ScopeLevel{};
};

pub fn main() !void {
    gpu.Impl.init();
    _ = gpu.Export(GPUInterface);

    var app: App = undefined;
    try app.init();
    defer app.deinit();

    while (true) {
        if (try app.core.internal.update(&app)) return;
    }
}
