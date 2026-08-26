#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D out_tex;
layout(rgba16f, binding = 1, set = 0) uniform image2D out_depth;
layout(rgba16f, binding = 2, set = 0) uniform image2D in_tex;
layout(binding = 3, set = 0) uniform sampler2D in_depth;

layout(push_constant, std430) readonly uniform Params {
    vec2 screen_size;
} variables;

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    vec2 size = variables.screen_size;

    imageStore(out_tex, uv, imageLoad(in_tex, uv));
    imageStore(out_depth, uv, texture(in_depth, uv / size));
}
