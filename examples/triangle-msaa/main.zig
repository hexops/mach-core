const std = @import("std");
const mach = @import("core");
const gpu = mach.gpu;

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,
timer: mach.Timer,
window_title_timer: mach.Timer,
pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,
texture: *gpu.Texture,
texture_view: *gpu.TextureView,

const sample_count = 4;

pub fn init(app: *App) !void {
    try app.core.init(gpa.allocator(), .{});
    app.timer = try mach.Timer.start();
    app.window_title_timer = try mach.Timer.start();

    const shader_module = app.core.device().createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
    defer shader_module.release();

    // Fragment state
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = app.core.descriptor().format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertex_main",
        },
        .multisample = gpu.MultisampleState{
            .count = sample_count,
        },
    };

    app.pipeline = app.core.device().createRenderPipeline(&pipeline_descriptor);
    app.queue = app.core.device().getQueue();

    app.texture = app.core.device().createTexture(&gpu.Texture.Descriptor{
        .size = gpu.Extent3D{
            .width = app.core.descriptor().width,
            .height = app.core.descriptor().height,
        },
        .sample_count = sample_count,
        .format = app.core.descriptor().format,
        .usage = .{ .render_attachment = true },
    });
    app.texture_view = app.texture.createView(null);

    shader_module.release();
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();

    app.texture.release();
    app.texture_view.release();
}

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .framebuffer_resize => |size| {
                app.texture.release();
                app.texture = app.core.device().createTexture(&gpu.Texture.Descriptor{
                    .size = gpu.Extent3D{
                        .width = size.width,
                        .height = size.height,
                    },
                    .sample_count = sample_count,
                    .format = app.core.descriptor().format,
                    .usage = .{ .render_attachment = true },
                });

                app.texture_view.release();
                app.texture_view = app.texture.createView(null);
            },
            .close => return true,
            else => {},
        }
    }

    const back_buffer_view = app.core.swapChain().getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = app.texture_view,
        .resolve_target = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .discard,
    };

    const encoder = app.core.device().createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.draw(3, 1, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    app.core.swapChain().present();
    back_buffer_view.release();

    const delta_time = app.timer.lap();
    if (app.window_title_timer.read() >= 1.0) {
        app.window_title_timer.reset();
        var buf: [32]u8 = undefined;
        const title = try std.fmt.bufPrintZ(&buf, "Mach Core [ FPS: {d} ]", .{@floor(1 / delta_time)});
        app.core.setTitle(title);
    }
    return false;
}
