const builtin = @import("builtin");

const platform = if (builtin.cpu.arch == .wasm32)
    @import("platform/wasm.zig")
else
    @import("platform/native.zig");

pub const Core = platform.Core;
pub const Timer = platform.Timer;

// Verifies that a platform implementation exposes the expected function declarations.
comptime {
    assertHasDecl(@This(), "Core");
    assertHasDecl(@This(), "Timer");

    // Core
    assertHasDecl(@This().Core, "init");
    assertHasDecl(@This().Core, "deinit");
    assertHasDecl(@This().Core, "pollEvents");

    assertHasDecl(@This().Core, "setTitle");

    assertHasDecl(@This().Core, "setDisplayMode");
    assertHasDecl(@This().Core, "displayMode");

    assertHasDecl(@This().Core, "setBorder");
    assertHasDecl(@This().Core, "border");

    assertHasDecl(@This().Core, "setResizeable");
    assertHasDecl(@This().Core, "resizeable");

    assertHasDecl(@This().Core, "setHeadless");
    assertHasDecl(@This().Core, "headless");

    assertHasDecl(@This().Core, "setVSync");
    assertHasDecl(@This().Core, "vsync");

    assertHasDecl(@This().Core, "setSize");
    assertHasDecl(@This().Core, "size");

    assertHasDecl(@This().Core, "setSizeLimit");
    assertHasDecl(@This().Core, "sizeLimit");

    assertHasDecl(@This().Core, "setCursorMode");
    assertHasDecl(@This().Core, "cursorMode");

    assertHasDecl(@This().Core, "setCursorShape");
    assertHasDecl(@This().Core, "cursorShape");

    assertHasDecl(@This().Core, "joystickPresent");
    assertHasDecl(@This().Core, "joystickName");
    assertHasDecl(@This().Core, "joystickButtons");
    assertHasDecl(@This().Core, "joystickAxes");

    assertHasDecl(@This().Core, "keyPressed");
    assertHasDecl(@This().Core, "keyReleased");
    assertHasDecl(@This().Core, "mousePressed");
    assertHasDecl(@This().Core, "mouseReleased");
    assertHasDecl(@This().Core, "mousePosition");

    assertHasDecl(@This().Core, "outOfMemory");

    // Timer
    assertHasDecl(@This().Timer, "start");
    assertHasDecl(@This().Timer, "read");
    assertHasDecl(@This().Timer, "reset");
    assertHasDecl(@This().Timer, "lap");
}

fn assertHasDecl(comptime T: anytype, comptime name: []const u8) void {
    if (!@hasDecl(T, name)) @compileError("Core missing declaration: " ++ name);
}
