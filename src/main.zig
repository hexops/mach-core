pub const Core = @import("Core.zig");
pub const Timer = @import("Timer.zig");
pub const gpu = @import("gpu");
pub const sysjs = @import("sysjs");
const builtin = @import("builtin");
pub const platform_util = if (builtin.cpu.arch == .wasm32) {} else @import("platform/native/util.zig");

pub fn AppInterface(comptime app_entry: anytype) void {
    if (!@hasDecl(app_entry, "App")) {
        @compileError("expected e.g. `pub const App = mach.App(modules, init)' (App definition missing in your main Zig file)");
    }

    const App = app_entry.App;
    if (@typeInfo(App) != .Struct) {
        @compileError("App must be a struct type. Found:" ++ @typeName(App));
    }

    if (@hasDecl(App, "init")) {
        const InitFn = @TypeOf(@field(App, "init"));
        if (InitFn != fn (*App) @typeInfo(@typeInfo(InitFn).Fn.return_type.?).ErrorUnion.error_set!void)
            @compileError("expected 'pub fn init(app: *App) !void' found '" ++ @typeName(InitFn) ++ "'");
    } else {
        @compileError("App must export 'pub fn init(app: *App) !void'");
    }

    if (@hasDecl(App, "update")) {
        const UpdateFn = @TypeOf(@field(App, "update"));
        if (UpdateFn != fn (app: *App) @typeInfo(@typeInfo(UpdateFn).Fn.return_type.?).ErrorUnion.error_set!bool)
            @compileError("expected 'pub fn update(app: *App) !bool' found '" ++ @typeName(UpdateFn) ++ "'");
    } else {
        @compileError("App must export 'pub fn update(app: *App) !bool'");
    }

    if (@hasDecl(App, "updateMainThread")) {
        const UpdateMainThreadFn = @TypeOf(@field(App, "updateMainThread"));
        if (UpdateMainThreadFn != fn (app: *App) @typeInfo(@typeInfo(UpdateMainThreadFn).Fn.return_type.?).ErrorUnion.error_set!bool)
            @compileError("expected 'pub fn updateMainThread(app: *App) !bool' found '" ++ @typeName(UpdateMainThreadFn) ++ "'");
    }

    if (@hasDecl(App, "deinit")) {
        const DeinitFn = @TypeOf(@field(App, "deinit"));
        if (DeinitFn != fn (app: *App) void)
            @compileError("expected 'pub fn deinit(app: *App) void' found '" ++ @typeName(DeinitFn) ++ "'");
    } else {
        @compileError("App must export 'pub fn deinit(app: *App) void'");
    }
}
