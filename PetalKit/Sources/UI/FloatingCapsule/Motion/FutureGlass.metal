#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Superellipse exponent of the corners. 2 is a circle; Apple-style continuous
// corners sit a little above it, which squares the capsule ends slightly.
constant float kSquircle = 2.15;
constant int kBands = 8;

static float sq(float x) { return x * x; }

static float superRadius(float2 c) {
    float2 a = max(c, 1e-5);
    return powr(powr(a.x, kSquircle) + powr(a.y, kSquircle), 1.0 / kSquircle);
}

// Approximate signed distance to a squircle-capped capsule with half size h.
static float squircle(float2 p, float2 h) {
    h = max(h, 1e-3);
    float r = min(h.x, h.y);
    float2 q = abs(p) - (h - r);
    return superRadius(max(q, 0.0)) - r + min(max(q.x, q.y), 0.0);
}

static float smoothUnion(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

struct Shapes {
    float4 pill;
    float4 secondary;
    float blend;
};

static float field(Shapes s, float2 p) {
    float a = squircle(p - s.pill.xy, s.pill.zw);
    if (s.secondary.z < 0.01) { return a; }
    return smoothUnion(a, squircle(p - s.secondary.xy, s.secondary.zw), s.blend);
}

static float2 fieldNormal(Shapes s, float2 p, float e) {
    float2 g = float2(field(s, p + float2(e, 0)) - field(s, p - float2(e, 0)),
                      field(s, p + float2(0, e)) - field(s, p - float2(0, e)));
    return g / max(length(g), 1e-5);
}

// Visible-light weights for a band s in [0, 1], red to violet.
static float3 spectrum(float s) {
    float r = exp(-sq((s - 0.12) / 0.22)) + 0.3 * exp(-sq((s - 0.98) / 0.12));
    float g = exp(-sq((s - 0.48) / 0.20));
    float b = exp(-sq((s - 0.80) / 0.20));
    return float3(r, g, b);
}

// 1 inside a shape's round end caps, 0 along its flat sides.
static float capWeight(float2 p, float4 shape) {
    float r = min(shape.z, shape.w);
    float2 q = abs(p - shape.xy) - (shape.zw - r);
    float along = shape.z >= shape.w ? q.x : q.y;
    return smoothstep(-1.0 * r, 0.15 * r, along);
}

static float bloom(float2 p, float4 shape, float2 spread) {
    float2 q = (p - shape.xy) / max(spread, 1e-3);
    return exp(-dot(q, q));
}

// The capsule floats over other apps and cannot read them, so the lens images
// a fixed light field instead: a dim violet room with two bright lines that
// cross under the glass, like the folded wallpaper of the original scene.
// The lines drift and breathe slowly (caustic.x = seconds), and brighten a
// little with the microphone level (caustic.y), so the caustic arcs shimmer.
static float3 environment(float2 p, float4 pill, float2 caustic) {
    float2 q = (p - pill.xy) / max(pill.w, 1e-3);
    float aspect = max(pill.z / pill.w, 1.0);
    float t = caustic.x;
    float drift = 0.035 * sin(t * 1.1) + 0.015 * sin(t * 2.3 + 1.7);
    float tilt = 0.10 + 0.05 * sin(t * 0.6 + 0.4);
    float breathe = 1.0 + 0.14 * sin(t * 1.6) + 0.30 * saturate(caustic.y);
    float lower = exp(-sq((q.y - 0.42 - drift + tilt * q.x / aspect) / 0.09));
    float upper = exp(-sq((q.y + 0.30 + 0.6 * drift - 0.18 * q.x / aspect) / 0.07));
    float3 room = float3(0.16, 0.15, 0.26) + float3(0.06, 0.05, 0.10) * q.y;
    return room + (float3(0.70, 0.70, 1.15) * lower + float3(0.55, 0.52, 0.90) * upper) * breathe;
}

struct Lens {
    float3 refracted;
    float band;
    float facing;
    float transmission;
};

// The end caps are domes: the slope steepens toward the rim and bends rays
// inward, so the rim shows the light field from deep under the glass. A line
// under the cap focuses a few points inside the rim into a bright caustic
// arc, and shorter wavelengths bend more, which splits the arc into a spectrum.
// Only the round end caps focus light, through a band in their lower shoulder.
static Lens endCapLens(float2 position, float2 n, float depth, Shapes shapes, float2 caustic) {
    float4 pill = shapes.pill;
    float4 secondary = shapes.secondary;
    float pillDistance = squircle(position - pill.xy, pill.zw);
    float secondaryDistance = secondary.z > 0.01 ? squircle(position - secondary.xy, secondary.zw) : 1e6;
    bool inPill = pillDistance < secondaryDistance;
    // Each shape's own thickness, so a drop that appears or leaves does not change the other's caustic.
    float thickness = min(inPill ? pill.w : secondary.w, 49.0);
    float shoulder = 0.55 * thickness;
    float slope = sq(saturate(1.0 - depth / shoulder));
    float lensDepth = 0.85 * thickness;
    float3 refracted = 0.0;
    float3 weight = 0.0;
    for (int i = 0; i < kBands; i++) {
        float s = (float(i) + 0.5) / float(kBands);
        float bend = 1.0 + 0.30 * (s - 0.5);
        float3 w = spectrum(s);
        refracted += environment(position - n * lensDepth * slope * bend, pill, caustic) * w;
        weight += w;
    }
    Lens lens;
    lens.refracted = refracted / weight;
    lens.band = exp(-sq((depth - 0.24 * thickness) / (0.11 * thickness)));
    lens.facing = powr(max(n.y, 0.0), 1.5);
    float cap = inPill ? capWeight(position, pill) : capWeight(position, secondary);
    lens.transmission = lens.band * cap * (0.06 + 0.90 * lens.facing);
    return lens;
}

static float3 causticHighlight(Lens lens) {
    return max(lens.refracted - 0.17, 0.0) * (0.9 + 1.6 * lens.band * lens.facing) * saturate(lens.transmission);
}

/// Dark liquid glass, drawn with premultiplied alpha over a transparent window.
///
/// - pill, secondary: centre (xy) and half size (zw) in points.
/// - optics: x = points per design point, y = smooth-union radius, z = visibility,
///   w = secondary bloom strength.
/// - ripple: centre (xy), age in seconds (z), strength (w).
/// - rippleHalf: half size of the shape that sent the ripple.
/// - glow: label bloom colour (rgb) and strength (a).
/// - canvas: drawable size, used to fade the ripple before it reaches the edges.
/// - caustic: x = shimmer time in seconds, y = audio level.
/// - hover: x = pointer over the stop drop, y = pointer over the Transcribe pill, each 0 to 1.
[[ stitchable ]] half4 petalFutureGlass(float2 position, half4 color,
                                        float4 pill, float4 secondary, float4 optics,
                                        float4 ripple, float2 rippleHalf, float4 glow, float2 canvas, float2 caustic, float2 hover) {
    float scale = optics.x;
    float line = max(scale, 0.8);
    Shapes shapes = { pill, secondary, optics.y };
    float sd = field(shapes, position);
    float near = 46.0 * scale;
    float visibility = optics.z;

    // Premultiplied colour of everything outside the glass: ripple and shadow.
    float4 outside = 0.0;

    // Ripple: a decaying wave packet that leaves the squircle that sent it.
    float age = ripple.z;
    if (ripple.w > 0.0 && age > 0.0 && age < 2.2) {
        float2 rp = position - ripple.xy;
        float rd = squircle(rp, rippleHalf);
        float front = 45.0 * (1.0 - exp(-age * 2.0)) * scale;
        float x = rd - front;
        float packet = exp(-sq(x / (20.0 * scale)));
        if (packet > 0.002) {
            float2 edge = min(position, canvas - position);
            float edgeFade = smoothstep(0.0, 18.0, min(edge.x, edge.y));
            float fade = exp(-age / 0.42) * smoothstep(0.0, 0.08, age) * ripple.w * edgeFade
                * smoothstep(0.0, 6.0 * scale, sd);
            float k = 6.2831853 / (13.0 * scale);
            float3 wave = float3(sin(x * k * 1.0 / 1.30), sin(x * k), sin(x * k * 1.0 / 0.72));
            float crest = max(wave.g, 0.0);
            float trough = max(-wave.g, 0.0);
            float3 fringe = saturate(0.65 + 0.35 * wave);
            float lightAlpha = 0.16 * crest * packet * fade;
            float darkAlpha = 0.10 * trough * packet * fade;
            outside = float4(fringe * lightAlpha, lightAlpha + darkAlpha);
        }
    }

    if (sd > near || visibility <= 0.0) {
        return half4(outside);
    }

    // Soft contact shadow under the glass.
    float shadowField = field(shapes, position - float2(0.0, 5.0 * scale));
    float shadow = 0.42 * exp(-max(shadowField, 0.0) / (9.0 * scale)) * visibility;
    shadow *= smoothstep(-1.0, 2.0 * scale, sd);
    outside = outside * (1.0 - shadow) + float4(0.0, 0.0, 0.0, shadow);

    float aa = max(0.6 * scale, 0.5);
    if (sd > aa) {
        return half4(outside);
    }

    float2 n = fieldNormal(shapes, position, 0.75 * scale);
    float depth = -sd;
    Lens lens = endCapLens(position, n, depth, shapes, caustic);

    // Thick dark glass: almost opaque, with a soft lift toward the base.
    float halfHeight = max(pill.w, 1e-3);
    float lower = smoothstep(0.0, 1.0, (position.y - pill.y) / halfHeight);
    float3 tint = float3(0.038, 0.032, 0.045);
    float3 darkBody = tint + float3(0.09, 0.08, 0.12) * lower;
    float3 body = mix(darkBody, lens.refracted, 0.25 * saturate(lens.transmission)) + causticHighlight(lens);

    // Bloom from the label inside the glass.
    // Hovering Transcribe brightens the label bloom; hovering Stop fills the drop with a red glow.
    float3 bloomColor = glow.rgb * bloom(position, pill, float2(pill.z * 0.56, pill.w * 0.38)) * glow.a
        * (1.0 + 0.8 * hover.y);
    float stopGlow = 0.0;
    if (secondary.z > 0.01) {
        float3 stopColor = mix(float3(0.17, 0.07, 0.11), float3(0.62, 0.05, 0.07), hover.x);
        float spread = mix(0.42, 0.66, hover.x);
        bloomColor += stopColor * bloom(position, secondary, secondary.zw * spread) * optics.w;
        float secondaryDistance = squircle(position - secondary.xy, secondary.zw);
        stopGlow = hover.x * smoothstep(2.0, -2.0, secondaryDistance - squircle(position - pill.xy, pill.zw));
    }
    body += bloomColor * smoothstep(0.0, 6.0 * scale, depth);

    // Rim light: a hairline with a cool key from the top left and a lift along the base.
    float key = max(dot(n, normalize(float2(-0.55, -0.85))), 0.0);
    float base = max(dot(n, float2(0.0, 1.0)), 0.0);
    float rim = exp(-sq((sd + 0.55 * line) / (0.55 * line)));
    float3 rimColor = mix(float3(0.80, 0.80, 0.86), float3(1.0, 0.42, 0.42), 0.7 * stopGlow)
        * (1.0 + 0.35 * hover.y * (1.0 - stopGlow));
    body += rimColor * rim * (0.20 + 0.30 * key + 0.50 * base);
    body += float3(0.10, 0.10, 0.13) * exp(-depth / (2.5 * line)) * (0.4 + key);

    float coverage = (1.0 - smoothstep(-aa, aa, sd)) * visibility;
    return half4(float4(body, 1.0) * coverage + outside * (1.0 - coverage));
}

/// Only the spectral caustic glints of the end caps, drawn with premultiplied
/// alpha over system Liquid Glass. Arguments match `petalFutureGlass`.
[[ stitchable ]] half4 petalGlassGlints(float2 position, half4 color,
                                        float4 pill, float4 secondary, float4 optics, float2 caustic) {
    float scale = optics.x;
    Shapes shapes = { pill, secondary, optics.y };
    float sd = field(shapes, position);
    float aa = max(0.6 * scale, 0.5);
    float thickness = min(pill.w, secondary.z > 0.01 ? secondary.w : pill.w);
    if (sd > aa || -sd > 0.6 * thickness || optics.z <= 0.0) {
        return half4(0.0h);
    }
    float2 n = fieldNormal(shapes, position, 0.75 * scale);
    Lens lens = endCapLens(position, n, -sd, shapes, caustic);
    float coverage = (1.0 - smoothstep(-aa, aa, sd)) * optics.z;
    float3 glint = causticHighlight(lens) * coverage * 1.15;
    return half4(half3(glint), half(saturate(max(glint.r, max(glint.g, glint.b)))));
}
