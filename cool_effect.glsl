#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;
layout(rgba16f, binding = 1, set = 0) uniform image2D mask_tex;
layout(binding = 2, set = 0) uniform sampler2D depth_tex;
layout(rgba16f, binding = 3, set = 0) uniform image2D prev_tex;
layout(rgba16f, binding = 4, set = 0) uniform image2D motion_tex;

layout(push_constant, std430) readonly uniform Params
{
    vec2 screen_size;
    float time;
} variables;

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    vec2 size = variables.screen_size;

    vec4 motion = imageLoad(motion_tex, uv);
    vec4 screen = imageLoad(screen_tex, uv);
    vec4 mask = imageLoad(mask_tex, uv);
    vec4 prev = imageLoad(prev_tex, ivec2(round(vec2(uv) + vec2(motion.rg * size))));
    float depth = texture(depth_tex, uv / size).r;

    vec4 color = mix(screen, prev, mask.a);

    if(!any(isnan(color)))
    {
        imageStore(screen_tex, uv, color);
        imageStore(prev_tex, uv, color);
    }
}
