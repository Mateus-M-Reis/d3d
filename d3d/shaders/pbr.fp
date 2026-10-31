#version 140

// d3d PBR fragment shader.
//
// Metallic-roughness Cook-Torrance lighting from Defold's LightBuffer, plus
// cascaded directional shadows and distance fog. The output is linear HDR;
// tone mapping and gamma encoding happen in the post pass.

#define MAX_LIGHT_COUNT 32

in highp vec3 var_world_position;
in highp vec3 var_view_position;
in mediump vec3 var_normal;
in mediump vec2 var_texcoord0;
in highp vec4 var_shadow0;
in highp vec4 var_shadow1;
in highp vec4 var_shadow2;

out vec4 out_fragColor;

uniform sampler2D albedo_texture;
uniform sampler2D normal_texture;
uniform sampler2D shadow_map0;
uniform sampler2D shadow_map1;
uniform sampler2D shadow_map2;

uniform d3d_frame
{
    highp vec4 camera_position;
    highp vec4 fog_color;
    highp vec4 fog_params;       // x: density, y: max factor, z/w: reserved
    highp vec4 cascade_splits;   // x/y/z: far view depth per cascade
    highp vec4 shadow_params;    // x: texel size, y: kernel, z: min bias, w: slope bias
};

uniform d3d_material
{
    mediump vec4 base_color;
    mediump vec4 material_params; // x: metallic, y: roughness, z: use normal map, w: alpha cutoff
    mediump vec4 emissive_factor;
};

#ifdef EDITOR
uniform Light
{
    vec4 position;
    vec4 color;
    vec4 direction_range;
    vec4 params;
} lights[MAX_LIGHT_COUNT];

uniform LightBuffer
{
    vec4 light_info;
};
#else
struct Light
{
    vec4 position;
    vec4 color;
    vec4 direction_range;
    vec4 params;
};

uniform LightBuffer
{
    vec4 light_info;
    Light lights[MAX_LIGHT_COUNT];
};
#endif

const float PI = 3.14159265359;

float distribution_ggx(float n_dot_h, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float d = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
    return a2 / max(PI * d * d, 1e-6);
}

float visibility_smith(float n_dot_v, float n_dot_l, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float gv = n_dot_l * sqrt(n_dot_v * n_dot_v * (1.0 - a2) + a2);
    float gl = n_dot_v * sqrt(n_dot_l * n_dot_l * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-5);
}

vec3 fresnel_schlick(float cos_theta, vec3 f0)
{
    return f0 + (vec3(1.0) - f0) * pow(1.0 - cos_theta, 5.0);
}

float sample_shadow(sampler2D shadow_map, highp vec3 coord, float receiver_depth)
{
    if (coord.x < 0.0 || coord.x > 1.0 || coord.y < 0.0 || coord.y > 1.0)
    {
        return 1.0;
    }

    float stored_depth = texture(shadow_map, coord.xy).r;
    return receiver_depth <= stored_depth ? 1.0 : 0.0;
}

float shadow_visibility(highp vec4 shadow_coord, sampler2D shadow_map,
                        vec3 normal, vec3 direction_to_light)
{
    if (shadow_coord.w <= 0.0)
    {
        return 1.0;
    }

    highp vec3 coord = shadow_coord.xyz / shadow_coord.w;
    if (coord.z < 0.0 || coord.z > 1.0)
    {
        return 1.0;
    }

    float n_dot_l = max(dot(normal, direction_to_light), 0.0);
    float bias = max(shadow_params.z, shadow_params.w * (1.0 - n_dot_l));
    float receiver_depth = coord.z - bias;

    float texel = shadow_params.x;
    float kernel = shadow_params.y;
    float spacing = 1.0;
    float step_size = texel * spacing;

    if (kernel >= 2.5)
    {
        float visibility = 0.0;
        for (int y = -1; y <= 1; ++y)
        {
            for (int x = -1; x <= 1; ++x)
            {
                vec2 offset = vec2(float(x), float(y)) * step_size;
                visibility += sample_shadow(shadow_map, coord + vec3(offset, 0.0), receiver_depth);
            }
        }
        return visibility / 9.0;
    }

    return sample_shadow(shadow_map, coord, receiver_depth);
}

float directional_visibility(float view_depth, vec3 normal, vec3 direction_to_light)
{
    if (view_depth <= cascade_splits.x)
    {
        return shadow_visibility(var_shadow0, shadow_map0, normal, direction_to_light);
    }
    if (view_depth <= cascade_splits.y)
    {
        return shadow_visibility(var_shadow1, shadow_map1, normal, direction_to_light);
    }
    if (view_depth <= cascade_splits.z)
    {
        return shadow_visibility(var_shadow2, shadow_map2, normal, direction_to_light);
    }
    return 1.0;
}

vec3 shade_directional(Light light, vec3 normal, vec3 view, vec3 diffuse_color,
                       vec3 f0, float roughness, float metallic, float view_depth)
{
    vec3 direction_to_light = normalize(-light.direction_range.xyz);
    float n_dot_l = max(dot(normal, direction_to_light), 0.0);
    if (n_dot_l <= 0.0)
    {
        return vec3(0.0);
    }

    vec3 radiance = light.color.rgb * light.params.y;
    radiance *= directional_visibility(view_depth, normal, direction_to_light);

    vec3 half_vector = normalize(view + direction_to_light);
    float n_dot_v = max(dot(normal, view), 0.0);
    float n_dot_h = max(dot(normal, half_vector), 0.0);
    float v_dot_h = max(dot(view, half_vector), 0.0);

    float ndf = distribution_ggx(n_dot_h, roughness);
    float vis = visibility_smith(n_dot_v, n_dot_l, roughness);
    vec3 fresnel = fresnel_schlick(v_dot_h, f0);

    vec3 specular = ndf * vis * fresnel;
    vec3 diffuse = (vec3(1.0) - fresnel) * (1.0 - metallic) * diffuse_color / PI;

    return (diffuse + specular) * radiance * n_dot_l;
}

vec3 shade_point(Light light, vec3 normal, vec3 view, vec3 world_position,
                 vec3 diffuse_color, vec3 f0, float roughness, float metallic)
{
    vec3 to_light = light.position.xyz - world_position;
    float distance = length(to_light);
    if (distance >= light.direction_range.w)
    {
        return vec3(0.0);
    }

    vec3 direction_to_light = to_light / max(distance, 1e-5);
    float n_dot_l = max(dot(normal, direction_to_light), 0.0);
    if (n_dot_l <= 0.0)
    {
        return vec3(0.0);
    }

    float ratio = distance / max(light.direction_range.w, 1e-5);
    float window = clamp(1.0 - ratio * ratio * ratio * ratio, 0.0, 1.0);
    float attenuation = window * window / (distance * distance + 1.0);

    vec3 half_vector = normalize(view + direction_to_light);
    float n_dot_v = max(dot(normal, view), 0.0);
    float n_dot_h = max(dot(normal, half_vector), 0.0);
    float v_dot_h = max(dot(view, half_vector), 0.0);

    float ndf = distribution_ggx(n_dot_h, roughness);
    float vis = visibility_smith(n_dot_v, n_dot_l, roughness);
    vec3 fresnel = fresnel_schlick(v_dot_h, f0);

    vec3 specular = ndf * vis * fresnel;
    vec3 diffuse = (vec3(1.0) - fresnel) * (1.0 - metallic) * diffuse_color / PI;

    return (diffuse + specular) * light.color.rgb * light.params.y * attenuation * n_dot_l;
}

vec3 shade_spot(Light light, vec3 normal, vec3 view, vec3 world_position,
                vec3 diffuse_color, vec3 f0, float roughness, float metallic)
{
    vec3 to_light = light.position.xyz - world_position;
    float distance = length(to_light);
    if (distance >= light.direction_range.w)
    {
        return vec3(0.0);
    }

    vec3 direction_to_light = to_light / max(distance, 1e-5);
    float n_dot_l = max(dot(normal, direction_to_light), 0.0);
    if (n_dot_l <= 0.0)
    {
        return vec3(0.0);
    }

    vec3 spot_direction = normalize(light.direction_range.xyz);
    float outer_cos = cos(0.5 * light.params.w);
    float inner_cos = cos(0.5 * light.params.z);
    float cone = smoothstep(outer_cos, inner_cos, dot(-direction_to_light, spot_direction));
    if (cone <= 0.0)
    {
        return vec3(0.0);
    }

    float ratio = distance / max(light.direction_range.w, 1e-5);
    float window = clamp(1.0 - ratio * ratio * ratio * ratio, 0.0, 1.0);
    float attenuation = window * window / (distance * distance + 1.0);

    vec3 half_vector = normalize(view + direction_to_light);
    float n_dot_v = max(dot(normal, view), 0.0);
    float n_dot_h = max(dot(normal, half_vector), 0.0);
    float v_dot_h = max(dot(view, half_vector), 0.0);

    float ndf = distribution_ggx(n_dot_h, roughness);
    float vis = visibility_smith(n_dot_v, n_dot_l, roughness);
    vec3 fresnel = fresnel_schlick(v_dot_h, f0);

    vec3 specular = ndf * vis * fresnel;
    vec3 diffuse = (vec3(1.0) - fresnel) * (1.0 - metallic) * diffuse_color / PI;

    return (diffuse + specular) * light.color.rgb * light.params.y * attenuation * cone * n_dot_l;
}

void main()
{
    vec4 albedo_sample = texture(albedo_texture, var_texcoord0);
    float alpha = albedo_sample.a * base_color.a;
    if (alpha < material_params.w)
    {
        discard;
    }

    vec3 albedo = albedo_sample.rgb * base_color.rgb;
    vec3 normal = normalize(var_normal);

    if (material_params.z > 0.5)
    {
        vec3 tangent_normal = texture(normal_texture, var_texcoord0).xyz * 2.0 - 1.0;
        normal = normalize(normal + tangent_normal * 0.001);
    }

    vec3 view = normalize(camera_position.xyz - var_world_position);
    float metallic = clamp(material_params.x, 0.0, 1.0);
    float roughness = clamp(material_params.y, 0.04, 1.0);
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    vec3 diffuse_color = albedo * (1.0 - metallic);

    float view_depth = -var_view_position.z;
    vec3 color = light_info.xyz * albedo;

    int light_count = int(clamp(light_info.w, 0.0, float(MAX_LIGHT_COUNT)));
    for (int i = 0; i < MAX_LIGHT_COUNT; ++i)
    {
        if (i >= light_count)
        {
            break;
        }

        int type = int(lights[i].params.x);
        if (type == 0)
        {
            color += shade_directional(lights[i], normal, view, diffuse_color,
                                       f0, roughness, metallic, view_depth);
        }
        else if (type == 1)
        {
            color += shade_point(lights[i], normal, view, var_world_position,
                                 diffuse_color, f0, roughness, metallic);
        }
        else if (type == 2)
        {
            color += shade_spot(lights[i], normal, view, var_world_position,
                                diffuse_color, f0, roughness, metallic);
        }
    }

    color += emissive_factor.rgb;

    float distance = length(camera_position.xyz - var_world_position);
    float fog = 1.0 - exp(-pow(distance * fog_params.x, 2.0));
    color = mix(color, fog_color.rgb, clamp(fog * fog_params.y, 0.0, 1.0));

    out_fragColor = vec4(color, alpha);
}
