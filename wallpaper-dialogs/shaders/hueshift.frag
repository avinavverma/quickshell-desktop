#version 440
// Re-hues the picture toward `hue` while keeping its light/dark, and (via `spread`)
// some of its original colour variety: pink skin, the yellow ring and the blue heart
// all land on shades around the new colour. `amount` fades between original and new.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D maskTex;   // painted eye mask (alpha channel)
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float hue;       // target hue 0..1
    float sat;       // target saturation 0..1 (scales the picture's own)
    float spread;    // 0 = flat single hue, 1 = keep the original hue differences
    float baseHue;   // dominant hue of the picture (pink ~0.88)
    float amount;    // 0..1
    float useMask;   // 1 = restrict to the painted mask, 0 = whole patch
    float variety;   // 0 = pure accent colour (the picture's own pink cast removed), 1 = hue-shifted original
    vec4 tint;       // the accent colour itself
};

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
    vec4 t = texture(src, qt_TexCoord0);
    vec3 hsv = rgb2hsv(t.rgb);
    float dh = hsv.x - baseHue;
    dh -= floor(dh + 0.5);                       // wrap to -0.5 .. 0.5
    float h = fract(hue + dh * spread);
    float s = clamp(hsv.y * sat, 0.0, 1.0);
    vec3 shifted = hsv2rgb(vec3(h, s, hsv.z));
    // Colourise: keep only the picture's light/dark and paint it in the accent colour
    // (shadows -> dark accent, light areas -> the accent itself, glints -> a bit lighter), so the
    // original pink cast no longer leaks into the result.
    float L = pow(dot(t.rgb, vec3(0.299, 0.587, 0.114)), 1.15);
    vec3 acc = tint.rgb;
    // the accent sits at L = 0.72 (where the iris/heart live); only the brightest glints go toward white
    vec3 col = L < 0.72 ? mix(vec3(0.0), acc, L / 0.72) : mix(acc, vec3(1.0), (L - 0.72) / 0.28 * 0.55);
    vec3 result = mix(col, shifted, variety);
    float m = mix(1.0, texture(maskTex, qt_TexCoord0).a, useMask);
    fragColor = vec4(mix(t.rgb, result, amount * m), t.a) * qt_Opacity;
}
