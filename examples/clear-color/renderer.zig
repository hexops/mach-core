const mach = @import("core");
const gpu = mach.gpu;

pub const Renderer = @This();

var queue: *gpu.Queue = undefined;

pub fn RendererInit(core: *mach.Core) void {
    queue = core.device().getQueue();
}

pub fn RenderUpdate(core: *mach.Core) void {
    const back_buffer_view = core.swapChain().getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = gpu.Color{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device().createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swapChain().present();
    back_buffer_view.release();
}
