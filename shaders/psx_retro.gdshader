shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform bool enable_pixelation = true;
uniform vec2 target_resolution = vec2(960.0, 540.0);
uniform float color_depth : hint_range(4.0, 64.0, 1.0) = 32.0;
uniform float dither_intensity : hint_range(0.0, 2.0, 0.05) = 0.16;
uniform float grain_intensity : hint_range(0.0, 0.2, 0.005) = 0.006;
uniform float scanline_intensity : hint_range(0.0, 0.5, 0.01) = 0.01;
uniform float chromatic_aberration : hint_range(0.0, 0.05, 0.0005) = 0.0008;
uniform float static_glitch_intensity : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float saturation : hint_range(0.5, 2.0, 0.05) = 1.15;
// Keep the physical world noir while allowing phosphor UI accents to retain color.
uniform float noir_strength : hint_range(0.0, 1.0, 0.05) = 0.0;

// 8x8 Bayer Ordered Dither Matrix (values normalized to [0, 1])
const float bayer8[64] = float[64](
     0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0,
    48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0,
    12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0,
    60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0,
     3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0,
    52.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0,
    15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0,
    63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0
);

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 res = target_resolution;
    vec2 uv = SCREEN_UV;

    // 1. Pixelation downsampling
    if (enable_pixelation && res.x > 0.0 && res.y > 0.0) {
        uv = floor(uv * res) / res;
    }

    // Effective combined glitch intensity
    float effective_glitch = clamp(max(glitch_intensity, static_glitch_intensity), 0.0, 1.0);

    // 2. Glitch Jitter, Sine-Modulated Static Bands & Tape Displacement
    // Intermittent and subtle rather than heavy continuous noise
    float glitch_x = 0.0;
    if (effective_glitch > 0.001) {
        // Intermittent tracking pulse that triggers in sporadic intervals
        float tracking_pulse = pow(sin(TIME * 1.8) * 0.5 + 0.5, 6.0);
        float band_wave = sin(uv.y * 36.0 + TIME * 12.0) * cos(uv.y * 72.0 - TIME * 8.0);
        float line_id = floor(uv.y * (res.y * 0.12));
        float tear_noise = hash21(vec2(line_id, floor(TIME * 16.0)));

        if (tear_noise > (1.0 - effective_glitch * 0.30 * tracking_pulse)) {
            glitch_x = (tear_noise - 0.5) * 0.025 * effective_glitch;
        }
        if (abs(band_wave) > (1.0 - effective_glitch * 0.35 * tracking_pulse)) {
            glitch_x += band_wave * 0.008 * effective_glitch;
        }
    }
    vec2 final_uv = uv + vec2(glitch_x, 0.0);

    // 3. Subdued Chromatic Aberration via Radial Screen Mask
    // Center road is kept crisp and legible; RGB fringe is pushed to outer borders
    vec2 center_offset = final_uv - vec2(0.5);
    float radial_dist = length(center_offset * vec2(1.0, 1.15));
    float border_mask = smoothstep(0.20, 0.65, radial_dist);

    float effective_ca_mask = mix(border_mask, max(border_mask, 0.35), effective_glitch);
    float ca_amount = chromatic_aberration * effective_ca_mask;

    vec2 ca_offset = (center_offset * (ca_amount * 1.4)) + vec2(ca_amount * 0.35, 0.0);

    // Sample channels with radial displacement
    float r = texture(screen_texture, final_uv + ca_offset).r;
    float g = texture(screen_texture, final_uv).g;
    float b = texture(screen_texture, final_uv - ca_offset).b;
    vec3 col = vec3(r, g, b);

    // 4. 8x8 Bayer Ordered Dither
    ivec2 pixel_coord = ivec2(floor(uv * res));
    int bayer_index = (pixel_coord.y % 8) * 8 + (pixel_coord.x % 8);
    float dither_val = (bayer8[bayer_index] - 0.5) * (dither_intensity / color_depth);
    col += vec3(dither_val);

    // 5. Color Depth Reduction / 16-bit Style Posterization
    col = floor(col * color_depth + 0.5) / color_depth;

    // 6. Analog Sensor / CRT Grain (subtle and stable)
    if (grain_intensity > 0.001) {
        vec2 grain_seed = uv * res + vec2(sin(TIME * 30.0), cos(TIME * 20.0));
        float grain = (hash21(grain_seed) - 0.5) * grain_intensity * (1.0 + effective_glitch * 2.0);
        col += vec3(grain);
    }

    // 7. Intermittent Scanlines modulated by TIME & glitch_intensity
    if (scanline_intensity > 0.001 || effective_glitch > 0.01) {
        float dynamic_scanline_mult = scanline_intensity + (effective_glitch * 0.12 * (sin(TIME * 14.0) * 0.5 + 0.5));
        float scanline = sin(uv.y * res.y * 3.14159265) * 0.5 + 0.5;
        col *= (1.0 - (scanline * dynamic_scanline_mult));
    }

    // 8. Static burst snow during intense glitches approaching KM 77 (subtle & intermittent)
    if (effective_glitch > 0.15) {
        float snow = hash21(uv * res * 1.5 + vec2(TIME * 40.0, -TIME * 25.0));
        if (snow > (1.0 - effective_glitch * 0.20)) {
            col = mix(col, vec3(snow * 0.65), effective_glitch * 0.40);
        }
    }

    // 9. Gothic Sepulchral Noir Grading (obsidian-violet shadows, cold silver midtones, bone highlights)
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(luma), col, saturation);
    vec3 warm_light_color = col;
    float warm_chroma = max(warm_light_color.r, max(warm_light_color.g, warm_light_color.b))
        - min(warm_light_color.r, min(warm_light_color.g, warm_light_color.b));
    float warm_red_bias = smoothstep(0.05, 0.22, warm_light_color.r - warm_light_color.g * 0.78)
        * smoothstep(0.05, 0.20, warm_light_color.r - warm_light_color.b * 1.05);
    float warm_light_mask = warm_red_bias * smoothstep(0.08, 0.28, warm_chroma)
        * smoothstep(0.10, 0.34, warm_light_color.r);

    float noir_luma = clamp(dot(col, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
    // S-curve contrast for dramatic gothic chiaroscuro
    float gothic_contrast = smoothstep(0.02, 0.96, pow(noir_luma, 1.08));
    vec3 shadow_tint = vec3(0.018, 0.015, 0.028);   // Deep sepulchral violet-black
    vec3 mid_tint = vec3(0.44, 0.46, 0.54);         // Cold moonlight slate-silver
    vec3 highlight_tint = vec3(0.96, 0.93, 0.88);   // Pale bone / ivory highlight
    vec3 gothic_grade = mix(
        mix(shadow_tint, mid_tint, clamp(gothic_contrast * 2.0, 0.0, 1.0)),
        highlight_tint,
        clamp((gothic_contrast - 0.5) * 2.0, 0.0, 1.0)
    );
    col = mix(col, gothic_grade, noir_strength);

    // Preserve and enrich crimson blood/candlelight and gaslight amber through the Gothic grade
    vec3 crimson_boosted = vec3(warm_light_color.r * 1.12, warm_light_color.g * 0.92, warm_light_color.b * 0.85);
    col = mix(col, crimson_boosted, clamp(warm_light_mask * 1.15, 0.0, 1.0) * noir_strength);

    // 10. Subtle Gothic Cathedral Vignette around screen edges
    float vignette = 1.0 - smoothstep(0.42, 0.92, radial_dist) * 0.38;
    col *= vignette;

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
