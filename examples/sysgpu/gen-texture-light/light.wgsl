struct CameraUniform {
	view_pos: vec4<f32>,
	view_proj: mat4x4<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
};

struct Light {
	position: vec4<f32>,
	color: vec4<f32>,
};

@group(0) @binding(0) var<uniform> camera: CameraUniform;
@group(1) @binding(0) var<uniform> light: Light;

@vertex
fn vs_main(
	// TODO - struct input
	@location(0) model_position: vec3<f32>,
	@location(1) model_normal: vec3<f32>,
	@location(2) model_tex_coords: vec2<f32>,
) -> VertexOutput {
    var out: VertexOutput;
    let world_pos = vec4<f32>(model_position + light.position.xyz, 1.0);
    out.clip_position = camera.view_proj * world_pos;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
	return vec4<f32>(1.0, 1.0, 1.0, 0.5);
}
