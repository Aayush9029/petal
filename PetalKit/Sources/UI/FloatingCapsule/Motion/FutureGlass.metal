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
// Before a delete (caustic.z) the light turns red.
static float3 environment(float2 p, float4 pill, float4 caustic) {
    float2 q = (p - pill.xy) / max(pill.w, 1e-3);
    float aspect = max(pill.z / pill.w, 1.0);
    float t = caustic.x;
    float danger = saturate(caustic.z);
    float drift = 0.035 * sin(t * 1.1) + 0.015 * sin(t * 2.3 + 1.7);
    float tilt = 0.10 + 0.05 * sin(t * 0.6 + 0.4);
    float breathe = 1.0 + 0.14 * sin(t * 1.6) + 0.30 * saturate(caustic.y);
    float lower = exp(-sq((q.y - 0.42 - drift + tilt * q.x / aspect) / 0.09));
    float upper = exp(-sq((q.y + 0.30 + 0.6 * drift - 0.18 * q.x / aspect) / 0.07));
    float3 room = mix(float3(0.16, 0.15, 0.26), float3(0.22, 0.10, 0.11), danger)
        + float3(0.06, 0.05, 0.10) * q.y;
    float3 lowerLight = mix(float3(0.70, 0.70, 1.15), float3(1.25, 0.34, 0.36), danger);
    float3 upperLight = mix(float3(0.55, 0.52, 0.90), float3(1.00, 0.30, 0.32), danger);
    return room + (lowerLight * lower + upperLight * upper) * breathe;
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
static Lens endCapLens(float2 position, float2 n, float depth, Shapes shapes, float4 caustic) {
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

// Position along the rim of a wide capsule in turns, clockwise from the right end.
// Callers compare it with fract(), so the loop has no seam where it wraps from 1 to 0.
static float rimTurns(float2 p, float4 pill) {
    float2 q = p - pill.xy;
    float r = max(min(pill.z, pill.w), 1e-3);
    float straight = max(pill.z - pill.w, 0.0);
    float perimeter = 4.0 * straight + 6.2831853 * r;
    float s;
    if (q.x >= straight) {
        s = r * atan2(q.y, q.x - straight);
    } else if (q.x <= -straight) {
        s = 1.5707963 * r + 2.0 * straight + r * (1.5707963 - atan2(q.y, -(q.x + straight)));
    } else if (q.y >= 0.0) {
        s = 1.5707963 * r + (straight - q.x);
    } else {
        s = 4.7123890 * r + 2.0 * straight + (q.x + straight);
    }
    return fract(s / perimeter);
}

// Brightness of the highlight that orbits the rim while the capsule processes:
// a bright head with a soft comet tail. orbit: x = head in turns, y = strength,
// z = 1 for an even, still glow (Reduce Motion).
static float orbitLight(float2 p, float4 pill, float4 orbit) {
    if (orbit.y <= 0.001) { return 0.0; }
    if (orbit.z > 0.5) { return 0.45 * orbit.y; }
    float d = fract(rimTurns(p, pill) - orbit.x + 0.5) - 0.5;
    float head = exp(-sq(d / 0.035));
    float tail = d < 0.0 ? exp(d / 0.16) * 0.55 : 0.0;
    return max(head, tail) * orbit.y;
}

static float hash11(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

constant int kDroplets = 16;

// A discarded recording: small glass droplets fly out of the shapes and fade.
// Dark beads match the Future glass; clear beads match system glass.
static float4 burstDroplets(float2 p, float4 pill, float4 secondary, float age, bool clearBeads) {
    float4 result = 0.0;
    float life = (1.0 - smoothstep(0.20, 0.50, age)) * smoothstep(0.0, 0.06, age);
    if (life <= 0.0) { return result; }
    float travel = 1.0 - exp(-age * 7.0);
    bool hasSecondary = secondary.z > 0.01;
    for (int i = 0; i < kDroplets; i++) {
        float fi = float(i);
        bool fromSecondary = hasSecondary && i >= 11;
        float4 shape = fromSecondary ? secondary : pill;
        float count = fromSecondary ? 5.0 : (hasSecondary ? 11.0 : 16.0);
        float k = fromSecondary ? fi - 11.0 : fi;
        float a = 6.2831853 * (k + 0.5 + 0.35 * (hash11(fi + 1.7) - 0.5)) / count;
        float2 around = float2(cos(a), sin(a));
        float2 dir = normalize(around / max(shape.zw, 1e-3));
        float2 start = shape.xy + around * shape.zw * 0.8;
        float reach = 14.0 + 22.0 * hash11(fi * 3.1);
        float2 c = start + dir * reach * travel + float2(0.0, 14.0 * age * age);
        float radius = (2.6 + 3.0 * hash11(fi * 7.3)) * (1.0 - smoothstep(0.20, 0.50, age));
        float sd = length(p - c) - radius;
        if (sd > 1.0) { continue; }
        float coverage = (1.0 - smoothstep(-0.5, 0.5, sd)) * life;
        float2 n = (p - c) / max(radius, 1e-3);
        float rimLight = exp(-sq((sd + 0.45) / 0.45));
        float spec = smoothstep(0.35, 0.0, length(n - float2(-0.35, -0.4)));
        float3 bead;
        if (clearBeads) {
            bead = float3(0.92, 0.88, 0.90) * 0.35 + float3(1.0, 0.45, 0.47) * rimLight * 0.7 + float3(1.0) * spec * 0.7;
            coverage *= 0.7;
        } else {
            bead = float3(0.10, 0.03, 0.04) + float3(1.0, 0.40, 0.42) * rimLight * 0.8 + float3(0.9) * spec * 0.6;
        }
        result = float4(bead, 1.0) * coverage + result * (1.0 - coverage);
    }
    return result;
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
/// - caustic: x = shimmer time in seconds, y = audio level, z = delete red, w = highlight strength.
/// - hover: x = pointer over the stop drop, y = pointer over the Transcribe pill, each 0 to 1.
/// - orbit: the processing highlight, see `orbitLight`.
/// - burst: x = seconds since the glass popped, y = 1 while it bursts, z = 1 for clear droplets.
[[ stitchable ]] half4 petalFutureGlass(float2 position, half4 color,
                                        float4 pill, float4 secondary, float4 optics,
                                        float4 ripple, float2 rippleHalf, float4 glow, float2 canvas,
                                        float4 caustic, float2 hover, float4 orbit, float4 burst) {
    float scale = optics.x;
    float line = max(scale, 0.8);
    Shapes shapes = { pill, secondary, optics.y };
    float sd = field(shapes, position);
    float near = 46.0 * scale;
    float visibility = optics.z;
    float danger = saturate(caustic.z);
    float highlightStrength = caustic.w;

    // Premultiplied colour of everything outside the glass: ripple, droplets, and shadow.
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

    if (burst.y > 0.5) {
        float4 droplets = burstDroplets(position, pill, secondary, burst.x, burst.z > 0.5);
        outside = droplets + outside * (1.0 - droplets.a);
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
    float3 body = mix(darkBody, lens.refracted, 0.25 * saturate(lens.transmission))
        + causticHighlight(lens) * highlightStrength;

    // Bloom from the label inside the glass.
    // Hovering Transcribe brightens the label bloom; hovering Stop fills the drop with a red glow.
    float3 bloomColor = glow.rgb * bloom(position, pill, float2(pill.z * 0.56, pill.w * 0.38)) * glow.a
        * (1.0 + 0.8 * hover.y);
    float stopGlow = 0.0;
    if (secondary.z > 0.01) {
        float3 stopColor = mix(float3(0.17, 0.07, 0.11), float3(0.50, 0.05, 0.07), hover.x);
        float spread = mix(0.42, 0.58, hover.x);
        bloomColor += stopColor * bloom(position, secondary, secondary.zw * spread) * optics.w;
        float secondaryDistance = squircle(position - secondary.xy, secondary.zw);
        stopGlow = hover.x * smoothstep(2.0, -2.0, secondaryDistance - squircle(position - pill.xy, pill.zw));
    }
    body += bloomColor * smoothstep(0.0, 6.0 * scale, depth);

    // Rim light: a hairline with a cool key from the top left and a lift along the base.
    float key = max(dot(n, normalize(float2(-0.55, -0.85))), 0.0);
    float base = max(dot(n, float2(0.0, 1.0)), 0.0);
    float rim = exp(-sq((sd + 0.55 * line) / (0.55 * line)));
    float3 rimColor = mix(float3(0.80, 0.80, 0.86), float3(1.0, 0.42, 0.42), max(0.7 * stopGlow, 0.6 * danger))
        * (1.0 + 0.35 * hover.y * (1.0 - stopGlow));
    body += rimColor * rim * (0.20 + 0.30 * key + 0.50 * base);
    body += float3(0.10, 0.10, 0.13) * exp(-depth / (2.5 * line)) * (0.4 + key);

    // The processing highlight runs in a band just inside the rim.
    float orbitBand = exp(-sq((depth - 1.8 * line) / (1.6 * line))) + 0.25 * exp(-depth / (7.0 * line));
    float3 orbitColor = mix(float3(0.62, 0.50, 1.30), float3(1.20, 0.36, 0.40), danger);
    body += orbitColor * orbitLight(position, pill, orbit) * orbitBand * highlightStrength;

    float coverage = (1.0 - smoothstep(-aa, aa, sd)) * visibility;
    return half4(float4(body, 1.0) * coverage + outside * (1.0 - coverage));
}

/// The rim and spectral end cap glints of the Future glass, drawn with premultiplied
/// alpha over system Liquid Glass. Arguments match `petalFutureGlass`. The rim adds a
/// light hairline that faces the key light and a faint shade that faces away from it,
/// so the system glass gets the same depth.
[[ stitchable ]] half4 petalGlassGlints(float2 position, half4 color,
                                        float4 pill, float4 secondary, float4 optics, float4 caustic) {
    float scale = optics.x;
    float line = max(scale, 0.8);
    Shapes shapes = { pill, secondary, optics.y };
    float sd = field(shapes, position);
    float aa = max(0.6 * scale, 0.5);
    float thickness = min(pill.w, secondary.z > 0.01 ? secondary.w : pill.w);
    if (sd > 2.0 * line || -sd > 0.6 * thickness || optics.z <= 0.0) {
        return half4(0.0h);
    }
    float2 n = fieldNormal(shapes, position, 0.75 * scale);
    float depth = -sd;
    float coverage = (1.0 - smoothstep(-aa, aa, sd)) * optics.z;

    float3 light = 0.0;
    if (sd <= aa) {
        Lens lens = endCapLens(position, n, depth, shapes, caustic);
        light = causticHighlight(lens) * caustic.w;
    }

    float key = max(dot(n, normalize(float2(-0.55, -0.85))), 0.0);
    float away = max(dot(n, normalize(float2(0.55, 0.85))), 0.0);
    float base = max(dot(n, float2(0.0, 1.0)), 0.0);
    float rim = exp(-sq((sd + 0.55 * line) / (0.55 * line)));
    float3 rimColor = mix(float3(0.92, 0.92, 0.98), float3(1.0, 0.5, 0.5), 0.6 * saturate(caustic.z));
    light += rimColor * rim * (0.22 + 0.45 * key + 0.30 * base) * 0.85;
    light += float3(0.85, 0.85, 0.92) * exp(-depth / (2.5 * line)) * key * 0.10;
    light *= coverage;

    // A soft shade along the rim that faces away from the light.
    float shade = 0.16 * exp(-sq((sd + 0.9 * line) / (0.9 * line))) * away * optics.z;
    float lightAlpha = saturate(max(light.r, max(light.g, light.b)));
    return half4(half3(light), half(saturate(lightAlpha + shade * (1.0 - lightAlpha))));
}
