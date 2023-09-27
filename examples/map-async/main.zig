const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const workgroup_size = 64;
const buffer_size = 1000;

pub fn init(app: *App) !void {
    try core.init(.{});
    app.* = .{};

    const output = core.device.createBuffer(&.{
        .usage = .{ .storage = true, .copy_src = true },
        .size = buffer_size * @sizeOf(f32),
        .mapped_at_creation = .false,
    });

    const staging = core.device.createBuffer(&.{
        .usage = .{ .map_read = true, .copy_dst = true },
        .size = buffer_size * @sizeOf(f32),
        .mapped_at_creation = .false,
    });

    const compute_module = core.device.createShaderModuleWGSL("main.wgsl", @embedFile("main.wgsl"));

    const compute_pipeline = core.device.createComputePipeline(&gpu.ComputePipeline.Descriptor{ .compute = gpu.ProgrammableStageDescriptor{
        .module = compute_module,
        .entry_point = "main",
    } });

    const compute_bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = compute_pipeline.getBindGroupLayout(0),
        .entries = &.{
            gpu.BindGroup.Entry.buffer(0, output, 0, buffer_size),
        },
    }));

    compute_module.release();

    const encoder = core.device.createCommandEncoder(null);

    const compute_pass = encoder.beginComputePass(null);
    compute_pass.setPipeline(compute_pipeline);
    compute_pass.setBindGroup(0, compute_bind_group, &.{});
    compute_pass.dispatchWorkgroups(try std.math.divCeil(u32, buffer_size, workgroup_size), 1, 1);
    compute_pass.end();

    encoder.copyBufferToBuffer(output, 0, staging, 0, buffer_size);

    var command = encoder.finish(null);
    encoder.release();

    var response: gpu.Buffer.MapAsyncStatus = undefined;
    const callback = (struct {
        pub inline fn callback(ctx: *gpu.Buffer.MapAsyncStatus, status: gpu.Buffer.MapAsyncStatus) void {
            ctx.* = status;
        }
    }).callback;

    var queue = core.queue;
    queue.submit(&[_]*gpu.CommandBuffer{command});

    staging.mapAsync(.{ .read = true }, 0, buffer_size, &response, callback);
    while (true) {
        if (response == gpu.Buffer.MapAsyncStatus.success) {
            break;
        } else {
            core.device.tick();
        }
    }

    const staging_mapped = staging.getConstMappedRange(f32, 0, buffer_size / @sizeOf(f32));
    for (staging_mapped.?) |v| {
        std.debug.print("{d} ", .{v});
    }
    std.debug.print("\n", .{});
    staging.unmap();
}

pub fn deinit(app: *App) void {
    _ = app;
    defer _ = gpa.deinit();
    core.deinit();
}

pub fn update(_: *App) !bool {
    return true;
}
