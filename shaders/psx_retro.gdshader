shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform bool enable_pixelation = true;
uniform vec2 target_resolution = vec2(640.0, 360.0);
uniform float color_depth : hint_range(4.0, 64.0, 1.0) = 32.0;
uniform float dither_intensity : hint_range(0.0, 2.0, 0.05) = 0.42;
uniform float grain_intensity : hint_range(0.0, 0.2, 0.005) = 0.016;
uniform float scanline_intensity : hint_range(0.0, 0.5, 0.01) = 0.025;
uniform float chromatic_aberration : hint_range(0.0, 0.05, 0.0005) = 0.0008;
uniform float static_glitch_intensity : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float saturation : hint_range(0.5, 2.0, 0.05) = 1.15;

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
    float glitch_x = 0.0;
    if (effective_glitch > 0.001) {
        // Intermittent horizontal static bands modulated by TIME
        float band_wave = sin(uv.y * 42.0 + TIME * 19.0) * cos(uv.y * 84.0 - TIME * 13.0);
        float line_id = floor(uv.y * (res.y * 0.15));
        float tear_noise = hash21(vec2(line_id, floor(TIME * 24.0)));
        if (tear_noise > (1.0 - effective_glitch * 0.45)) {
            glitch_x = (tear_noise - 0.5) * 0.07 * effective_glitch;
        }
        if (abs(band_wave) > (1.0 - effective_glitch * 0.5)) {
            glitch_x += band_wave * 0.022 * effective_glitch;
        }
    }
    vec2 final_uv = uv + vec2(glitch_x, 0.0);

    // 3. Horizontal Chromatic Aberration + Radial Displacement
    float ca_amount = chromatic_aberration + (effective_glitch * 0.025);
    vec2 ca_h_offset = vec2(ca_amount, 0.0);
    vec2 ca_dir = (final_uv - vec2(0.5)) * (ca_amount * 0.7);
    // Displace R channel horizontally right, B channel horizontally left
    float r = texture(screen_texture, final_uv + ca_dir + ca_h_offset).r;
    float g = texture(screen_texture, final_uv).g;
    float b = texture(screen_texture, final_uv - ca_dir - ca_h_offset).b;
    vec3 col = vec3(r, g, b);

    // 4. 8x8 Bayer Ordered Dither
    ivec2 pixel_coord = ivec2(floor(uv * res));
    int bayer_index = (pixel_coord.y % 8) * 8 + (pixel_coord.x % 8);
    float dither_val = (bayer8[bayer_index] - 0.5) * (dither_intensity / color_depth);
    col += vec3(dither_val);

    // 5. Color Depth Reduction / 16-bit Style Posterization
    col = floor(col * color_depth + 0.5) / color_depth;

    // 6. Analog Sensor / CRT Grain
    if (grain_intensity > 0.001) {
        vec2 grain_seed = uv * res + vec2(sin(TIME * 45.0), cos(TIME * 30.0));
        float grain = (hash21(grain_seed) - 0.5) * grain_intensity * (1.0 + effective_glitch * 3.5);
        col += vec3(grain);
    }

    // 7. Intermittent Scanlines modulated by TIME & glitch_intensity
    if (scanline_intensity > 0.001 || effective_glitch > 0.01) {
        float dynamic_scanline_mult = scanline_intensity + (effective_glitch * 0.28 * (sin(TIME * 22.0) * 0.5 + 0.5));
        float scanline = sin(uv.y * res.y * 3.14159265 + (TIME * 5.0 * effective_glitch)) * 0.5 + 0.5;
        col *= (1.0 - (scanline * dynamic_scanline_mult));
    }

    // 8. Static burst snow during intense glitches approaching KM 77
    if (effective_glitch > 0.08) {
        float snow = hash21(uv * res * 2.0 + vec2(TIME * 60.0, -TIME * 40.0));
        if (snow > (1.0 - effective_glitch * 0.28)) {
            col = mix(col, vec3(snow * 0.85), effective_glitch * 0.65);
        }
    }

    // 9. Color saturation adjustment to preserve vivid accents through dither
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(luma), col, saturation);

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
