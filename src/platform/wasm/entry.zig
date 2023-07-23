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

pub const GPUInterface = gpu.StubInterface;

pub fn machLogFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const writer = LogWriter{ .context = {} };

    writer.print(message_level.asText() ++ prefix ++ format ++ "\n", args) catch return;
    machLogFlush();
}

// Define std_options.logFn if the user did not in their "app" main.zig
pub usingnamespace if (@hasDecl(App, "std_options")) struct {} else struct {
    pub const std_options = struct {
        pub const logFn = @import("root").machLogFn;
    };
};

var app: App = undefined;
export fn wasmInit() void {
    app.init() catch unreachable;
}

export fn wasmUpdate() bool {
    return app.update() catch unreachable;
}

export fn wasmDeinit() void {
    app.deinit();
}

// Custom @panic implementation which logs to the browser console.
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;
    _ = ret_addr;
    machPanic(msg.ptr, msg.len);
    unreachable;
}

pub extern "mach" fn machLogWrite(str: [*]const u8, len: u32) void;
pub extern "mach" fn machLogFlush() void;
pub extern "mach" fn machPanic(str: [*]const u8, len: u32) void;

const LogError = error{};
const LogWriter = std.io.Writer(void, LogError, writeLog);
fn writeLog(_: void, msg: []const u8) LogError!usize {
    machLogWrite(msg.ptr, msg.len);
    return msg.len;
}
