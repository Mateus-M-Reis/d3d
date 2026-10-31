#version 140

// HDR presentation pass: exposure, ACES tone mapping and gamma encoding.

in mediump vec2 var_texcoord0;

out vec4 out_fragColor;

uniform sampler2D scene_texture;

uniform d3d_post
{
    mediump vec4 post_params; // x: exposure, y: tonemap, z: gamma, w: vignette
};

vec3 aces_fitted(vec3 x)
{
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main()
{
    vec3 color = texture(scene_texture, var_texcoord0).rgb;
    color *= post_params.x;

    if (post_params.y > 0.5)
    {
        color = aces_fitted(color);
    }

    float gamma = max(post_params.z, 1.0);
    color = pow(max(color, vec3(0.0)), vec3(1.0 / gamma));

    if (post_params.w > 0.0)
    {
        vec2 centered = var_texcoord0 * 2.0 - 1.0;
        float vignette = 1.0 - dot(centered, centered) * post_params.w;
        color *= clamp(vignette, 0.0, 1.0);
    }

    out_fragColor = vec4(color, 1.0);
}
