const std = @import("std");
const Timer = @import("Timer.zig");

pub const Frequency = @This();

/// The target frequency (e.g. 60hz) or zero for unlimited
target: u32 = 0,

/// The estimated delay that is needed to achieve the target frequency. Updated during tick()
delay_ns: u64 = 0,

/// The actual measured frequency. This is updated every 1/10th second (the number of actual ticks
/// measured every 1/10th second, multiplied by 10.)
rate: u32 = 0,

/// Internal fields, this must be initialized via a call to start().
internal: struct {
    // The frame number in this second's cycle. e.g. zero to 59
    count: u32,
    timer: Timer,
} = undefined,

/// Starts the timer used for frequency calculation. Must be called once before anything else.
pub fn start(f: *Frequency) !void {
    f.internal = .{
        .count = 0,
        .timer = try Timer.start(),
    };
}

/// Tick should be called at each occurrence (e.g. frame)
pub inline fn tick(f: *Frequency) void {
    var current_time = f.internal.timer.readPrecise();
    if (current_time >= std.time.ns_per_s) {
        f.rate = f.internal.count;
        f.internal.count = 0;
        f.internal.timer.reset();
        current_time = f.internal.timer.readPrecise();
    }
    if (f.target != 0) {
        var limited_count = if (f.internal.count > f.target) f.target else f.internal.count + 1;
        const target_time_per_tick: u64 = (std.time.ns_per_s / f.target);
        const target_time = target_time_per_tick * limited_count;
        if (current_time > target_time) {
            f.delay_ns = 0;
        } else {
            f.delay_ns = target_time - current_time;
        }
    } else {
        f.delay_ns = 0;
    }
    f.internal.count += 1;
}
