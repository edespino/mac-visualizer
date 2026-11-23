#include <metal_stdlib>
using namespace metal;

// Must match BarVertex in Swift: two float4s, stride 32 bytes.
struct Vertex {
    float4 position; // xy = clip space
    float4 color;    // rgba
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;       // local quad UV in [-1, +1], derived from vid % 6
};

// Local-quad UVs for the 6-vertex pattern visualizers use to emit a quad:
// [bl, br, tl, br, tr, tl].
constant float2 kQuadUV[6] = {
    float2(-1, -1), float2( 1, -1), float2(-1,  1),
    float2( 1, -1), float2( 1,  1), float2(-1,  1)
};

vertex VertexOut vs_main(const device Vertex *verts [[buffer(0)]],
                         uint vid [[vertex_id]]) {
    VertexOut out;
    out.position = float4(verts[vid].position.xy, 0.0, 1.0);
    out.color = verts[vid].color;
    out.uv = kQuadUV[vid % 6];
    return out;
}

// Sharp pass: used by bars / radial / mirrored / oscilloscope. UV is ignored.
// `brightness` is the global output dimmer. It is bound here too because the
// no-glow / no-trail geometry path writes straight to the drawable and never
// reaches composite_fs.
fragment float4 fs_main(VertexOut in [[stage_in]],
                        constant float &brightness [[buffer(0)]]) {
    return float4(in.color.rgb * brightness, in.color.a);
}

// Round pass: used by particles / fountain / fireworks. Soft circular mask
// inside the emitted quad — corners fade to black so the visible spark is a
// soft dot instead of a hard square.
fragment float4 fs_round(VertexOut in [[stage_in]],
                         constant float &brightness [[buffer(0)]]) {
    float d = length(in.uv);
    float mask = 1.0 - smoothstep(0.65, 1.0, d);
    if (mask <= 0.001) discard_fragment();
    return float4(in.color.rgb * mask * brightness, 1.0);
}

// ---- Bloom post-processing ----
struct FSQOut {
    float4 position [[position]];
    float2 uv;
};

// Fullscreen triangle from vertex_id (no vertex buffer).
vertex FSQOut fullscreen_vs(uint vid [[vertex_id]]) {
    FSQOut out;
    float2 uv = float2(float((vid << 1) & 2), float(vid & 2)); // (0,0),(2,0),(0,2)
    out.uv = uv;
    out.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return out;
}

struct CompositeUniforms {
    float intensity;
    float vignetteAmount;
    float time;
    int kaleidoscopeFolds;     // 0 = off; 2..12 = N-fold mirror
    float perPixelAlphaMode;   // 0 = opaque output, 1 = per-pixel alpha
    float brightness;          // global output dimmer; 1 = full brightness
};

fragment float4 composite_fs(FSQOut in [[stage_in]],
                             texture2d<float> sceneTex [[texture(0)]],
                             texture2d<float> blurTex  [[texture(1)]],
                             sampler samp              [[sampler(0)]],
                             constant CompositeUniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;

    // Kaleidoscope: fold the UV across N rotational symmetry segments around
    // the screen center. With folds = 0, the UV passes through unchanged.
    if (u.kaleidoscopeFolds > 0) {
        float2 c = uv - 0.5;
        float r = length(c);
        float angle = atan2(c.y, c.x);
        float foldAngle = (2.0 * M_PI_F) / float(u.kaleidoscopeFolds);
        float a = fmod(angle + 2.0 * M_PI_F, foldAngle);
        if (a > foldAngle * 0.5) a = foldAngle - a;
        uv = float2(cos(a) * r, sin(a) * r) + 0.5;
    }

    float3 scene = sceneTex.sample(samp, uv).rgb;
    float3 blur  = blurTex.sample(samp, uv).rgb;
    float3 color = scene + blur * u.intensity;

    if (u.vignetteAmount > 0.0) {
        float rv = length(in.uv * 2.0 - 1.0);
        float v = 1.0 - u.vignetteAmount * smoothstep(0.55, 1.1, rv);
        color *= v;
    }

    // Alpha is derived from the UNDIMMED color so the dimmer darkens the
    // visuals without also making the window punch through in per-pixel-alpha
    // mode. Dimming happens before the drawable's implicit [0,1] clamp, so HDR
    // palette highlights resolve into range instead of staying blown out.
    float outAlpha = mix(1.0, max(max(color.r, color.g), color.b), u.perPixelAlphaMode);
    // PerPixelAlphaMode == 2 means the active shader supplies its own
    // coverage in the scene alpha channel; keep it (max with the brightness alpha).
    if (u.perPixelAlphaMode > 1.5) {
        outAlpha = max(max(max(color.r, color.g), color.b), sceneTex.sample(samp, uv).a);
    }
    return float4(color * u.brightness, outAlpha);
}

// Fade pass for the trail-persistence pipeline. Outputs a precomputed
// "fade additive" color (bg * (1 - persistence)). Combined with a blend
// equation `dst = src + dst * blendColor`, where `blendColor = persistence`,
// the trail texture math becomes:
//   trailTex = bg*(1-persistence) + trailTex*persistence
// i.e. it lerps the existing trail toward the bg by (1 - persistence)
// per frame. When persistence == 0, the trail clears to bg each frame
// (identical to today's behavior with the existing clearColor).
fragment float4 fade_fs(FSQOut in [[stage_in]],
                        constant float4 &fadeRGBA [[buffer(0)]]) {
    return fadeRGBA;
}

// ============================================================================
// Shader-driven visualizers (plasma, bumpscope)
// ============================================================================

struct ShaderInputs {
    float time;
    float energy;
    float bands[16];
};

struct PaletteStopUniform {
    float r;
    float g;
    float b;
    float position;
};

struct PaletteUniform {
    PaletteStopUniform stops[8];
    int stopCount;
};

// Linearly sample the palette at t in [0,1]. Stops are treated as evenly
// distributed across [0,1] regardless of their `position` field (matches the
// Swift ColorPalette.sample semantics).
static inline float3 samplePalette(constant PaletteUniform &p, float t) {
    t = clamp(t, 0.0, 1.0);
    int n = p.stopCount;
    if (n <= 1) {
        return float3(p.stops[0].r, p.stops[0].g, p.stops[0].b);
    }
    float scaled = t * float(n - 1);
    int lo = (int)floor(scaled);
    if (lo < 0) lo = 0;
    if (lo > n - 2) lo = n - 2;
    int hi = lo + 1;
    float u = scaled - float(lo);
    PaletteStopUniform a = p.stops[lo];
    PaletteStopUniform b = p.stops[hi];
    return float3(a.r + (b.r - a.r) * u,
                  a.g + (b.g - a.g) * u,
                  a.b + (b.b - a.b) * u);
}

// User-tunable Plasma parameters. Field order/types MUST match the Swift
// PlasmaUniforms struct (Sources/Core/PlasmaUniforms.swift): 15 × float, tightly
// packed (stride 60). Each field is a prior hardcoded literal in plasma_fs;
// defaults reproduce the original look byte-for-byte.
struct PlasmaUniforms {
    float coordinateScale;
    float coordinateOffset;
    float xFrequency;
    float yFrequency;
    float diagonalFrequency;
    float xTimeScale;
    float yTimeScale;
    float diagonalTimeScale;
    float waveDivisor;
    float contrast;
    float brightnessBias;
    float energyResponse;
    float clampMin;
    float clampMax;
    float alpha;
};

fragment float4 plasma_fs(FSQOut in [[stage_in]],
                          constant ShaderInputs &input [[buffer(0)]],
                          constant PaletteUniform &palette [[buffer(1)]],
                          constant PlasmaUniforms &u [[buffer(2)]]) {
    float2 uv = in.uv * u.coordinateScale - u.coordinateOffset;
    float t = input.time;
    float v = sin(uv.x * u.xFrequency + t * u.xTimeScale)
            + sin(uv.y * u.yFrequency + t * u.yTimeScale)
            + sin((uv.x + uv.y) * u.diagonalFrequency + t * u.diagonalTimeScale);
    v = v / u.waveDivisor * u.contrast + u.brightnessBias + input.energy * u.energyResponse;
    v = clamp(v, u.clampMin, u.clampMax);
    return float4(samplePalette(palette, v), u.alpha);
}

// User-tunable Bumpscope parameters. Field order/types MUST match the Swift
// BumpscopeUniforms struct (Sources/Core/BumpscopeUniforms.swift): 14 × float
// interleaved with 1 × int, every field 4 bytes / 4-aligned, tightly packed
// (stride 60). Each field is a prior hardcoded literal in bumpscope_fs;
// defaults reproduce the original look byte-for-byte.
struct BumpscopeUniforms {
    float uvClampMin;
    float uvClampMax;
    int neighborRadius;
    float slopeScale;
    float surfaceNormalY;
    float surfaceNormalZ;
    float lightX;
    float lightY;
    float lightZ;
    float diffuseFloor;
    float bandGain;
    float intensityBias;
    float intensityClampMin;
    float intensityClampMax;
    float alpha;
};

fragment float4 bumpscope_fs(FSQOut in [[stage_in]],
                             constant ShaderInputs &input [[buffer(0)]],
                             constant PaletteUniform &palette [[buffer(1)]],
                             constant BumpscopeUniforms &u [[buffer(2)]]) {
    float ux = clamp(in.uv.x, u.uvClampMin, u.uvClampMax);
    int xi = (int)(ux * 15.0);
    if (xi < 0) xi = 0;
    if (xi > 15) xi = 15;
    // Keep xi ± radius inside the fixed bands[16] domain (radius itself is
    // already clamped to 0...15 in the Swift builder).
    int xL = (xi - u.neighborRadius >= 0) ? xi - u.neighborRadius : 0;
    int xR = (xi + u.neighborRadius <= 15) ? xi + u.neighborRadius : 15;
    float h  = input.bands[xi];
    float hL = input.bands[xL];
    float hR = input.bands[xR];
    float dx = (hR - hL) * u.slopeScale;
    // Normalize-of-zero guards: the exposed surface-normal and light vectors can
    // be hand-edited to ~zero, where normalize() is undefined. Fall back to the
    // default directions. Defaults are nonzero, so both guards are inert at
    // defaults and the look is unchanged.
    float3 nv = float3(-dx, u.surfaceNormalY, u.surfaceNormalZ);
    float3 n = (length(nv) < 1e-6) ? float3(0.0, 1.0, 0.0) : normalize(nv);
    float3 lv = float3(u.lightX, u.lightY, u.lightZ);
    float3 L = (length(lv) < 1e-6) ? normalize(float3(0.5, 0.7, 0.5)) : normalize(lv);
    float lit = max(u.diffuseFloor, dot(n, L));
    float intensity = clamp(lit * (h * u.bandGain + u.intensityBias), u.intensityClampMin, u.intensityClampMax);
    return float4(samplePalette(palette, intensity), u.alpha);
}

// ---- LavaLamp shader ----

constant int kLavaLampPointCount = 24;       // point capacity (active count via lava.pointCount)
constant int kLavaLampThresholdCount = 4;

struct LavaLampUniforms {
    float4 pointsAndAmps[kLavaLampPointCount];  // xy = position NDC, z = amplitude, w = unused
    float thresholds[kLavaLampThresholdCount];  // retained, unused by this shader
    float tolerance;                            // retained, unused by this shader
    float beatBoost;
    float densityFalloff;       // Gaussian density falloff K (exp(-r2 * K))
    float brightnessResponse;   // density->brightness response
    float paletteDensityScale;  // density->palette level
    int pointCount;             // active metaball count (<= kLavaLampPointCount)
};

fragment float4 lavalamp_fs(FSQOut in [[stage_in]],
                             constant ShaderInputs &input [[buffer(0)]],
                             constant PaletteUniform &palette [[buffer(1)]],
                             constant LavaLampUniforms &lava [[buffer(2)]]) {
    // in.uv.y = 0 at top of screen (per fullscreen_vs convention); negate Y so
    // uv.y = +1 at top, -1 at bottom, matching the NDC convention used by the
    // marching-squares cell emission path.
    float2 uv = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    // Bounded Gaussian density. Each point contributes `amp * exp(-r² * K)`.
    // With K=8.0 (sigma ≈ 0.35), a single point with amp=1 contributes ~1.0
    // at its center, falling to ~0.13 at r=0.5. Total density for 12 points
    // typically lies in [0, 4] depending on amplitudes and overlap.
    float density = 0.0;
    for (int i = 0; i < lava.pointCount; ++i) {
        float2 d = uv - lava.pointsAndAmps[i].xy;
        float r2 = dot(d, d);
        density += lava.pointsAndAmps[i].z * exp(-r2 * lava.densityFalloff);
    }
    // Continuous brightness: 0 at zero density, climbing smoothly with density.
    // Soft-clip so very dense regions saturate but don't blow out.
    float brightness = 1.0 - exp(-density * lava.brightnessResponse);   // 0 at density=0
    float level = clamp(density * lava.paletteDensityScale, 0.0, 1.0);
    float3 base = samplePalette(palette, level);
    return float4(base * brightness * (1.0 + lava.beatBoost), 1.0);
}

// ---- Voronoi blobs shader ----

// Seed array capacity (raised from the original 75 so the seed-count slider can
// grow without changing the buffer layout). `activeCount` is the live loop bound
// driven by `voronoiSeedCount`; default 75 loops the first 75 slots — identical
// to the prior fixed-75 shader. MUST match `kVoronoiSeedCapacity` in Core's
// VoronoiUniforms.swift.
constant int kVoronoiSeedCount = 128;

struct VoronoiUniforms {
    float4 seedsAndBands[kVoronoiSeedCount];  // xy = seed position in NDC, z = band level, w = unused
    float K;                                   // edge sharpness; higher = sharper cells
    float beatBoost;                           // 0..1 added brightness
    float fadeBrightness;                      // 0..1 fade-to-black multiplier (1 = full, 0 = black)
    int activeCount;                           // live seed count (loop bound), 1..capacity
};

fragment float4 voronoi_fs(FSQOut in [[stage_in]],
                            constant ShaderInputs &input [[buffer(0)]],
                            constant PaletteUniform &palette [[buffer(1)]],
                            constant VoronoiUniforms &voronoi [[buffer(2)]]) {
    float2 uv = in.uv * 2.0 - 1.0;
    // Find the two nearest seeds by squared distance.
    float minDist2 = 1e9;
    float secondDist2 = 1e9;
    int nearestIdx = 0;
    for (int i = 0; i < voronoi.activeCount; ++i) {
        float2 d = uv - voronoi.seedsAndBands[i].xy;
        float d2 = dot(d, d);
        if (d2 < minDist2) {
            secondDist2 = minDist2;
            minDist2 = d2;
            nearestIdx = i;
        } else if (d2 < secondDist2) {
            secondDist2 = d2;
        }
    }
    // Edge factor: when the nearest and second-nearest distances are close,
    // we're on an edge. K controls the falloff width.
    float dEdge = sqrt(secondDist2) - sqrt(minDist2);
    float edgeFactor = 1.0 - exp(-voronoi.K * dEdge);   // 0 at edges, →1 at cell centers

    float level = clamp(voronoi.seedsAndBands[nearestIdx].z, 0.0, 1.0);
    float4 baseColor = float4(samplePalette(palette, level), 1.0);
    float brightness = (1.0 + voronoi.beatBoost) * edgeFactor * voronoi.fadeBrightness;
    return float4(baseColor.rgb * brightness, 1.0);
}

// ---- Octave Meatballs shader ----
// OctaveMeatballs: ported to Metal from "Metaball octaves" by Justas Dabrila,
// CC BY 4.0, https://www.shadertoy.com/view/WlXSzn
// Changes were made: GLSL translated to Metal Shading Language; made
// audio-reactive (per-octave ring brightness, spin, and outward drift driven
// by FFT bands + RMS energy); recoloured through the app palette; the
// derivative (fwidth) term replaced with an analytic radial approximation so
// no GL_OES_standard_derivatives dependency is needed; octave count reduced
// for real-time performance.

// GLSL mod(x,y) is always non-negative for positive y; MSL fmod takes the sign
// of x. This reproduces the GLSL behaviour the original pattern relies on.
static inline float positiveMod(float x, float y) {
    return x - y * floor(x / y);
}

// User-tunable Octave Meatballs values. Field order/types MUST match the Swift
// OctaveMeatballsUniforms struct (Sources/Core/OctaveMeatballsUniforms.swift):
// 29 floats then 1 int, so the layout is padding-free.
struct OctaveMeatballsUniforms {
    float scale;
    float ballDivisor;
    float backgroundR;
    float backgroundG;
    float backgroundB;
    float octavePhase;
    float shimmerOctaveScale;
    float shimmerTimeScale;
    float lifeTimeScale;
    float pulseEdge0;
    float pulseEdge1;
    float lifeOctaveScale;
    float lifeDenomBase;
    float lifeDenomRadius;
    float lifeDenomScale;
    float distanceFloor;
    float ballStrength;
    float ballBase;
    float redGlowR;
    float redGlowG;
    float redGlowB;
    float paletteFieldGain;
    float paletteGain;
    float bandPhase;
    float bandBrightness;
    float energyBrightness;
    float paletteEnergy;
    float offsetX;
    float offsetY;
    int octaves;
};

fragment float4 octave_meatballs_fs(FSQOut in [[stage_in]],
                                    constant ShaderInputs &input [[buffer(0)]],
                                    constant PaletteUniform &palette [[buffer(1)]],
                                    constant OctaveMeatballsUniforms &u [[buffer(2)]]) {
    // The pattern is radially symmetric, so the fullscreen_vs flipped-Y
    // convention is harmless here. A content offset shifts the whole field
    // (background included) and discards the uncovered window, so the
    // background does not stay painted edge to edge when the picture moves.
    float2 clip = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    float2 src = clip - float2(u.offsetX, u.offsetY);
    if (src.x < -1.0 || src.x > 1.0 || src.y < -1.0 || src.y > 1.0) {
        discard_fragment();
    }
    float2 uv = float2(src.x, -src.y);

    float t = input.time;
    float energy = input.energy;

    float scale = u.scale;
    uv *= scale;

    float div = u.ballDivisor;
    int octaves = u.octaves;

    float l = length(uv);
    float baseAngle = atan2(uv.y, uv.x);

    float3 color = float3(u.backgroundR, u.backgroundG, u.backgroundB);
    float allBalls = 0.0;

    for (int octave = 0; octave < octaves; ++octave) {
        float fOctave = float(octave + 1);
        // Spread the spectrum across the rings: inner octaves take low bands,
        // outer octaves take high bands.
        int band = (octave * 16) / octaves;
        if (band > 15) band = 15;
        float bandAmp = input.bands[band];

        float numBalls = div * fOctave;
        float angularDivisor = (2.0 * M_PI_F) * (1.0 / numBalls);
        // Per-octave rotation; band energy nudges each ring's phase so the
        // pattern shimmers with the music.
        float uvAngle = baseAngle
                      + (2.0 * M_PI_F) * u.octavePhase * fOctave
                      + sin(float(octave) * u.shimmerOctaveScale * t * u.shimmerTimeScale)
                      + bandAmp * u.bandPhase;
        float angle = abs(positiveMod(uvAngle, angularDivisor) - angularDivisor * 0.5);
        float2 p = float2(cos(angle), sin(angle)) * l;

        // Outward travel of the metaballs over time. The original divided by a
        // screen-space derivative (fwidth); approximate that with a radial term
        // so the effect needs no derivative extension. Energy speeds the drift.
        float lifeT = fract(t * u.lifeTimeScale + smoothstep(u.pulseEdge0, u.pulseEdge1, abs(sin(t))) * fOctave * u.lifeOctaveScale);
        lifeT /= (u.lifeDenomBase + l * u.lifeDenomRadius) * u.lifeDenomScale;
        float2 mbPos = p + float2(-1.0, 0.0) * lifeT * scale;
        float mb = 1.0 / max(length(mbPos), u.distanceFloor) * fOctave * u.ballStrength;
        // Audio weighting: bands modulate per-ring brightness, energy lifts all.
        mb *= (u.ballBase + bandAmp * u.bandBrightness + energy * u.energyBrightness);

        color += float3(u.redGlowR, u.redGlowG, u.redGlowB) * mb * (1.0 - lifeT);
        allBalls += mb;
    }

    allBalls /= float(octaves);
    // Recolour the accumulated metaball field through the app palette so the
    // visualizer follows the active theme instead of the original fixed blue.
    float level = clamp(allBalls * u.paletteFieldGain + energy * u.paletteEnergy, 0.0, 1.0);
    color += samplePalette(palette, level) * allBalls * u.paletteGain;

    return float4(color, 1.0);
}

// ---- Star Nest shader ----
// StarNest: ported to Metal from "Star Nest" by Pablo Roman Andrioli.
// This content is under the MIT License.
// Source: https://www.shadertoy.com/view/XlfGRj
// Changes were made: GLSL translated to MSL and made audio-reactive.

// User-tunable Star Nest resting values. Field order/types MUST match the
// Swift StarNestUniforms struct (Sources/Core/StarNestUniforms.swift). Each
// scalar is the resting `base`; the audio modulation is applied on top below.
struct StarNestUniforms {
    float zoom;
    float speed;
    float formuparam;
    float tile;
    float stepsize;
    float brightness;
    float darkmatter;
    float distfading;
    float saturation;
    int volsteps;
    int iterations;
};

fragment float4 star_nest_fs(FSQOut in [[stage_in]],
                             constant ShaderInputs &input [[buffer(0)]],
                             constant PaletteUniform &palette [[buffer(1)]],
                             constant StarNestUniforms &u [[buffer(2)]]) {
    float energy = clamp(input.energy, 0.0, 1.5);
    float bass = clamp((input.bands[0] + input.bands[1] + input.bands[2] + input.bands[3]) * 0.25, 0.0, 1.5);
    float lowMid = clamp((input.bands[4] + input.bands[5] + input.bands[6] + input.bands[7]) * 0.25, 0.0, 1.5);
    float highMid = clamp((input.bands[8] + input.bands[9] + input.bands[10] + input.bands[11]) * 0.25, 0.0, 1.5);
    float treble = clamp((input.bands[12] + input.bands[13] + input.bands[14] + input.bands[15]) * 0.25, 0.0, 1.5);

    float2 uv = in.uv - 0.5;
    uv.y *= 0.5625;

    float zoom = u.zoom + bass * 0.22 - treble * 0.08;
    float3 dir = normalize(float3(uv * zoom, 0.85 + energy * 0.12));
    float time = input.time * (u.speed + energy * 0.08) + 0.25;

    float a1 = 0.50 + sin(input.time * 0.09 + lowMid * 1.7) * 0.24;
    float a2 = 0.82 + cos(input.time * 0.07 + highMid * 1.9) * 0.22;
    float c1 = cos(a1);
    float s1 = sin(a1);
    float c2 = cos(a2);
    float s2 = sin(a2);

    dir.xz = float2(dir.x * c1 + dir.z * s1, -dir.x * s1 + dir.z * c1);
    dir.xy = float2(dir.x * c2 + dir.y * s2, -dir.x * s2 + dir.y * c2);

    float3 from = float3(1.0, 0.5, 0.5);
    from += float3(time * (1.75 + bass * 0.8), time * (0.8 + lowMid * 0.5), -2.0 - energy * 0.8);
    from.xz = float2(from.x * c1 + from.z * s1, -from.x * s1 + from.z * c1);
    from.xy = float2(from.x * c2 + from.y * s2, -from.x * s2 + from.y * c2);

    int volsteps = u.volsteps;
    int iterations = u.iterations;
    float formuparam = u.formuparam + lowMid * 0.08;
    float tile = u.tile + bass * 0.18;
    float stepsize = u.stepsize - min(treble * 0.018, 0.035);
    float brightness = u.brightness + energy * 0.00075 + treble * 0.00035;
    float darkmatter = u.darkmatter - bass * 0.08;
    float distfading = u.distfading + highMid * 0.08;
    float saturation = u.saturation + treble * 0.18;

    float s = 0.1;
    float fade = 1.0;
    float3 accum = float3(0.0);
    float glow = 0.0;

    for (int r = 0; r < 26; ++r) {
        if (r >= volsteps) break;

        float3 p = from + s * dir * 0.5;
        float tile2 = tile * 2.0;
        p = abs(float3(tile) - float3(positiveMod(p.x, tile2),
                                      positiveMod(p.y, tile2),
                                      positiveMod(p.z, tile2)));

        float pa = 0.0;
        float a = 0.0;
        for (int i = 0; i < 16; ++i) {
            if (i >= iterations) break;
            float lp = max(dot(p, p), 1e-4);
            p = abs(p) / lp - formuparam;
            float lenP = length(p);
            a += abs(lenP - pa);
            pa = lenP;
        }

        float dm = max(0.0, darkmatter - a * a * 0.001);
        a *= a * a;
        if (r > 6) fade *= 1.0 - dm;

        int bandIndex = min((r * 16) / 26, 15);
        float bandAmp = clamp(input.bands[bandIndex], 0.0, 1.5);
        float depth = float(r) / 25.0;
        float pulse = 0.75 + bandAmp * 0.9 + energy * 0.45;
        float star = a * brightness * fade * pulse;
        accum += float3(s, s * s, s * s * s * s) * star;
        glow += fade * (0.012 + bandAmp * 0.014);

        fade *= distfading;
        s += stepsize * (1.0 + depth * bass * 0.18);
    }

    accum += float3(glow);
    float grey = length(accum);
    accum = mix(float3(grey), accum, saturation);

    float luminance = dot(accum, float3(0.2126, 0.7152, 0.0722));
    float level = clamp(luminance * 0.9 + bass * 0.16 + treble * 0.08, 0.0, 1.0);
    float3 paletteColor = samplePalette(palette, level);
    float sparkle = 1.0 + treble * 1.3 + smoothstep(0.45, 1.2, luminance) * (0.6 + energy);
    float3 color = paletteColor * accum * (1.8 + energy * 1.4) * sparkle;

    return float4(color, 1.0);
}

// ---- Outrun the Rain shader ----
// OutrunTheRain: single-pass procedural rain for Metal, inspired by "Outrun the rain" by Ian Reichert-Watts.
// The MIT License, Copyright (c) 2018 Ian Reichert-Watts.
// Source: https://github.com/AlexVestin/musicvid.org/blob/master/src/editor/animation/shaders/OutrunTheRain.js
// Changes were made: reimplemented as a single-pass audio-reactive MSL effect.

static inline float outrunHash(float n) {
    return fract(sin(n * 12.9898) * 43758.5453);
}

// One depth layer of falling streaks. `columns` divides screen width into thin
// rain channels; `fall` scrolls them downward over time. All control values are
// continuous floats — there are no audio-driven loop counts here, so the effect
// never flickers frame-to-frame from changing iteration bounds.
static inline float outrunRainLayer(float2 uv, float columns, float fall,
                                    float t, float seed, float thickness) {
    float colF = uv.x * columns + seed * 31.0;
    float col = floor(colF);
    float fx = fract(colF) - 0.5;
    float h = outrunHash(col + seed * 7.0);
    float h2 = outrunHash(col + seed * 13.0 + 5.0);
    // Per-column vertical scroll with speed/phase jitter so drops desync.
    float yy = uv.y * (1.5 + h) + t * fall * (0.7 + h * 0.9) + h2 * 10.0;
    float cell = fract(yy);
    // Bright head at cell≈0, quadratic fade down the tail.
    float streak = 1.0 - smoothstep(0.0, 0.55, cell);
    streak *= streak;
    // Horizontal thinness; larger thickness => sharper line.
    float width = exp(-fx * fx * thickness);
    // Leave gaps so the rain isn't a solid grid (static per column).
    float present = step(0.35, h);
    return streak * width * present;
}

// Field order/types MUST match `OutrunRainUniforms` in Sources/Core. All 44 are
// `float`, so the struct is densely packed with no internal padding.
struct OutrunRainUniforms {
    float horizon;
    float horizonGlowScale;
    float horizonGlowBase;
    float horizonBassGlow;
    float lowMidBackdrop;
    float backgroundBrightness;
    float backgroundGlow;
    float leanBase;
    float leanLowMid;
    float fallBase;
    float fallBass;
    float fallEnergy;
    float density;
    float layer0ColumnScale;
    float layer0FallScale;
    float layer0Seed;
    float layer0Thickness;
    float layer0Weight;
    float layer1ColumnScale;
    float layer1FallScale;
    float layer1Seed;
    float layer1Thickness;
    float layer1Weight;
    float layer2ColumnScale;
    float layer2FallScale;
    float layer2Seed;
    float layer2Thickness;
    float layer2Weight;
    float sparkleColumnScale;
    float sparkleFallScale;
    float sparkleSeed;
    float sparkleThickness;
    float sparkleBase;
    float sparkleTreble;
    float rainVerticalBase;
    float rainVerticalY;
    float rainColorBase;
    float rainColorTreble;
    float rainColorEnergy;
    float rainBrightnessBase;
    float rainBrightnessEnergy;
    float rainBrightnessTreble;
    float reflectionWidth;
    float reflectionBass;
};

fragment float4 outrun_rain_fs(FSQOut in [[stage_in]],
                               constant ShaderInputs &input [[buffer(0)]],
                               constant PaletteUniform &palette [[buffer(1)]],
                               constant OutrunRainUniforms &u [[buffer(2)]]) {
    // fullscreen_vs convention: uv.y = 0 at the TOP of the screen, 1 at the
    // bottom — exactly what rain wants (drops fall toward increasing y).
    float2 uv = in.uv;
    float t = input.time;
    float energy = clamp(input.energy, 0.0, 1.5);
    float bass   = clamp((input.bands[0] + input.bands[1] + input.bands[2] + input.bands[3]) * 0.25, 0.0, 1.5);
    float lowMid = clamp((input.bands[4] + input.bands[5] + input.bands[6] + input.bands[7]) * 0.25, 0.0, 1.5);
    float treble = clamp((input.bands[12] + input.bands[13] + input.bands[14] + input.bands[15]) * 0.25, 0.0, 1.5);

    // --- Synthwave backdrop: dark sky above, glowing horizon band low down. ---
    float horizon = u.horizon;
    float sky = smoothstep(0.0, horizon, uv.y);          // 0 at top -> 1 at horizon
    float dGlow = (uv.y - horizon) * u.horizonGlowScale;
    float glow = exp(-dGlow * dGlow);                     // bright band hugging the horizon
    float bgLevel = clamp(sky * 0.5 + glow * (u.horizonGlowBase + bass * u.horizonBassGlow) + lowMid * u.lowMidBackdrop, 0.0, 1.0);
    float3 bg = samplePalette(palette, bgLevel) * (u.backgroundBrightness + glow * (u.backgroundGlow + energy));

    // Wind-blown "outrun" lean: slant the rain diagonally, more with low-mids.
    float2 ruv = uv;
    ruv.x += uv.y * (u.leanBase + lowMid * u.leanLowMid);

    // Bass + energy thicken and speed the rain.
    float fall = u.fallBase + bass * u.fallBass + energy * u.fallEnergy;
    float baseCols = u.density;

    float rain = 0.0;
    rain += outrunRainLayer(ruv, baseCols * u.layer0ColumnScale, fall * u.layer0FallScale, t, u.layer0Seed, u.layer0Thickness) * u.layer0Weight;
    rain += outrunRainLayer(ruv, baseCols * u.layer1ColumnScale, fall * u.layer1FallScale, t, u.layer1Seed, u.layer1Thickness) * u.layer1Weight;
    rain += outrunRainLayer(ruv, baseCols * u.layer2ColumnScale, fall * u.layer2FallScale, t, u.layer2Seed, u.layer2Thickness) * u.layer2Weight;

    // Treble adds fine bright sparkle droplets.
    float sparkle = outrunRainLayer(ruv, baseCols * u.sparkleColumnScale, fall * u.sparkleFallScale, t, u.sparkleSeed, u.sparkleThickness);
    rain += sparkle * (u.sparkleBase + treble * u.sparkleTreble);

    // Rain reads denser low on screen, thins toward the top.
    rain *= u.rainVerticalBase + uv.y * u.rainVerticalY;

    float rainLevel = clamp(u.rainColorBase + treble * u.rainColorTreble + energy * u.rainColorEnergy, 0.0, 1.0);
    float3 rainColor = samplePalette(palette, rainLevel);

    // HDR: streaks push well above 1.0 so the bloom pipeline blooms them.
    // Final color is intentionally NOT clamped to [0,1].
    float3 color = bg + rainColor * rain * (u.rainBrightnessBase + energy * u.rainBrightnessEnergy + treble * u.rainBrightnessTreble);

    // Soft reflected smear of the horizon glow, pulsing with bass.
    float dRef = (uv.y - horizon) * u.reflectionWidth;
    float reflection = exp(-dRef * dRef) * bass * u.reflectionBass;
    color += samplePalette(palette, bgLevel) * reflection;

    return float4(color, 1.0);
}

// ============================================================================
// Machined-metal spinner, drawn analytically.
// Original design. Fixed light from the upper left; SDFs in the body's rotated
// frame, lighting in the screen frame so highlights stay put as the body turns.
// Field order/types MUST match SpinnerUniforms in Sources/Core/SpinnerVisualizer.swift.
// ============================================================================
struct SpinnerUniforms {
    float angle;
    float velocity;
    float frameDt;
    float hubMark;   // hub mark index: < 0.5 interlock, else sign-off
    float aspect;
    float offsetX;
    float offsetY;
    int metal;      // material index (0 steel .. 4 anodized titanium)
    float zoom;     // probe-only magnification (1 in the app)
    float tilt;     // view tilt about the horizontal axis, rad, one full turn [0, 2 pi): 0 = front face-on, pi = back face-on
    float hubFinish; // < 0.5 lit (mark cut into the hub as glowing channels), < 1.5 raised (mark stands proud of the plain hub), else engraved (unlit dark matte laser cut)
    // Appended settings (same order as SpinnerUniforms in Swift; all neutral at the factory settings).
    float roomLight;      // multiplier on the non-emissive lighting of the metal
    float glowBrightness; // multiplier on rod / arc / lit-mark emission
    float spinBlur;       // multiplier on the blur sweep (shutter length); 0 = none
    float shadowDarkness; // peak shadow opacity setting; 0.48 is the original look
    float shadowSpread;   // multiplier on the shadow's softness
    float shadowDistance; // multiplier on the shadow's offset from the puck
};


// Global scale of ALL non-emissive lighting on the metal (diffuse, anisotropic
// highlights, speculars, environment). Not applied to tube/monogram emission or the drop shadow.
constant float kSpinnerLight = 0.45;
// Distance (in R) of the virtual camera used ONLY for reflection/specular directions.
constant float spViewDist = 2.6;   // (unused since the camera below became the geometry camera)
// Mild perspective. A pinhole camera on the +z axis at spCamDist (R) from the puck center; 0 = orthographic.
// The scale is fixed so that the plane through the puck center keeps its size, so the center never moves on screen.
constant float spPerspective = 1.0;
constant float spCamDist = 6.0;
// World-space lights: the key (upper left, in front) and a dim floor bounce (below, in front).
constant float3 spKeyL = float3(-0.55, 0.60, 0.58);
constant float3 spBounceL = float3(0.20, -0.85, 0.45);
// Extra emission gain on the glow rods at full motion blur (they would smear to nothing otherwise).
constant float spEmBoost = 1.6;

// Glow tubes. 8 slots every 45 degrees, colors repeat every 4 slots
// (green, ice blue, orange, violet), each color on its own radius (R units) so motion blur
// makes four separate concentric rings.
constant float3 spTubeColor[4]  = { float3(0.25, 1.0, 0.45), float3(0.30, 0.75, 1.0),
                                    float3(1.0, 0.50, 0.12), float3(0.65, 0.35, 1.0) };
constant float  spTubeRadius[4] = { 0.69, 0.75, 0.81, 0.87 };
constant int    spTubeSlots     = 8;
constant float  spTubeHalfLen   = 0.08;    // 0.16 R long
constant float  spTubeHalfW     = 0.020;   // 0.040 R wide
constant float  spTubeSpill     = 0.05;    // glow spill distance onto the metal (R)

// Hub mark: a short bar, a pair of bars, then a lowercase "e", left to right.
// Design box 200x200, origin top-left, y DOWN, center (100,100). Round-ended strokes; each
// piece has its own stroke width and emission level (dimmer to brighter, left to right).
// One number to tune both hub marks' size (about the hub center).
constant float spMarkSize     = 0.72;
constant float spMonoScale    = 0.27 * spMarkSize / 74.0;   // R per design unit
constant float spMonoEmission = 0.85;                   // peak emissive level (piece 3)
constant float3 spMonoColor   = float3(0.30, 0.75, 1.0);   // ice blue
constant float3 spMonoPieceEm = float3(0.45, 0.75, 1.0);   // emission scale: bar, bar pair, "e"
constant float3 spMonoPieceW  = float3(6.0, 8.0, 10.0);    // stroke widths (design units)
constant float2 spMonoBar     = float2(30.0, 50.0);        // single bar x range, y = 104
constant float4 spMonoPair    = float4(64.0, 92.0, 94.0, 112.0);   // x0, x1, y of the two bars
constant float2 spMonoECenter = float2(140.0, 100.0);      // "e" center
constant float  spMonoERadius = 28.0;
constant float  spMonoEGap    = 0.836;                     // rad (47.9 deg): open wedge, lower right
constant float  spMonoELean   = 0.17453;                   // rad (10 deg) clockwise on screen

// Depth of the hub-mark channels (R units). Drives wall width, inner shadow,
// rim and spill; clamped per pixel to 45% of the local stroke width so thin strokes keep a floor.
constant float spMarkDepth = 0.022;

// Relief height of the raised mark (R units): bevel and cast-shadow width.
constant float spMarkRaise = 0.010;
// Top-face brightness of the sign-off pieces (dash, pair, "e") in the raised finish.
constant float3 spRaisePieceTone = float3(0.6, 0.8, 1.0);

// Interlocked hub mark (index 0). Same 200x200 y-down design box; letter 1 is
// four capsules, letter 2 is letter 1 evaluated at the point negated about (100,100).
constant float4 spMarkSeg[4] = {
    float4(54.0,  52.0,  54.0, 132.0),   // stem
    float4(54.0,  52.0, 120.0,  52.0),   // top bar
    float4(54.0,  92.0, 110.0,  92.0),   // middle bar
    float4(54.0, 132.0, 120.0, 132.0),   // bottom bar
};
constant float spMarkStroke = 9.0;
constant float spMarkScale  = 0.27 * spMarkSize / 73.0;     // R per design unit

static inline float spSeg(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

static inline float spMarkLetter(float2 d) {
    float m = 1e5;
    for (int i = 0; i < 4; ++i) m = min(m, spSeg(d, spMarkSeg[i].xy, spMarkSeg[i].zw));
    return m;
}

// Interlock mark SDF in R units (negative inside) at hub-centered screen point q (+y up).
static inline float spInterlockD(float2 q) {
    float2 d = float2(100.0 + q.x / spMarkScale, 100.0 - q.y / spMarkScale);
    float m = min(spMarkLetter(d), spMarkLetter(float2(200.0) - d));
    return (m - 0.5 * spMarkStroke) * spMarkScale;
}

// Signed distance in R units (negative inside) of piece `i` at hub-centered screen point q
// (+y up); converts to the y-down design box first.
static inline float spMonoD(float2 q, int i) {
    float2 d = float2(100.0 + q.x / spMonoScale, 100.0 - q.y / spMonoScale);
    float m;
    if (i == 0) {
        m = spSeg(d, float2(spMonoBar.x, 104.0), float2(spMonoBar.y, 104.0));
    } else if (i == 1) {
        m = min(spSeg(d, float2(spMonoPair.x, spMonoPair.z), float2(spMonoPair.y, spMonoPair.z)),
                spSeg(d, float2(spMonoPair.x, spMonoPair.w), float2(spMonoPair.y, spMonoPair.w)));
    } else {
        // Undo the clockwise lean (y-down coordinates) about the "e" center.
        float2 p = d - spMonoECenter;
        float c = cos(spMonoELean), sn = sin(spMonoELean);
        p = float2(c * p.x + sn * p.y, -sn * p.x + c * p.y);
        float cross = spSeg(p, float2(-spMonoERadius, 0.0), float2(spMonoERadius, 0.0));
        float ang = atan2(p.y, p.x);                        // angle from +x toward +y (y down)
        if (ang < 0.0) ang += 2.0 * M_PI_F;
        float arc;
        if (ang >= spMonoEGap) {
            arc = fabs(length(p) - spMonoERadius);
        } else {
            float2 e0 = float2(spMonoERadius, 0.0);
            float2 e1 = spMonoERadius * float2(cos(spMonoEGap), sin(spMonoEGap));
            arc = min(length(p - e0), length(p - e1));
        }
        m = min(cross, arc);
    }
    return (m - 0.5 * spMonoPieceW[i]) * spMonoScale;
}

// Active mark SDF (R units, negative inside) at hub-centered point q.
static inline float spMarkD(float2 q, float hubMark) {
    if (hubMark < 0.5) return spInterlockD(q);
    return min(spMonoD(q, 0), min(spMonoD(q, 1), spMonoD(q, 2)));
}

// Emission level and stroke width (R units) of the mark piece nearest to q.
static inline void spMarkInfo(float2 q, float hubMark, thread float &em, thread float &w) {
    if (hubMark < 0.5) { em = spMonoEmission; w = spMarkStroke * spMarkScale; return; }
    float d0 = spMonoD(q, 0), d1 = spMonoD(q, 1), d2 = spMonoD(q, 2);
    int i = (d0 <= d1 && d0 <= d2) ? 0 : (d1 <= d2 ? 1 : 2);
    em = spMonoEmission * spMonoPieceEm[i];
    w = spMonoPieceW[i] * spMonoScale;
}

static inline float spSS(float a, float b, float x) {
    float t = saturate((x - a) / (b - a));
    return t * t * (3.0 - 2.0 * t);
}

static inline float2 spRot(float2 p, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Soft rectangular light panel seen from direction r. `c` = panel axis (unit), `uu` = panel
// "width" axis (unit, perpendicular to c). half = half extents in tangent-plane units, soft = edge softness.
// Continuous in r everywhere (the window fades to zero before the panel's horizon), so no seams.
static inline float spBox(float3 r, float3 c, float3 uu, float2 hext, float soft) {
    float d = dot(r, c);
    float m = spSS(0.10, 0.40, d);
    uu = normalize(uu - c * dot(uu, c));
    float3 vv = cross(c, uu);
    float2 p = float2(dot(r, uu), dot(r, vv)) / max(d, 0.10);
    float2 a = hext - fabs(p);
    return m * spSS(-soft, soft, a.x) * spSS(-soft, soft, a.y);
}

// Soft shoulder: identity below the knee, then rolls off smoothly toward 1.0 (slope-continuous).
static inline float3 spShoulder(float3 x) {
    const float knee = 0.55, span = 1.0 - knee;
    float3 hi = knee + span * (1.0 - exp(-(max(x, knee) - knee) / span));
    return min(x, float3(knee)) + (hi - float3(knee)) * step(float3(knee), x);
}

// Procedural dim-studio environment looked up by a reflected direction (screen frame,
// +z toward the viewer, +y up). Dark surround, a soft horizon band, one large soft box from the
// upper left, two small dim fill strips, a faint cool back-rim strip and a floor bounce.
// No atan2 / azimuth terms: continuous in direction.
static inline float3 spEnv(float3 r, float3 tint, float stripGain) {
    float3 col = float3(0.040, 0.043, 0.054);
    col += float3(0.040, 0.044, 0.056) * spSS(-0.2, 1.0, r.y);                          // dim ceiling
    col += float3(0.075, 0.080, 0.095) * exp(-(r.y + 0.04) * (r.y + 0.04) / 0.030);     // soft horizon band
    col += float3(0.045, 0.047, 0.055) * spSS(0.0, 0.9, r.z);                           // faint wall in front of the object
    // Key: large soft box, upper left, slightly tilted, brighter toward its upper-left end.
    {
        float3 c = normalize(float3(-0.42, 0.62, 0.40));
        float3 uu = normalize(cross(float3(0.0, 0.0, 1.0), c));
        uu = normalize(uu * 0.94 + cross(c, uu) * 0.34);
        float b = spBox(r, c, uu, float2(0.80, 0.34), 0.20);
        float grad = mix(0.60, 1.15, spSS(-0.8, 0.8, dot(r, uu)));
        col += float3(2.6, 2.65, 2.75) * b * grad;
    }
    // Key strip: tall vertical soft box, front left. A cylinder wall reflects only near-horizontal directions, so this is
    // what gives the rim its broad highlight band; soft edges, brightest at mid height.
    {
        float3 c = normalize(float3(-0.60, 0.05, 0.80));
        float3 uu = normalize(cross(float3(0.0, 1.0, 0.0), c));
        float g = mix(1.0, 0.40, spSS(0.25, 0.95, fabs(r.y - 0.05)));
        col += float3(3.0, 3.05, 3.2) * 0.54 * stripGain * g * spBox(r, c, uu, float2(0.42, 1.6), 0.30);
    }
    // Fill 1: narrow vertical strip, right, dim and cool (tinted a little): the secondary reflection on the rim.
    col += mix(float3(0.80, 0.88, 1.0), tint * 1.4, 0.25) * 1.15
         * spBox(r, normalize(float3(0.72, 0.06, 0.48)), float3(0.0, 1.0, 0.0), float2(0.55, 0.11), 0.08);
    // Fill 2: small, dimmer, low left.
    col += float3(0.70, 0.72, 0.78) * 0.55
         * spBox(r, normalize(float3(-0.62, -0.42, 0.45)), normalize(float3(0.6, -0.3, 0.0)), float2(0.20, 0.09), 0.07);
    // Back rim strip (behind and above the object): shows on steep tilts and on the rim, reads cool.
    col += float3(0.55, 0.65, 0.90) * 1.3
         * spBox(r, normalize(float3(0.25, 0.55, -0.80)), float3(1.0, 0.0, 0.0), float2(0.75, 0.10), 0.08);
    // Warm low back strip.
    col += float3(1.0, 0.82, 0.62) * 0.55
         * spBox(r, normalize(float3(-0.45, -0.30, -0.84)), normalize(float3(0.8, 0.2, 0.0)), float2(0.35, 0.07), 0.06);
    // Fill 3: small dim strip low right (lifts the lower chamfers off the shadow).
    col += float3(0.85, 0.80, 0.75) * 0.75
         * spBox(r, normalize(float3(0.60, -0.55, 0.55)), normalize(float3(0.7, 0.5, 0.0)), float2(0.30, 0.10), 0.09);
    // Floor bounce.
    col += float3(0.120, 0.112, 0.120) * spSS(0.05, -0.55, r.y);                          // floor bounce: lifts the lower half of a wall off black
    return col;
}

// Material table, indexed by SpinnerUniforms.metal
// (0 steel, 1 brass, 2 copper, 3 black zirconium, 4 anodized titanium).
// f0: base reflectance of the outer face; deep: base of the recessed inner ring/grooves;
// glossK scales speculars; dim scales this metal's non-emissive lighting (on top of
// kSpinnerLight) so bright metals stay in the dim-room range; cast tints the highlights;
// film > 0 enables the thin-film color shift.
struct SpMat { float3 f0; float3 deep; float glossK; float dim; float3 cast; float film; float glow; float room; };

static inline SpMat spMaterial(int m) {
    SpMat k;
    k.glossK = 1.0; k.dim = 1.0; k.cast = float3(0.0); k.film = 0.0; k.glow = 1.0; k.room = 1.0;
    if (m == 1) {          // brass
        k.f0 = float3(0.96, 0.76, 0.32); k.deep = float3(0.42, 0.27, 0.07); k.dim = 0.98;
    } else if (m == 2) {   // copper
        k.f0 = float3(0.95, 0.64, 0.54); k.deep = float3(0.40, 0.22, 0.17); k.dim = 0.75;
    } else if (m == 3) {   // black zirconium
        k.f0 = float3(0.17, 0.18, 0.20); k.deep = float3(0.07, 0.075, 0.09); k.glossK = 1.5;
        k.dim = 1.6; k.cast = float3(0.0, 0.04, 0.10);
    } else if (m == 4) {   // anodized titanium
        k.f0 = float3(0.50, 0.51, 0.53); k.deep = float3(0.18, 0.19, 0.21); k.dim = 1.1; k.film = 1.0;
    } else {               // steel
        k.f0 = float3(0.56, 0.57, 0.58); k.deep = float3(0.19, 0.195, 0.21);
    }
    return k;
}

// Thin-film color: t 0..1 runs blue -> violet -> magenta -> gold.
static inline float3 spFilmColor(float t) {
    // Clean blue -> violet -> silver-lavender -> pale gold (no magenta stop, so it never reads pink).
    float3 c = mix(float3(0.22, 0.40, 0.95), float3(0.50, 0.38, 0.92), spSS(0.0, 0.34, t));
    c = mix(c, float3(0.80, 0.77, 0.84), spSS(0.34, 0.64, t));
    return mix(c, float3(0.96, 0.80, 0.42), spSS(0.64, 1.0, t));
}

// Applies the anodized thin-film tint (varies with radius and screen angle); strongest on
// the outer face and chamfer. No-op for other materials.
static inline float3 spFilm(float3 col, SpMat mat, float r, float2 radScreen, float3 n) {
    if (mat.film <= 0.0) return col;
    float t = saturate(r * 1.15 - 0.25 + 0.30 * dot(radScreen, float2(-0.55, 0.60)) + 0.35 * dot(n.xy, float2(-0.55, 0.60)));
    float strength = 0.35 + 0.65 * spSS(0.55, 0.80, r);
    float3 fc = spFilmColor(t);
    fc = mix(float3(dot(fc, float3(0.33))), fc, 0.55);          // tinted metal, not paint
    return col * mix(float3(1.0), fc * 1.6, strength * 0.7);
}

static inline float3 spFresnel(float3 f0, float ndv) {
    return f0 + (1.0 - f0) * pow(1.0 - saturate(ndv), 5.0);
}

// Metal shading of normal n (screen frame) with optional brushed anisotropy.
// `radial` is the unit radial direction on screen (for the lathe-turned streaks); `v` is the unit direction
// to the viewer (slightly different per pixel, so a flat face reflects a sweep of directions
// and shows a gradient instead of one flat tone; geometry stays orthographic).
// Reflection-led: a small ambient floor plus the dim studio reflected by the Fresnel-tinted surface.
// Brushed surfaces smear the reflection across the groove (four env taps, evaluated once per pixel by callers).
static inline float3 spMetal(float3 n, float3 f0, float3 tint, float aniso, float2 radial, float gloss, SpMat mat, float3 v) {
    n = normalize(n);
    float nv = max(dot(n, v), 0.001);
    float3 r = 2.0 * nv * n - v;
    float3 env;
    if (aniso > 0.0) {
        float3 sm = float3(radial, 0.0) * (0.20 * aniso);          // streak across the groove (radial on a lathe-turned face)
        env = 0.25 * (spEnv(normalize(r - 1.5 * sm), tint, 0.28) + spEnv(normalize(r - 0.5 * sm), tint, 0.28)
                    + spEnv(normalize(r + 0.5 * sm), tint, 0.28) + spEnv(normalize(r + 1.5 * sm), tint, 0.28));
    } else {
        env = spEnv(r, tint, 0.28);
    }
    // Ambient follows the WORLD normal: a face tipped down sees mostly floor and loses most of it, one tipped up gains.
    float hemi = n.y >= 0.0 ? 1.0 + 0.55 * n.y : 1.0 + 0.85 * n.y;
    float3 col = f0 * (0.50 * max(hemi, 0.12)) + env * spFresnel(f0, nv) * 1.0;
    float3 L = normalize(spKeyL);
    float3 h = normalize(L + v);
    if (aniso > 0.0) {
        // Concentric grooves: highlight is tight along the groove tangent, wide across it.
        float2 t = float2(-radial.y, radial.x);
        float2 hd = h.xy - n.xy;
        float ht = dot(hd, t), hr = dot(hd, radial);
        float s = exp(-(ht * ht) / 0.020 - (hr * hr) / 0.55);
        // Second, fainter pair from the right-hand fill strip: its half vector lies along another diagonal.
        float3 h2 = normalize(normalize(float3(0.62, -0.20, 0.76)) + v);
        float2 hd2 = h2.xy - n.xy;
        float ht2 = dot(hd2, t), hr2 = dot(hd2, radial);
        float s2 = exp(-(ht2 * ht2) / 0.030 - (hr2 * hr2) / 0.60);
        col += f0 * (s * 0.95 + s2 * 0.34) * aniso;
    }
    // Tight key specular (only visible where a bevel tilts the normal into it).
    col += (float3(1.0) + mat.cast * 8.0) * pow(max(dot(n, h), 0.0), gloss * mat.glossK) * 1.35 + mat.cast * 0.5;
    return spShoulder(col * kSpinnerLight * mat.dim);
}

// Disc-frame -> screen-frame for a view tilted by angle t (cs = (cos t, sin t)):
// the disc's top edge moves away from the viewer. Identity at t = 0.
static inline float3 spTiltN(float3 n, float2 cs) {
    return float3(n.x, n.y * cs.x + n.z * cs.y, -n.y * cs.y + n.z * cs.x);
}

// spMetal for a normal / radial direction given in the disc frame.
static inline float3 spMetalT(float3 n, float3 f0, float3 tint, float aniso, float2 radial, float gloss, SpMat mat, float2 cs, float3 v) {
    float2 rs = float2(radial.x, radial.y * cs.x);
    float l = length(rs);
    rs = l > 1e-4 ? rs / l : radial;
    return spMetal(spTiltN(n, cs), f0, tint, aniso, rs, gloss, mat, v);
}

// Thin machined-edge line. dist = signed distance from the edge, w = half width (about a pixel),
// facing in -1..1: > 0 the bevel turns toward the key light (catches a bright line), < 0 turns away (dark line).
static inline float3 spEdge(float3 col, float dist, float w, float facing, float3 lit, float hi, float lo) {
    float line = 1.0 - spSS(0.0, w, fabs(dist));
    return col * (1.0 - lo * saturate(-facing) * line) + lit * (hi * saturate(facing) * line);
}

// Key light direction in the view plane (unit): upper left.
constant float2 spL2 = float2(-0.6759, 0.7373);

// The light that the relief cues of a face (slit walls, groove lips, recess edges, mark bevels) respond to,
// as a unit direction in the face's local (view-frame) 2D coordinates plus a strength 0..1. The key and the floor bounce are
// projected into the face plane for the current tilt (cs = cos, sin of the visible face's tilt). The key only counts while it
// actually lights the face (its normal component is positive); a face tipped away from it is lit by the bounce, from below,
// and weaker. Flat-on this reproduces spL2 at full strength.
static inline float3 spLightLocal(float2 cs) {
    float c = cs.x, s = cs.y;
    float3 K = normalize(spKeyL), Bn = normalize(spBounceL);
    float kz = K.y * s + K.z * c;
    float2 kp = float2(K.x, K.y * c - K.z * s);
    float bz = Bn.y * s + Bn.z * c;
    float2 bp = float2(Bn.x, Bn.y * c - Bn.z * s);
    float sk = spSS(-0.05, 0.45, kz);
    float sb = 0.55 * spSS(0.0, 0.7, bz);
    float2 kd = kp / max(length(kp), 1e-4), bd = bp / max(length(bp), 1e-4);
    float2 e = kd * sk + bd * sb * (1.0 - sk);
    float len = length(e);
    float2 dir = len > 1e-4 ? e / len : kd;
    return float3(dir, saturate(sk + sb * (1.0 - sk)));
}

static inline float spHash(float x) { return fract(sin(x * 127.1) * 43758.5453); }

// Laser-cut openwork in the inner ring: through-slots swept like turbine vanes.
constant int   spSlitCount   = 12;
constant float spSlitInner   = 0.42;                 // R, inner end
constant float spSlitOuter   = 0.57;                 // R, outer end
constant float spSlitSweep   = 0.2443;               // rad (14 deg): outer end advanced vs inner end
constant float spSlitWidth   = 0.022;                // R
constant float spCutWall     = 0.0075;                // R, offset used for the visible cut-wall sliver
constant float spThickness = 0.32;                // R, thickness of the OUTER WHEEL and the rim wall (the tallest ring); the inner web is thinner by 2 * spWebRecess
// Stepped cross-section, identical on both faces: the outer wheel (step radius out to the rim) is the tallest ring,
// the inner web (slits) sits spWebRecess lower on each side, and the hub is a short cylinder standing spHubProud above the outer face.
constant float spWebRecess = 0.07;                // R per side
constant float spHubProud = 0.02;                 // R above the outer wheel's face
constant float spStepR = 0.62;                    // R, the outer wheel's inner edge (the step wall)
constant float spHubR = 0.36;                     // R, the hub cylinder
constant float spStepChamfer = 0.014;             // R, chamfer on the step's top edge
// Effective thickness of the tilted drop-shadow construction (the old 0.3 x 0.11 plate value, kept on purpose):
// a larger value shifts the bottom-face shadow past the slit width and closes the shadow's slit holes.
constant float spShadowThickness = 0.033;
constant float spRimChamfer = 0.030;               // R, 45-degree chamfer at the top and bottom edge of the rim wall (cuts in from the full radius)
constant float spRimGrooveHalf = 0.011;            // R, half width of the two fine grooves bounding the rim wall's center band
constant float3 spCutWallColor = float3(0.060, 0.040, 0.032);   // dark, slightly heat-tinted

// Signed distance (negative inside the slot) at body-frame point b; slots repeat every 2*pi/count.
static inline float spSlitD(float2 b) {
    float sector = 2.0 * M_PI_F / float(spSlitCount);
    float k = floor(atan2(b.y, b.x) / sector + 0.5);
    float2 p = spRot(b, -k * sector);
    float a0 = -0.5 * spSlitSweep, a1 = 0.5 * spSlitSweep;
    float2 pin = spSlitInner * float2(cos(a0), sin(a0));
    float2 pout = spSlitOuter * float2(cos(a1), sin(a1));
    return spSeg(p, pin, pout) - 0.5 * spSlitWidth;
}

// Smooth 1D value noise (band-limited, so brushing stays stable under minification).
static inline float spVN(float x) {
    float i = floor(x), f = x - i;
    f = f * f * (3.0 - 2.0 * f);
    return mix(spHash(i), spHash(i + 1.0), f) - 0.5;
}

// Face shading, split per region.
// Colour of one face region at radius r (no edge lines). Regions: 1 outer chamfer, 2 outer face, 3 groove, 4 inner ring, 5 under the hub.
static inline float3 spFaceCol(int region, float r, float2 rs, float2 q, float e, SpMat mat, float3 tint, float hubShadowTerm,
                               float2 cs, float3 v, float w, float lf) {
    const float rChamfer = 0.94, rStep = 0.62, rInner = 0.60, rHub = 0.38;
    float3 lit = mat.f0 * kSpinnerLight * mat.dim;      // an edge line's base brightness
    float3 col;
    if (region == 1) {
        // Polished outer chamfer: tilted outward, one crisp specular, plus a continuous highlight arc along its middle
        // (full strength on the light side, still visible on the far side) so the ring's thickness reads at every tilt.
        float t = saturate((r - rChamfer) / (1.0 - rChamfer));
        float tilt = mix(0.35, 1.5, spSS(0.0, 1.0, t));
        float3 n = float3(rs * tilt, 1.0);
        col = spMetalT(n, mat.f0 * 0.72, tint, 0.0, rs, 220.0, mat, cs, v);
        col = spFilm(col, mat, r, rs, n);
        float arcW = max(0.8 * w, 0.0022);
        float arc = 1.0 - spSS(0.0, arcW, fabs(r - (rChamfer + 0.036)));
        col += lit * arc * (0.95 + 1.10 * saturate(lf * 1.1 + 0.30));
    } else if (region == 2) {
        // Outer face: circular-brushed metal. Band-limited ring noise at three scales (finest fades first),
        // plus a broad sheen variation so a large flat area is never one tone.
        float3 n = float3(0.0, 0.0, 1.0);
        float a1 = saturate(1.3 - 70.0 * e), a2 = saturate(1.3 - 190.0 * e), a3 = saturate(1.3 - 520.0 * e);
        float br = 0.50 * a1 * spVN(r * 70.0) + 0.35 * a2 * spVN(r * 190.0 + 9.0) + 0.30 * a3 * spVN(r * 520.0 + 3.0);
        float sheen = 0.5 + 0.5 * sin(dot(q, float2(5.1, 3.3)) + 2.2 * sin(dot(q, float2(1.7, -4.3))));
        n.xy += rs * br * 0.11;
        float3 base = mat.f0 * (1.0 + br * 0.55) * (0.90 + 0.18 * sheen);
        float mIn = 1.0 - spSS(0.0, spStepChamfer, r - rStep);   // the chamfer round the opening tilts down toward the center
        n.xy -= rs * mIn * 0.9;
        col = spMetalT(n, base, tint, 1.0, rs, 200.0, mat, cs, v);
        col = spFilm(col, mat, r, rs, n);
    } else if (region == 3) {
        // Groove between the outer face and the inner ring: a dark wall that catches a little light on the side facing the key.
        float t = (r - rInner) / (rStep - rInner);
        float3 n = float3(rs * mix(-1.2, 1.2, t), 1.0);
        col = spMetalT(n, mat.deep * 0.9, tint, 0.0, rs, 80.0, mat, cs, v) * 0.62;
        col *= 0.55 + 0.45 * spSS(0.0, 0.8, t);             // darkest at the floor, the wall rises toward the face
    } else if (region == 4) {
        // Inner ring: satin metal, one step lighter than the groove, slightly dished so it carries its own faint reflection;
        // the through-cut slits are applied per spin sample by the caller.
        float3 n = float3(0.0, 0.0, 1.0);
        float a1 = saturate(1.3 - 70.0 * e);
        n.xy += rs * (0.06 * a1 * spVN(r * 70.0 + 5.0));
        n.xy += rs * ((r - 0.49) * 1.1);                     // shallow dish: the reflection drifts across the ring
        col = spMetalT(n, mat.deep * 1.38, tint, 0.8, rs, 60.0, mat, cs, v);
        col = spFilm(col, mat, r, rs, n);
        col *= mix(1.0, 0.70, spSS(rInner - 0.07, rInner, r));
        col *= mix(1.0, 0.60, spSS(rHub + 0.07, rHub, r));
        col *= hubShadowTerm;
    } else {
        // Groove under the hub (the fixed hub is drawn over this).
        col = mat.deep * 0.5 * kSpinnerLight * mat.dim;
    }
    return col;
}

static inline int spFaceRegion(float r) {
    return r > 0.94 ? 1 : 2;   // the outer face only (the web and hub are separate surfaces)
}

// The disc's face shading that does NOT depend on the spin angle (everything is a function of radius and the screen-frame
// radial direction), evaluated ONCE per pixel outside the motion-blur loop. The hard region boundaries are antialiased by
// blending the two neighbouring regions' colours over one pixel (measured along the radial direction), on top of the edge lines.
// Regions: 1 outer chamfer, 2 outer face, 3 groove, 4 inner ring, 5 under the hub, 0 outside the disc.
// `q` is the disc-frame point (back face: mirrored in y by the caller), `v` the unit view vector.
static inline float3 spFaceBase(float2 q, float e, SpMat mat, float3 tint, float hubShadowTerm, float2 cs, float mir, float3 v, float2 px, float3 ld, thread int &region) {
    float r = length(q);
    float2 rs = r > 1e-4 ? q / r : float2(1.0, 0.0);
    rs.y *= mir;
    const float rChamfer = 0.94;
    const float rStep = 0.62;
    const float rInner = 0.60;
    const float rHub = 0.38;
    float3 lit = mat.f0 * kSpinnerLight * mat.dim;      // an edge line's base brightness
    float w = max(1.5 * length(float2(rs.x * px.x, rs.y * px.y)), 0.002);   // one pixel measured ALONG the radial direction (tilt stretches y)
    float lf = dot(rs, ld.xy) * ld.z;                    // + where a bevel tilted outward faces the light (world light projected into the face; weak when the key does not reach it)
    float aa = 0.55 * w;                                 // half width of the blend across a region boundary

    region = spFaceRegion(r);
    float3 col = spFaceCol(region, r, rs, q, e, mat, tint, hubShadowTerm, cs, v, w, lf);
    const float bnd[1] = { rChamfer };
    for (int k = 0; k < 1; ++k) {
        float d = r - bnd[k];
        if (fabs(d) < aa) {
            int lo = spFaceRegion(bnd[k] - 2.0 * aa), hi = spFaceRegion(bnd[k] + 2.0 * aa);
            if (lo != hi) {
                float3 cLo = spFaceCol(lo, r, rs, q, e, mat, tint, hubShadowTerm, cs, v, w, lf);
                float3 cHi = spFaceCol(hi, r, rs, q, e, mat, tint, hubShadowTerm, cs, v, w, lf);
                col = mix(cLo, cHi, spSS(-aa, aa, d));
            }
        }
    }
    // Machined edges, applied on both sides of each radial boundary so the lines are not clipped by the region switch.
    {
        col = spEdge(col, r - rChamfer, w, lf, lit, 1.5, 0.45);               // face -> chamfer edge
        // Lip of the step: the outer corner of the opening's chamfer catches the light (stronger on the side turned to it).
        col = spEdge(col, r - rStep - spStepChamfer, w, 0.30 - 0.70 * lf, lit, 1.5, 0.0);
    }
    return col;
}

// Shades the rotating features of the disc (glow tubes on the outer face, through-slits in the inner ring) on top of
// the angle-independent `base` color from spFaceBase, at disc-frame point q.
// Returns premultiplied color (HDR: slot glow may exceed 1); alpha is the disc coverage.
// `q` is in the DISC frame (for the back face the caller passes the view point mirrored in y); `mir` (+1 front, -1 back)
// maps disc-frame in-plane vectors back to the view frame used for lighting. `wallDelta` is in the view frame.
// `emBoost` (>= 1) lifts the rods' emission when motion blur would otherwise smear them to nothing.
static inline float4 spBody(float2 q, float ang, float e, SpMat mat, float2 cs, float2 wallDelta, float mir,
                            float3 base, int region, float emBoost, float2 px, float3 ld) {
    float2 b = spRot(q, -ang);
    float r = length(b);
    float cover = 1.0 - spSS(-e, e, r - 1.0);
    if (cover <= 0.0) return float4(0.0);

    float3 col = base;
    float holeIn = 0.0, wallA = 0.0, wallDepth = 0.0;
    float3 lit = mat.f0 * kSpinnerLight * mat.dim;

    if (region == 2) {
        // Glow tubes: 8 capsule recesses, tangential, colors/radii from the table above.
        float sector = 2.0 * M_PI_F / float(spTubeSlots);
        float sa = atan2(b.y, b.x);
        float si = floor(sa / sector + 0.5);
        int ci = ((int(si) % 4) + 4) % 4;
        float3 glowCol = spTubeColor[ci];
        float2 sp = spRot(b, -si * sector);                 // slot local: x radial, y tangential
        const float halfLen = spTubeHalfLen, halfW = spTubeHalfW;
        float dy = sp.y - clamp(sp.y, -(halfLen - halfW), halfLen - halfW);
        float2 gv = float2(sp.x - spTubeRadius[ci], dy);
        float d = length(gv) - halfW;                       // <0 inside the recess
        float inside = 1.0 - spSS(-e, e, d);
        // Colored light spilling onto the surrounding metal: a tight bright halo plus a wider soft one.
        float spill = 1.0 - spSS(0.0, spTubeSpill, d);
        spill *= spill;
        float spill2 = 1.0 - spSS(0.0, 2.2 * spTubeSpill, d);
        spill2 *= spill2;
        float sBoost = 1.0 + 0.6 * (emBoost - 1.0);
        col += glowCol * (spill * 0.34 + spill2 * 0.10) * sBoost * mat.glow * (1.0 - inside);
        // Machined bevel around the recess: lit on the side facing the key light, dark on the other.
        if (fabs(d) < 3.0 * e + 0.003) {
            float2 og = gv / max(length(gv), 1e-5);
            float2 os = spRot(spRot(og, si * sector), ang);
            os.y *= mir;
            float we = length(float2(os.x * px.x, os.y * px.y));
            col = spEdge(col, d - 0.8 * we, 1.1 * we + 0.0008, -dot(os, ld.xy) * ld.z, lit, 1.7, 0.55);
        }
        if (inside > 0.0) {
            float depthT = saturate(-d / halfW);            // 0 at the wall, 1 on the axis
            float3 floorCol = mat.f0 * mix(0.04, 0.15, spSS(0.0, 0.6, depthT)) * kSpinnerLight * mat.dim;
            // Emissive glass rod seated in the recess: slightly narrower than the recess so a dark gap
            // shows, core line offset toward the screen-up side, rounded ends that dim, a glint, faint frosting,
            // and a colored glow on the recess walls.
            float2 upSp = spRot(spRot(float2(0.0, mir), -ang), -si * sector);
            float2 lfSp = spRot(spRot(float2(-1.0, 0.0), -ang), -si * sector);
            float u = (sp.x - spTubeRadius[ci]) / (0.82 * halfW);
            float ee = max(fabs(sp.y) - (halfLen - halfW), 0.0) / (0.82 * halfW);
            float q2 = u * u + ee * ee;
            float rodIn = 1.0 - spSS(0.80, 1.0, q2);
            float cylP = sqrt(saturate(1.0 - q2));
            float uc = (u - 0.30 * upSp.x) / 0.50;
            float coreC = exp(-uc * uc) * (1.0 - ee * ee);
            float frost = 1.0 + 0.16 * spVN(sp.y * 60.0 + 3.0 * float(ci)) + 0.10 * spVN(sp.y * 150.0 + 11.0) + 0.08 * spVN(u * 4.0 + sp.y * 35.0 + 5.0);   // low-contrast irregular frost
            float glintU = -0.55 * upSp.x, glintY = 0.45 * halfLen * (lfSp.y >= 0.0 ? 1.0 : -1.0);
            float gl = exp(-((u - glintU) * (u - glintU)) / 0.03 - ((sp.y - glintY) * (sp.y - glintY)) / 0.00045);
            // Glass glint: a thin streak along the tube on the side facing the key light, strongest on tubes that face it.
            float Lx = clamp((-ld.x) * lfSp.x + ld.y * upSp.x, -1.0, 1.0) * ld.z;
            float gu = 0.58 * Lx;
            float streak = exp(-((u - gu) * (u - gu)) / 0.014) * (1.0 - ee * ee) * (0.30 + 0.70 * fabs(Lx));
            float3 em = (glowCol * (0.45 + 1.15 * cylP) * mix(0.35, 1.0, spSS(0.0, 0.6, 1.0 - ee * ee)) + mix(glowCol, float3(1.0), 0.45) * 2.6 * coreC * cylP * cylP) * frost
                      + float3(1.0) * gl * cylP * 0.8 + mix(glowCol, float3(1.0), 0.6) * 1.35 * streak * cylP;
            em *= emBoost * mat.glow;
            float wallG = 1.0 - spSS(0.0, 0.5, depthT);
            float3 recess = floorCol + glowCol * 0.40 * wallG * (0.6 + 0.4 * emBoost) * mat.glow;
            col = mix(col, mix(recess, em, rodIn), inside);
        }
    } else if (region == 4) {
        // Through-cut: coverage 0 inside the slot; the wall sliver (side away from the light)
        // is the slot SDF sampled at a small offset in that direction.
        // Visible wall offset: the fixed light-side sliver plus the tilt parallax (the ray's
        // lateral travel through the thickness), capped so a see-through opening always remains.
        float2 offs = -ld.xy * spCutWall + wallDelta;
        float offLen = length(offs);
        if (offLen > 0.6 * spSlitWidth) offs *= 0.6 * spSlitWidth / offLen;
        float offLen2 = max(length(offs), 1e-5);
        offs.y *= mir;                                   // view frame -> disc frame
        float2 away = spRot(offs, -ang);
        float dS = spSlitD(b);
        float dS2 = spSlitD(b + away);
        holeIn = 1.0 - spSS(-e, e, dS);
        wallA = holeIn * spSS(-e, e, dS2);
        wallDepth = -dS / max(-dS + dS2, 1e-5);
        // Occlusion that hugs the slit rim, and a crisp machined edge: lit where the metal bevel turns toward the light.
        col *= 1.0 - 0.38 * (1.0 - spSS(0.0, 0.03, dS)) * (1.0 - holeIn);   // recess occlusion (not light dependent)
        float facing = clamp((dS2 - dS) / offLen2, -1.0, 1.0);
        float we = max(px.x, px.y);
        col = spEdge(col, dS - 0.8 * we, 1.1 * we + 0.0008, facing * ld.z, lit, 1.15, 0.5);
    }
    float3 wallCol = spCutWallColor * kSpinnerLight * mat.dim;
    if (wallA > 0.0 && fabs(cs.y) > 0.01) {
        // Deeper in the cut = darker; brighter near the top rim (tilted views only).
        float f = saturate(wallDepth);
        wallCol *= mix(1.0, mix(mix(1.0, 3.0, ld.z), 0.6, f), saturate(fabs(cs.y) * 4.0));
    }
    float keep = 1.0 - holeIn;
    return float4(cover * (col * keep + wallCol * wallA), cover * (keep + wallA));
}

// Disc coverage (with the slits) in the screen frame, used for the soft drop shadow.
// `k` scales the edge softness (shadow softens with distance from the disc; 1 = face-on).
// Returns (soft, sharp): the same coverage with a wide penumbra edge and with a tight umbra edge, from one set of distances.
static inline float2 spDiscCover(float2 sq, float ang, float k, float rad) {
    float dd = length(sq) - rad;
    float d = spSlitD(spRot(sq, -ang));
    float soft = (1.0 - spSS(-0.15 * k, 0.15 * k, dd)) * spSS(-0.006 * k, 0.006 * k, d);
    float sharp = (1.0 - spSS(-0.035 * k, 0.035 * k, dd)) * spSS(-0.003 * k, 0.003 * k, d);
    return float2(soft, sharp);
}

// Approximate distance (R units, > 0 outside) from screen point p to the puck's silhouette: the union of the visible face
// ellipse, the far (chamfered) edge ellipse, and the rectangle swept between them.
static inline float spSilD(float2 p, float2 cs) {
    float c = max(cs.x, 0.03), sa = fabs(cs.y), sg = cs.y < 0.0 ? -1.0 : 1.0;
    float yb = -sg * spThickness * sa;                       // far edge centre
    float kt = length(float2(p.x, p.y / c));
    float dTop = (kt - 1.0) * min(1.0, max(c, 0.25));
    float rb = 1.0 - spRimChamfer;
    float kb = length(float2(p.x / rb, (p.y - yb) / (rb * c)));
    float dBot = (kb - 1.0) * rb * min(1.0, max(c, 0.25));
    float2 dq = float2(fabs(p.x) - rb, fabs(p.y - 0.5 * yb) - 0.5 * fabs(yb));
    float dRect = length(max(dq, 0.0)) + min(max(dq.x, dq.y), 0.0);
    return min(dTop, min(dBot, dRect));
}

// Rim machining that turns with the disc, as a profiled metal cylinder: a 45-degree chamfer at
// each edge, concave brushed bands, two V grooves, and a raised, crowned, knurled center band that carries the
// eight glow tubes as recessed windows (same colors and angular positions as the face tubes).
constant float spKnurlCount     = 96.0;
constant float spKnurlHelix     = 15.3;      // cycles per R of axial travel (45 degrees against the flute pitch)
constant float spRimWindowHalfLen = 0.10;    // rad of arc (R = 1)
constant float spRimWindowHalfH   = 0.022;   // R, half height of a window slot
// Rim layout is mirror-symmetric about mid-height (zd = T/2): chamfer, brushed band, groove,
// knurled center band with the windows, groove, brushed band, chamfer.
constant float spRimGrooveZ       = 0.11;    // R, depth of the upper groove (the lower one sits at T - this): the knurl band keeps its 0.10 R height, the plain bands take the extra
constant float spRimCrown         = 0.30;    // slope of the center band's barrel crown at its edges
constant float spRimConcave       = 0.12;    // slope of the plain bands' shallow hollow at their edges

// Wall radius at depth zd below the face edge (R): the chamfers cut 45 degrees in from the full radius.
static inline float spRimRadius(float zd) {
    // The TOP keeps the full radius so the wall meets the face disc (radius 1.0) with no step in the outline;
    // only the bottom edge is cut back by its chamfer.
    return 1.0 - spRimChamfer + min(spThickness - zd, spRimChamfer);
}

// Axial slope of the wall profile at depth zd (+ = the surface faces toward the front face, i.e. up).
static inline float spRimSlope(float zd) {
    float ch = spRimChamfer, gh = spRimGrooveHalf, g1 = spRimGrooveZ, g2 = spThickness - spRimGrooveZ;
    if (zd < ch) return 1.0;                                                         // top chamfer: up and out
    if (zd < g1 - gh) { float h = 0.5 * (g1 - gh - ch); return spRimConcave * (zd - (ch + h)) / h; }
    if (zd < g1) return -1.2;                                                        // groove, upper wall: faces down
    if (zd < g1 + gh) return 1.2;                                                    // groove, lower wall: faces up
    if (zd < g2 - gh) { float h = 0.5 * (g2 - g1 - 2.0 * gh); return -spRimCrown * (zd - 0.5 * spThickness) / h; }
    if (zd < g2) return -1.2;
    if (zd < g2 + gh) return 1.2;
    float z2 = spThickness - ch;
    if (zd < z2) { float h = 0.5 * (z2 - g2 - gh); return spRimConcave * (zd - (g2 + gh + h)) / h; }
    return -1.0;                                                                     // bottom chamfer: down and out
}

// Ambient occlusion from the grooves: dark in the cut, spreading a little onto the neighbouring bands.
static inline float spRimAO(float zd) {
    float d = min(fabs(zd - spRimGrooveZ), fabs(zd - (spThickness - spRimGrooveZ))) / 0.016;
    return 1.0 - 0.6 * exp(-d * d);
}

// Rounded-end slot signed distance (negative inside) in (arc, depth) coordinates.
static inline float spSlotD(float a, float z, float hl, float hh) {
    return length(float2(max(fabs(a) - (hl - hh), 0.0), z)) - hh;
}

// The rim wall is split in two. `spRimMakeBase` runs ONCE per pixel (outside the motion-blur loop) and
// holds everything that does not depend on the rotation angle: profile (depth, slope, occlusion), the machined-edge
// lines, the shaded colour for the un-knurled normal with its environment lookups, and the slot viewing geometry.
// `spRimSample` runs per blur sample and keeps only the angle-dependent terms: knurl relief and the rod slots.
struct SpRimBase {
    float cov;                 // 0 = no wall at this pixel
    float es, zd, zdp, sg, mir, scr;
    float2 cs, pe, rv, tang;   // pe = wall point in the disc frame (before the spin)
    float ca, slope, br, amp, ao, tone, roll, turn, polished, kmask, kamp, flutePx, brushed;
    float3 v, axl;
    float edgeDark; float3 edgeAdd;
    float3 col0;               // finished colour for the un-knurled normal, edges included
    float vn, vt, va, ew, hs, hr;
    float3 envC;               // environment at the un-knurled normal
    float3 envF[4];            // environment at the four knurl facet normals (+t, -t, +z, -z); only when kamp > 0
    float3 tgl;                // screen-frame circumferential direction
    float band;                // 0..1: how deep inside the key highlight band this pixel is (gates the knurl sparkle)
    float3 tintC;
};

// Environment seen by a wall normal n (screen frame): plain turned bands smear along the axis, polished parts stay sharp.
static inline float3 spRimEnv(float3 n, float3 v, float3 tint, float brushed, float3 axl, float3 tgl) {
    float nz = max(dot(n, v), 0.001);
    float3 rr = 2.0 * nz * n - v;
    float3 e0 = spEnv(rr, tint, 1.0);
    if (brushed > 0.02) {
        float3 e1 = spEnv(normalize(rr + 0.34 * axl), tint, 1.0), e2 = spEnv(normalize(rr - 0.34 * axl), tint, 1.0);
        float3 e3 = spEnv(normalize(rr + 0.22 * tgl), tint, 1.0), e4 = spEnv(normalize(rr - 0.22 * tgl), tint, 1.0);
        return mix(e0, 0.36 * e0 + 0.14 * (e1 + e2) + 0.18 * (e3 + e4), brushed);
    }
    return e0;
}

// Wall shading for a knurl-perturbed normal (dtk, dzk = flute slopes already scaled by the knurl amplitude, cavk = kamp*cavity).
static inline float3 spRimShade(thread const SpRimBase &B, float dtk, float dzk, float cavk, float3 envc, SpMat mat) {
    float3 nd = float3(B.rv + B.tang * dtk, B.slope + dzk);
    float3 n = normalize(spTiltN(normalize(nd), B.cs));
    float3 v = B.v;
    float3 L = normalize(float3(-0.55, 0.60, 0.58));
    float3 hh3 = normalize(L + v);
    float nz = max(dot(n, v), 0.001);
    float diff = saturate(dot(n, L));
    float ndh = saturate(dot(n, hh3));
    float3 f0 = mat.f0 * 1.25 * (1.0 + B.br * 0.10 * B.amp) * B.tone;
    f0 *= 1.0 - 0.60 * cavk;                                   // knurl valleys dark, peaks bright
    float3 col = f0 * (0.10 + 2.4 * diff * diff) * B.roll;
    col += envc * spFresnel(mat.f0, nz) * 0.95 * (1.0 - 0.94 * B.turn) * mix(0.85, 1.0, B.polished);
    {   // Broad soft-box sheen on the cylinder: a wide lobe from the key strip (left of centre) and a narrow secondary from the
        // fill strip (right). Grooves and facets that turn away from the axis fall out of it, so the relief stays visible in the band.
        float kx = (B.rv.x + 0.34) / 0.38, fx = (B.rv.x - 0.50) / 0.13;
        float lobe = exp(-kx * kx) + 0.30 * exp(-fx * fx);
        float vert = exp(-(B.slope + dzk * 0.25) * (B.slope + dzk * 0.25) / 0.45);
        col += mat.f0 * f0.x / max(mat.f0.x, 1e-3) * 0.70 * (1.0 + 2.0 * B.kamp) * lobe * vert * (1.0 - 0.3 * cavk) * (1.0 - 0.9 * B.turn);
    }
    float polish = 0.55 + 0.45 * B.polished;
    float hlen = mix(1.0, 0.45, B.brushed);                    // broader specular lobe on the plain bands
    col += (float3(1.0) + mat.cast * 8.0) * (pow(ndh, 150.0 * mat.glossK * hlen) * 0.65 * polish
                                           + pow(ndh, 40.0 * mat.glossK) * 0.70) * mix(1.0, 0.3, B.turn) + mat.cast * 0.5;
    float rimL = spSS(0.95, 0.998, fabs(B.rv.x));
    col += mat.f0 * rimL * (B.rv.x < 0.0 ? 0.22 : 0.09);
    col *= B.ao;
    col *= mix(1.0, 0.72, spSS(0.0, spThickness, B.zd));
    col *= kSpinnerLight * mat.dim;
    col = spFilm(col, mat, 0.95, float2(0.0, -B.sg), n);
    return spShoulder(col);
}

static inline SpRimBase spRimMakeBase(float3 Ol, float3 Dl, float es, float2 cs, SpMat mat, float3 tint, float mir, float3 camW) {
    // Ol, Dl: the pixel's view ray in the visible face's local frame (x right, y up in the face, z along its outward axis;
    // the puck center is the origin, the outer face plane is z = +T/2). The wall is the rim cylinder (axis z) with the profile
    // radius spRimRadius(depth); its near root is the visible surface. Depth and radius depend on each other through the chamfer.
    SpRimBase B;
    B.cov = 0.0;
    float c = cs.x;
    float sa = fabs(cs.y);
    float2 o2 = Ol.xy, d2 = Dl.xy;
    float a2 = dot(d2, d2);
    if (a2 < 1e-8) return B;                          // the ray runs along the axis (orthographic, face-on): no wall
    float bq = dot(o2, d2);
    float zo = 0.5 * spThickness;
    float r = 1.0, zdRaw = 0.0, t = 0.0;
    for (int it = 0; it < 3; ++it) {
        float disc = bq * bq - a2 * (dot(o2, o2) - r * r);
        t = (-bq - sqrt(max(disc, 0.0))) / a2;
        zdRaw = zo - (Ol.z + t * Dl.z);
        r = spRimRadius(clamp(zdRaw, 0.0, spThickness));
    }
    float dAxis = sqrt(max(dot(o2, o2) - bq * bq / a2, 0.0));       // distance of the ray from the axis
    float cx = 1.0 - spSS(-es, es, dAxis - r);                      // lateral silhouette (tangent rays): follows the chamfered profile
    if (cx <= 0.0) return B;
    float zd = clamp(zdRaw, 0.0, spThickness);
    float zdp = max(es / max(sa, 0.25), 1e-4);        // pixel size along zd
    // Depth bounds: the far edge, and a margin above the top edge (tucked under the face, which composites over the wall).
    float cov = cx * spSS(-zdp, zdp, spThickness - zdRaw) * (1.0 - spSS(zdp, 3.0 * zdp, -zdRaw));
    if (cov <= 0.0) return B;
    float3 Ph = Ol + t * Dl;                          // wall point, local frame
    float3 Pw = float3(Ph.x, Ph.y * c + Ph.z * cs.y, -Ph.y * cs.y + Ph.z * c);   // world (screen) frame
    float3 v = normalize(camW - Pw);
    B.cov = cov; B.es = es; B.zd = zd; B.mir = mir; B.cs = cs; B.v = v;
    B.sg = cs.y < 0.0 ? -1.0 : 1.0;
    B.zdp = zdp;
    B.amp = saturate(1.0 - es * 150.0);
    B.br = spHash(floor(zd * 220.0)) - 0.5;           // circumferential machining lines

    float rl = max(length(Ph.xy), 1e-3);
    B.pe = float2(Ph.x, mir * Ph.y);
    B.rv = Ph.xy / rl;                                // cylinder normal's horizontal part (unit)
    B.tang = mir * float2(-B.rv.y, B.rv.x);           // view-frame direction of increasing beta
    B.ca = sqrt(max(1.0 - B.rv.x * B.rv.x, 0.0));     // cylinder foreshortening (1 at the middle, 0 at the ends)

    B.slope = (spRimSlope(zd - 0.5 * zdp) + spRimSlope(zd) + spRimSlope(zd + 0.5 * zdp)) * (1.0 / 3.0);
    B.ao = spRimAO(zd);
    float g1 = spRimGrooveZ, g2 = spThickness - spRimGrooveZ, gh = spRimGrooveHalf;
    float crown = spSS(g1 + gh - zdp, g1 + gh + zdp, zd) * (1.0 - spSS(g2 - gh - zdp, g2 - gh + zdp, zd));
    B.polished = max(crown, 1.0 - spSS(spRimChamfer - zdp, spRimChamfer + zdp, min(zd, spThickness - zd)));

    B.kmask = spSS(g1 + gh + 0.004, g1 + gh + 0.012, zd) * (1.0 - spSS(g2 - gh - 0.012, g2 - gh - 0.004, zd));
    B.flutePx = (2.0 * M_PI_F / spKnurlCount) * max(B.ca, 0.05) / max(es, 1e-4);   // flute width in pixels
    B.kamp = B.kmask * spSS(1.6, 4.5, B.flutePx);
    B.turn = spSS(0.30, 0.95, fabs(B.rv.x));          // 0 across the middle, 1 at the ends: the wall rolls away
    B.roll = mix(1.0, 0.16, B.turn);
    B.tone = mix(0.80, 1.0, B.polished);              // plain bands sit a clear step below the crown
    B.brushed = (1.0 - B.polished) * (1.0 - B.kamp);
    B.axl = normalize(spTiltN(float3(0.0, 0.0, 1.0), cs));       // screen-frame axial direction of the wall
    B.tintC = tint;

    // Environment on the un-knurled normal: once per pixel.
    float3 n0 = normalize(spTiltN(normalize(float3(B.rv, B.slope)), cs));
    B.tgl = normalize(spTiltN(float3(B.tang, 0.0), cs));
    B.envC = spRimEnv(n0, v, tint, B.brushed, B.axl, B.tgl);
    B.band = spSS(0.8, 2.2, dot(B.envC, float3(0.3333)));
    B.envF[0] = B.envF[1] = B.envF[2] = B.envF[3] = B.envC;
    if (B.kamp > 0.0) {
        for (int k = 0; k < 4; ++k) {
            float s = (k & 1) ? -1.0 : 1.0;
            float3 ndf = (k < 2) ? float3(B.rv + B.tang * (s * 0.80 * B.kamp), B.slope)
                                 : float3(B.rv, B.slope + s * 0.80 * B.kamp);
            B.envF[k] = spRimEnv(normalize(spTiltN(normalize(ndf), cs)), v, tint, 0.0, B.axl, B.tgl);
        }
    }
    B.col0 = spRimShade(B, 0.0, 0.0, 0.0, B.envC, mat);

    // Machined edges: a thin line at every profile break. Convex corners facing up catch the key, those on the
    // lower half or concave corners (groove bottoms) go dark. Brightness follows the light side of the cylinder.
    float3 lit = mat.f0 * kSpinnerLight * mat.dim;
    float side = mix(0.30, 1.0, saturate(0.5 - 0.65 * B.rv.x)) * mix(0.35, 1.0, B.ca);
    const float ez[9] = { spRimChamfer, spRimGrooveZ - spRimGrooveHalf, spRimGrooveZ, spRimGrooveZ + spRimGrooveHalf,
                          spThickness - spRimGrooveZ - spRimGrooveHalf, spThickness - spRimGrooveZ,
                          spThickness - spRimGrooveZ + spRimGrooveHalf, spThickness - spRimChamfer, 0.45 * spRimChamfer };
    const float eh[9] = { 1.5, 1.3, -0.9, 0.6, 0.35, -0.8, 0.2, 0.55, 2.8 };   // last: the crisp highlight arc along the top chamfer
    float lw = max(1.0 * zdp, 0.0012);
    float arcSide = mix(0.60, 1.0, saturate(0.5 - 0.65 * B.rv.x)) * mix(0.55, 1.0, B.ca);   // the top-chamfer arc stays continuous round the whole wall
    float3 add = float3(0.0); float dark = 0.0;
    for (int k = 0; k < 9; ++k) {
        float l = 1.0 - spSS(0.0, lw, fabs(zd - ez[k]));
        add += lit * (max(eh[k], 0.0) * l * (k == 8 ? arcSide / max(side, 1e-3) : 1.0));
        dark = max(dark, max(-eh[k], 0.0) * l);
    }
    B.edgeDark = 1.0 - 0.6 * dark * side;
    B.edgeAdd = add * side;
    B.col0 = B.col0 * B.edgeDark + B.edgeAdd;

    // Slot viewing geometry: lateral drift of the view ray per unit depth into the pocket, soft edges.
    B.ew = max(es / max(B.ca, 0.3), zdp) * 1.1;
    {   // lateral drift of the view ray per unit depth: the view direction against the wall's own axes (screen frame)
        float3 ns = normalize(spTiltN(float3(B.rv, 0.0), cs));
        B.vn = max(dot(v, ns), 0.15);
        B.vt = dot(v, B.tgl);
        B.va = dot(v, B.axl);
    }
    B.hs = max(0.026, 0.7 * zdp);
    B.hr = max(0.0155, 0.35 * zdp);
    B.scr = -mir * (B.rv.y < 0.0 ? -1.0 : 1.0);     // sign of the arc coordinate along screen x
    return B;
}

static inline float4 spRimSample(thread const SpRimBase &B, float ang, SpMat mat, float emBoost) {
    float2 bp = spRot(B.pe, -ang);
    float beta = atan2(bp.y, bp.x);
    float zd = B.zd, zdp = B.zdp;
    float3 col = B.col0;

    // Knurling as relief: diamonds from two flute sets at opposite helix angles, only on the crowned band.
    float dt = 0.0, dz = 0.0;
    if (B.kamp > 0.0) {
        float u = beta * spKnurlCount / (2.0 * M_PI_F);
        float wv = zd * spKnurlHelix;
        float fa = fract(u + wv) - 0.5, fb = fract(u - wv) - 0.5;
        float sla = -clamp(fa * 6.0, -1.0, 1.0), slb = -clamp(fb * 6.0, -1.0, 1.0);
        dt = 0.7071 * (sla + slb); dz = 0.7071 * (sla - slb);
        float cavity = 1.0 - 0.5 * ((1.0 - 2.0 * fabs(fa)) + (1.0 - 2.0 * fabs(fb)));   // 0 on a peak, ~1 in a valley
        float dtk = dt * B.kamp, dzk = dz * B.kamp;
        float3 nd = float3(B.rv + B.tang * dtk, B.slope + dzk);
        float3 n = normalize(spTiltN(normalize(nd), B.cs));
        float wtp = max(dt, 0.0) * 0.7071, wtm = max(-dt, 0.0) * 0.7071, wzp = max(dz, 0.0) * 0.7071, wzm = max(-dz, 0.0) * 0.7071;
        float3 envK = B.envC * (1.0 - (wtp + wtm + wzp + wzm)) + B.envF[0] * wtp + B.envF[1] * wtm + B.envF[2] * wzp + B.envF[3] * wzm;
        col = spRimShade(B, dtk, dzk, B.kamp * cavity, envK, mat) * B.edgeDark + B.edgeAdd;
        // A few bright ticks on diamond tops, only where the key band lies.
        float cellH = spHash(floor(u + wv) * 17.0 + floor(u - wv) * 5.0 + 3.0);
        float tick = (1.0 - spSS(0.0, 0.20, fabs(fa))) * (1.0 - spSS(0.0, 0.20, fabs(fb)));
        col += (mat.f0 * 1.2 + 0.15) * (0.55 * step(0.82, cellH) * tick * B.band * B.kamp * kSpinnerLight * mat.dim * 2.0);
    }

    // Glow rods seated in machined slots on the rim's center line, at the face tubes' angular positions and colors.
    float3 lit = mat.f0 * kSpinnerLight * mat.dim;
    float sector = 2.0 * M_PI_F / float(spTubeSlots);
    float si = floor(beta / sector + 0.5);
    int ci = ((int(si) % 4) + 4) % 4;
    float a = beta - si * sector;                       // arc coordinate along the circumference (R units)
    float zc = 0.5 * spThickness;
    float zrel = zd - zc;
    float ew = B.ew, hs = B.hs, hr = B.hr;
    float hlS = 0.108, hlR = 0.094;                     // slot / rod half length
    float wd = spSlotD(a, zrel, hlS, hs);
    if (wd > 0.05) return float4(B.cov * col, B.cov);   // outside the slot's spill range: nothing angle-dependent left
    float3 gcol = spTubeColor[ci];
    float inside = 1.0 - spSS(-ew, ew, wd);
    const float Hs = 0.016, Hr = 0.011;                  // depth of the slot floor / rod axis below the surface
    float aF = a - Hs * B.vt / B.vn, zF = zrel + Hs * B.va / B.vn;
    float wdF = spSlotD(aF, zF, hlS, hs);
    float floorIn = 1.0 - spSS(-ew, ew, wdF);
    float aR = a - Hr * B.vt / B.vn, zR = zrel + Hr * B.va / B.vn;
    float2 gdir;                                        // outward direction of the slot edge in (arc, zd)
    {
        float2 wp2 = float2(max(fabs(a) - (hlS - hs), 0.0) * (a < 0.0 ? -1.0 : 1.0), zrel);
        float l2 = length(wp2);
        gdir = l2 > 1e-5 ? wp2 / l2 : float2(0.0, -1.0);
    }
    float scr = B.scr;                                  // sign of arc coordinate along screen x
    float2 gdirS = float2(gdir.x * scr, gdir.y);        // (screen x, zd = down)
    float lightFace = saturate(dot(-gdirS, normalize(float2(-0.55, -0.60)) ));   // bevel tilts toward the pocket
    float rimW = max(0.0042, 1.3 * ew);
    float rimRing = saturate(1.0 - fabs(wd) / rimW);
    col += lit * 0.95 * rimRing * lightFace;
    col *= 1.0 - 0.55 * rimRing * saturate(dot(gdirS, normalize(float2(-0.55, -0.60))) + 0.2) * (1.0 - lightFace);
    // Spill onto the surrounding metal; on the knurl it follows the flute relief (flanks facing the slot pick it up).
    float g1 = spRimGrooveZ, g2 = spThickness - spRimGrooveZ, gh = spRimGrooveHalf;
    float wspill = 1.0 - spSS(0.0, 0.045, wd);
    wspill *= wspill;
    float2 toSlot = float2(-gdir.x, gdir.y);            // (tang, axial up) direction toward the slot
    float flank = saturate(0.35 + 0.9 * dot(float2(dt, dz), toSlot));
    float spillMul = mix(1.0, flank * 1.5, B.kamp);
    float gLower = (zd > g1 && zd < g1 + gh) || (zd > g2 && zd < g2 + gh) ? 1.0 : 0.0;   // groove walls facing up
    col += gcol * wspill * 0.30 * (1.0 - inside) * (spillMul + 0.8 * gLower);
    // Slot interior: floor, walls and the rod.
    float3 pocket = lit * 0.10;
    float wallLower = spSS(0.0, 0.006, zF) * (1.0 - floorIn);       // the lower wall faces up, toward the viewer
    float wallEnd = (1.0 - floorIn) * spSS(hlS - hs - 0.005, hlS - hs + 0.005, fabs(aF));
    float3 wallCol = lit * 0.12 + gcol * (0.25 + 0.75 * wallLower + 0.55 * wallEnd);
    float upperShade = 1.0 - spSS(-hs, -hs + 0.012, zrel);          // shadowed upper wall band
    float3 slotCol = mix(wallCol, pocket, floorIn);
    slotCol *= 1.0 - 0.6 * upperShade;
    // Rod: self-luminous glass tube lying along the slot.
    float rd = spSlotD(aR, zR, hlR, hr);
    float rodIn = (1.0 - spSS(-ew, ew, rd)) * inside;
    float vv = zR / hr;                                  // -1 top .. +1 bottom
    float ee = max(fabs(aR) - (hlR - hr), 0.0) / hr;
    float q2 = vv * vv + ee * ee;
    float cylP = sqrt(saturate(1.0 - q2));
    float vc = (vv + 0.32) / 0.34;                       // core line a little above center
    float coreC = exp(-vc * vc) * (1.0 - ee * ee);
    float frost = 1.0 + 0.16 * spVN(aR * 55.0 + 2.0) + 0.10 * spVN(aR * 140.0 + 13.0 + 3.0 * vv) + 0.08 * spVN(vv * 3.0 + aR * 30.0 + 9.0);
    float aScr = aR * scr / hlR;                         // + toward screen right
    float gl = exp(-((vv + 0.58) * (vv + 0.58)) / 0.012 - ((aScr + 0.50) * (aScr + 0.50)) / 0.006);
    float faceDim = mix(0.30, 1.0, spSS(0.15, 0.85, B.ca));
    float3 wem = (gcol * (0.22 + 1.0 * cylP * cylP) * mix(0.30, 1.0, spSS(0.0, 0.7, 1.0 - ee * ee))
                 + mix(gcol, float3(1.0), 0.55) * 2.4 * coreC * coreC * cylP) * frost
               + float3(1.2) * gl * cylP * faceDim;
    float rstreak = exp(-((vv + 0.52) * (vv + 0.52)) / 0.030) * (1.0 - ee * ee) * (0.45 + 0.55 * saturate(0.5 - 0.7 * B.rv.x));
    wem += mix(gcol, float3(1.0), 0.6) * 1.1 * rstreak * cylP * faceDim;
    wem *= faceDim * emBoost * mat.glow;
    slotCol = mix(slotCol, wem, rodIn);
    col = mix(col, slotCol, inside);

    return float4(B.cov * col, B.cov);
}

// The hub's top face (a slightly domed polished disc at the top of the hub cylinder), shaded at local point q
// (face-local coordinates, hub center at the origin). Static: the hub does not rotate. Carries the mark in either finish.
static inline float3 spHubTop(float2 q, float e, float hm, bool isRaised, bool isEngraved, SpMat mat, float3 tint, float2 cs, float3 vw, float3 ld) {
    const float hubR = spHubR;
    float hr = length(q);
    float3 hubCol = float3(0.0);
    {
        float h = hr / hubR;
        float2 rd = hr > 1e-4 ? q / hr : float2(1.0, 0.0);
        if (h > 0.93) {
            // Small outer chamfer with one tight specular.
            float t = (h - 0.93) / 0.07;
            float3 n = float3(rd * mix(0.4, 1.6, t), 1.0);
            hubCol = spMetalT(n, mat.f0 * 0.65, tint, 0.0, rd, 200.0, mat, cs, vw);
            hubCol = spFilm(hubCol, mat, 0.9, rd, n);
        } else {
            // Flat, very slightly domed dark polished metal; smooth, no lobes.
            float3 n = normalize(float3(rd * h * 0.16, 1.0));
            float3 hubTone = clamp(mat.f0 / 0.56, 0.25, 1.6);
            // Polished dome: reflects the studio through the same environment as the faces (view-dependent gradient).
            hubCol = spMetalT(n, mat.f0 * 0.40, tint, 0.0, rd, 700.0, mat, cs, vw);
            // One crisp ring near the edge: a dark line with a lit lip just inside it.
            float dr = (h - 0.90) / max(0.012, e / hubR * 1.5);
            float ring = saturate(1.0 - fabs(dr));
            hubCol *= 1.0 - 0.7 * ring;
            hubCol += float3(0.30, 0.31, 0.34) * hubTone * kSpinnerLight * mat.room * saturate(1.0 - fabs(dr + 1.6)) * (0.35 + 1.3 * ld.z * saturate(0.5 - 0.5 * dot(rd, ld.xy))) * mix(0.55, 1.0, ld.z);   // lit lip follows the light (the lip facing it)

            if (isEngraved) {
            // Engraved finish: unlit. The mark is laser-cut into the polished hub as a dark matte channel: a dark floor with an
            // occlusion band along the wall that stands toward the light, a lit wall on the opposite side, no emission.
            float2 awayDirE = -ld.xy;
            float emE, wE;
            spMarkInfo(q, hm, emE, wE);
            float dE = min(spMarkDepth, 0.45 * wE);
            float d0E = spMarkD(q, hm);
            float inkE = 1.0 - spSS(-e, e, d0E);
            float d1E = spMarkD(q + awayDirE * dE, hm);
            float ink1E = 1.0 - spSS(-e, e, d1E);
            float3 faceE = hubCol * 1.6 + mat.f0 * 0.10 * kSpinnerLight * mat.dim;   // brighter polished face so the cut reads
            float3 floorE = mat.f0 * 0.02 * kSpinnerLight * mat.dim * (1.0 - 0.5 * (1.0 - spSS(0.0, 0.4 * dE, -d1E)));
            float wallA = inkE * (1.0 - ink1E);
            float3 wallE = mat.f0 * 0.30 * kSpinnerLight * mat.dim * mix(0.4, 1.0, ld.z);
            float3 chan = mix(floorE, wallE, wallA);
            hubCol = mix(faceE, chan, inkE);
            } else if (!isRaised) {   // lit finish: the mark is cut straight into the continuous hub face as glowing channels
            float2 lightDir = ld.xy;
            float2 awayDir = -lightDir;

            // Laser-cut channel: floor lit from the bottom, a wall on the side away from the light,
            // an engraved-edge pair on the rim, and a faint blue spill on the surrounding face.
            float emL, wL;
            spMarkInfo(q, hm, emL, wL);
            float dEff = min(spMarkDepth, 0.45 * wL);       // thin strokes: depth <= 45% of width
            float3 glow = spMonoColor * emL * mat.glow;
            float d0 = spMarkD(q, hm);
            float ink0 = 1.0 - spSS(-e, e, d0);
            float d1 = spMarkD(q + awayDir * dEff, hm);
            float ink1 = 1.0 - spSS(-e, e, d1);

            // Rim (outside the cut, ~1.25 px): bright chamfer on the lower-right edge, dark line on
            // the upper-left edge.
            float rimW = 1.25 * e;
            float hiRim = (1.0 - ink0) * (1.0 - spSS(-e, e, spMarkD(q - awayDir * rimW, hm)));
            float loRim = (1.0 - ink0) * (1.0 - spSS(-e, e, spMarkD(q + awayDir * rimW, hm)));
            float3 metalHi = mat.f0 * kSpinnerLight * mat.dim;
            hubCol = mix(hubCol, hubCol + metalHi * 0.9 * ld.z, hiRim);
            hubCol *= 1.0 - 0.75 * loRim;

            // Faint blue spill on the hub face, falling off ~0.03 R from the strokes.
            float wash = (1.0 - ink0) * (1.0 - spSS(0.0, 0.03, d0));
            hubCol += glow * 0.06 * wash * wash;

            // Floor: inner shadow along the wall-side edge, brighter band on the opposite edge.
            float shade = 1.0 - 0.65 * (1.0 - spSS(0.0, 0.4 * dEff, -d1));
            float band = 1.0 + 0.30 * (1.0 - spSS(0.0, 0.5 * dEff, -d0));
            float3 floorCol = glow * shade * band;
            hubCol = mix(hubCol, floorCol, ink0);

            // Wall: dark body metal, lighter at the top rim, darker toward the floor with
            // the floor's glow bouncing near the bottom.
            float wallA = ink0 * (1.0 - ink1);
            float tW = saturate(d1 / max(dEff, 1e-5));       // 0 at the floor, 1 at the rim
            float3 wallMetal = mat.f0 * 0.22 * kSpinnerLight * mat.dim;
            float3 wallCol = mix(wallMetal * 0.5 + glow * 0.35, wallMetal * 1.5, spSS(0.0, 1.0, tW));
            hubCol = mix(hubCol, wallCol, wallA);
            } else {
            // Raised finish: plain polished hub; the mark stands proud as a low relief with a
            // bright satin top face, a bright bevel facing the light (upper left), a dark bevel on
            // the lower right and a short soft cast shadow on the hub face. No emission.
            float2 lightDir = ld.xy;
            float emL, wL;
            spMarkInfo(q, hm, emL, wL);
            float d0 = spMarkD(q, hm);
            float ink0 = 1.0 - spSS(-e, e, d0);
            // Cast shadow on the hub face along the lower right of each stroke.
            float shF = (1.0 - ink0) * (1.0 - spSS(0.0, spMarkRaise * 1.2, spMarkD(q + lightDir * spMarkRaise * 0.6, hm)));
            hubCol *= 1.0 - 0.55 * shF * ld.z;
            // Bevel widths: about the relief height, at least a pixel, never more than 22% of the
            // stroke width per side (>= 55% stays top face).
            float bw = min(max(0.6 * spMarkRaise, 1.1 * e), 0.225 * wL);
            float inkL = 1.0 - spSS(-e, e, spMarkD(q + lightDir * bw, hm));
            float inkA = 1.0 - spSS(-e, e, spMarkD(q - lightDir * bw, hm));
            float bevHi = ink0 * (1.0 - inkL);
            float bevLo = ink0 * (1.0 - inkA) * (1.0 - bevHi);
            // Top face: lightened, slightly desaturated body metal with a soft directional sheen.
            float lum = dot(mat.f0, float3(0.33));
            float3 satin = mix(mat.f0, float3(lum), mix(0.12, 0.8, mat.film));
            satin = mix(satin, float3(1.0), 0.5) * 1.35;
            float topSheen = 0.85 + 0.45 * spSS(-0.6, 0.8, dot(q / hubR, lightDir));
            float tone = 1.0;
            if (hm > 0.5) {
                float m0 = spMonoD(q, 0), m1 = spMonoD(q, 1), m2 = spMonoD(q, 2);
                int pi = (m0 <= m1 && m0 <= m2) ? 0 : (m1 <= m2 ? 1 : 2);
                tone = spRaisePieceTone[pi];
            }
            float3 topCol = satin * topSheen * tone * kSpinnerLight * mat.dim;
            topCol = mix(topCol, topCol * mix(1.0, 2.0, ld.z) + 0.04 * ld.z, bevHi);     // face turned to the light
            topCol *= 1.0 - 0.8 * bevLo;                          // face turned away
            hubCol = mix(hubCol, topCol, ink0);
            }   // raised
        }
    }
    return hubCol;
}

// ============================================================================
// Stepped cross-section. The visible face's local frame: x right, y up in the face, z the face's outward axis,
// origin = puck center. Levels: outer face plane z = T/2 (annulus spStepR..1), web plane z = T/2 - spWebRecess (annulus
// hub..spStepR, carries the slits), hub top plane z = T/2 + spHubProud (disc spHubR). Between them: the step wall (a cylinder of
// radius spStepR seen from inside) and the hub wall (a cylinder of radius spHubR seen from outside). The nearest hit along the
// pixel's ray is found in closed form (no marching).
// ============================================================================
struct SpHit { int kind; float3 P; float3 D; };   // kind: 0 none, 1 outer face, 2 web, 3 hub top, 4 step wall, 5 hub wall

struct SpCtx {
    float2 cs; float mir; SpMat mat; float3 tint; float e; float2 px; float3 ld; float3 Lk; float3 camW;
    float angle; float sweep; int N; float emBoost; bool raised; bool engraved; float hm; float fade;
};

static inline void spRayLocal(float2 qsP, float2 cs, thread float3 &Ol, thread float3 &Dl) {
    float3 rayO = float3(qsP * (1.0 - spPerspective), spCamDist);
    float3 rayD = float3(qsP * spPerspective, -spCamDist);
    Ol = float3(rayO.x, rayO.y * cs.x - rayO.z * cs.y, rayO.y * cs.y + rayO.z * cs.x);
    Dl = float3(rayD.x, rayD.y * cs.x - rayD.z * cs.y, rayD.y * cs.y + rayD.z * cs.x);
}

static inline float3 spKeyLocal(float2 cs) {
    float3 K = normalize(spKeyL);
    return float3(K.x, K.y * cs.x - K.z * cs.y, K.y * cs.y + K.z * cs.x);
}

static inline float3 spWorldP(float3 Pl, float2 cs) {
    return float3(Pl.x, Pl.y * cs.x + Pl.z * cs.y, -Pl.y * cs.y + Pl.z * cs.x);
}

static inline SpHit spSelect(float3 Ol, float3 Dl) {
    SpHit h; h.kind = 0; h.P = float3(0.0); h.D = Dl;
    float zo = 0.5 * spThickness, zw = zo - spWebRecess, zh = zo + spHubProud;
    float tBest = 1e9;
    float dlen = length(Dl);
    bool down = Dl.z < -0.002 * dlen;                 // the ray travels toward the face's back: the face side is visible
    float2 o2 = Ol.xy, d2 = Dl.xy;
    float a2 = dot(d2, d2), bq = dot(o2, d2), oo = dot(o2, o2);
    float rhoA = 1e9;
    if (down) {
        float tA = (zo - Ol.z) / Dl.z;
        rhoA = length(o2 + tA * d2);
        if (rhoA >= spStepR && rhoA < 1.25) { h.kind = 1; tBest = tA; }
        if (rhoA < spStepR) {                         // the ray enters the well through the opening
            float tW = (zw - Ol.z) / Dl.z;
            if (length(o2 + tW * d2) <= spStepR && tW < tBest) { h.kind = 2; tBest = tW; }
            if (a2 > 1e-8) {
                float disc = bq * bq - a2 * (oo - spStepR * spStepR);
                if (disc > 0.0) {
                    float tD = (-bq + sqrt(disc)) / a2;   // far root: the wall on the far side of the well
                    float zD = Ol.z + tD * Dl.z;
                    if (zD >= zw && zD <= zo && tD < tBest) { h.kind = 4; tBest = tD; }
                }
            }
        }
        float tH = (zh - Ol.z) / Dl.z;
        if (length(o2 + tH * d2) <= spHubR && tH < tBest) { h.kind = 3; tBest = tH; }
    }
    if (a2 > 1e-8) {
        float disc = bq * bq - a2 * (oo - spHubR * spHubR);
        if (disc > 0.0) {
            float tE = (-bq - sqrt(disc)) / a2;       // near root: the outside of the hub cylinder
            float zE = Ol.z + tE * Dl.z;
            bool reach = zE >= zo || (down && rhoA < spStepR);   // below the outer face only through the opening
            if (tE > 0.0 && zE >= zw && zE <= zh && reach && tE < tBest) { h.kind = 5; tBest = tE; }
        }
    }
    if (h.kind != 0) h.P = Ol + tBest * Dl;
    return h;
}

// Key light's pull along the face for a shadow caster that is h higher than the receiver: the shadow of a point lands at
// xy - h * sv. sv is clamped so a grazing key does not throw shadows across the whole face; sk fades the key's shadows out as
// its normal component goes to zero (a face tipped away from the key is not shadowed by it, it is simply unlit).
static inline float3 spKeyShadowDir(float3 Lk) {
    float2 sv = Lk.xy / max(Lk.z, 0.12);
    float l = length(sv);
    if (l > 0.9) sv *= 0.9 / l;
    return float3(sv, spSS(-0.05, 0.45, Lk.z));
}

// The web: satin metal at the bottom of the well, with ambient occlusion in the corners (the step wall and the hub wall) and the
// soft cast shadows of the outer wheel's inner edge and of the hub, both along the projected key light.
static inline float3 spWebBase(float3 P, float e, thread const SpCtx &C, float3 v) {
    float2 q = P.xy;
    float r = length(q);
    float2 rs = r > 1e-4 ? q / r : float2(1.0, 0.0);
    float3 n = float3(0.0, 0.0, 1.0);
    float a1 = saturate(1.3 - 70.0 * e);
    n.xy += rs * (0.06 * a1 * spVN(r * 70.0 + 5.0));
    n.xy += rs * ((r - 0.49) * 1.1);                       // shallow dish: the reflection drifts across the web
    float3 col = spMetalT(n, C.mat.deep * 2.3, C.tint, 0.8, rs, 60.0, C.mat, C.cs, v);
    col = spFilm(col, C.mat, r, rs, n);
    col *= 1.0 - 0.55 * exp(-max(spStepR - r, 0.0) / 0.04);       // corner at the foot of the step wall
    col *= 1.0 - 0.60 * exp(-max(r - spHubR, 0.0) / 0.04);        // corner at the foot of the hub
    float3 sd = spKeyShadowDir(C.Lk);
    float wS = spSS(-0.012, 0.022, length(q + spWebRecess * sd.xy) - spStepR);                    // under the outer wheel as seen from the key
    float hS = 1.0 - spSS(spHubR - 0.025, spHubR + 0.03, length(q + (spWebRecess + spHubProud) * sd.xy));   // under the hub's shadow
    col *= (1.0 - 0.80 * sd.z * wS) * (1.0 - 0.75 * sd.z * hS);
    return col;
}

// The step wall: the inner face of the outer wheel's opening, a vertical cylinder wall with a small polished chamfer at its top
// edge. Lit by the world normal; dark at its foot; the key reaches it only where the ray toward it leaves the well.
static inline float3 spStepWallCol(float3 P, thread const SpCtx &C, float3 v) {
    float zo = 0.5 * spThickness, zw = zo - spWebRecess;
    float2 inw = -P.xy / max(length(P.xy), 1e-4);
    float dz = zo - P.z;
    float tcm = 1.0 - spSS(0.0, spStepChamfer, dz);
    float3 nl = normalize(mix(float3(inw, 0.0), normalize(float3(inw * 0.7, 0.7)), tcm));
    float3 nw = spTiltN(nl, C.cs);
    float3 col = spMetal(nw, C.mat.f0 * mix(0.78, 0.72, tcm), C.tint, 0.0, float2(1.0, 0.0), mix(90.0, 220.0, tcm), C.mat, v);
    col *= mix(0.30, 1.0, spSS(0.0, spWebRecess, P.z - zw));      // occlusion at the foot
    float3 sd = spKeyShadowDir(C.Lk);
    float lit = (1.0 - spSS(spStepR - 0.02, spStepR + 0.02, length(P.xy + dz * sd.xy))) * sd.z;
    col *= mix(0.5, 1.0, lit);
    return col;
}

// The hub's side wall: a polished cylinder standing up from the web.
static inline float3 spHubWallCol(float3 P, thread const SpCtx &C, float3 v) {
    float zw = 0.5 * spThickness - spWebRecess;
    float2 outw = P.xy / max(length(P.xy), 1e-4);
    float3 nw = spTiltN(float3(outw, 0.0), C.cs);
    float3 col = spMetal(nw, C.mat.f0 * 0.45, C.tint, 0.0, float2(1.0, 0.0), 240.0, C.mat, v);
    col *= mix(0.30, 1.0, spSS(0.0, spWebRecess, P.z - zw));      // occlusion where it meets the web
    return col;
}

// Shades the nearest front surface of a hit: premultiplied rgb + coverage. The outer face and the web carry the rotating features
// (rods, slits) and are averaged over the motion-blur samples; the rest is static.
static inline float4 spShadeHit(SpHit h, thread const SpCtx &C) {
    if (h.kind == 0) return float4(0.0);
    float3 Pw = spWorldP(h.P, C.cs);
    float3 v = normalize(C.camW - Pw);
    float2 q = h.P.xy;
    if (h.kind == 1 || h.kind == 2) {
        float2 qd = float2(q.x, C.mir * q.y);
        int reg = 2;
        float3 base;
        float2 wallDelta = float2(0.0);
        if (h.kind == 1) {
            base = spFaceBase(qd, C.e, C.mat, C.tint, 1.0, C.cs, C.mir, v, C.px, C.ld, reg);
        } else {
            base = spWebBase(h.P, C.e, C, v);
            reg = 4;
            float dzs = min(h.D.z, -0.02 * length(h.D));
            wallDelta = (spThickness - 2.0 * spWebRecess) * h.D.xy / (-dzs);   // lateral travel of the ray through the web
        }
        float4 acc = float4(0.0);
        for (int i = 0; i < C.N; ++i) {
            float f = C.N > 1 ? (float(i) / float(C.N - 1) - 0.5) : 0.0;
            acc += spBody(qd, C.angle + C.sweep * f, C.e, C.mat, C.cs, wallDelta, C.mir, base, reg, C.emBoost, C.px, C.ld);
        }
        return acc * (C.fade / float(C.N));
    }
    if (h.kind == 3) {
        return float4(spHubTop(q, C.e, C.hm, C.raised, C.engraved, C.mat, C.tint, C.cs, v, C.ld), 1.0) * C.fade;
    }
    if (h.kind == 4) return float4(spStepWallCol(h.P, C, v), 1.0);
    return float4(spHubWallCol(h.P, C, v), 1.0);
}

fragment float4 spinner_fs(FSQOut in [[stage_in]],
                           constant ShaderInputs &input [[buffer(0)]],
                           constant PaletteUniform &palette [[buffer(1)]],
                           constant SpinnerUniforms &u [[buffer(2)]]) {
    // Clip space (+y up), centered on the (possibly offset) object, aspect-correct,
    // normalized so the outer radius is ~1.
    float2 clip = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    float aspect = max(u.aspect, 1e-3);
    float R = 0.6 * min(1.0, aspect) * (u.zoom > 0.0 ? u.zoom : 1.0);
    float2 qs = (float2(clip.x * aspect, clip.y) - float2(u.offsetX * aspect, u.offsetY)) / R;   // screen frame
    // Two-sided disc. u.tilt is one full turn. For tilt in (90, 270) degrees the BACK face shows: it is
    // handled as the same slab seen in a local frame turned over about the horizontal axis (local tilt
    // = tilt - 180, signed). Both frames pivot about the puck center (see the qs.y shift below).
    // The disc features are evaluated at the point mirrored in y (disc coords = (u, -v)), which makes the
    // back layout the left-right mirror of the front, the rotation read reversed on screen, and the tube
    // colors run the other way round. The hub is static and drawn in the local (view) frame, upright.
    float t0 = fmod(u.tilt, 2.0 * M_PI_F);
    if (t0 < 0.0) t0 += 2.0 * M_PI_F;
    bool back = t0 > 0.5 * M_PI_F && t0 < 1.5 * M_PI_F;
    float te = back ? t0 - M_PI_F : (t0 >= 1.5 * M_PI_F ? t0 - 2.0 * M_PI_F : t0);   // signed tilt of the visible face
    float tc = cos(te), ts = sin(te);
    float2 cs = float2(tc, ts);                              // true (cos, sin) of the visible face's tilt
    float mir = back ? -1.0 : 1.0;
    // The puck turns about its own center (T/2 behind the visible face plane, for front and back alike):
    // the visible face plane is at +T/2 along the axis, so its center sits at screen y = (T/2) sin(tilt).
    // The geometry is ray based. The pinhole camera sits on +z at spCamDist and looks at the puck center; the ray
    // through the pixel is expressed in the visible face's local frame (x right, y up in the face, z the face's outward axis, origin =
    // puck center), so the pivot is the puck center at every tilt, with or without perspective. The point on the plane z = lateral
    // (1 - p z / D) of the pixel has the same screen coordinate as before at the center plane, so the size there is unchanged.
    // Perspective enlarges the near side of the tilted puck, which would walk the silhouette's center off the anchor (about 0.07 R at
    // 45 degrees). The vertical extremes of the two rim circles are at sin = +-1 (y' is monotonic in that parameter), so the silhouette's
    // vertical center is known in closed form; the view is shifted by it so the silhouette stays centered at every tilt. (The
    // puck's own 3D center then sits that far off the anchor; the shift is 0 face-on, edge-on and with spPerspective = 0.)
    {
        float zc2 = 0.5 * spThickness;
        float ymax = -1e9, ymin = 1e9;
        for (int k = 0; k < 4; ++k) {
            float sgn = (k & 1) ? -1.0 : 1.0, sig = (k & 2) ? -1.0 : 1.0;
            float yy = sgn * zc2 * ts + tc * sig, zz = sgn * zc2 * tc - ts * sig;
            float yp = yy * mix(1.0, spCamDist / max(spCamDist - zz, 0.5), spPerspective);
            ymax = max(ymax, yp); ymin = min(ymin, yp);
        }
        qs.y += 0.5 * (ymax + ymin);
    }
    float3 camW = float3(0.0, 0.0, spCamDist);
    float3 rayO = float3(qs * (1.0 - spPerspective), spCamDist);
    float3 rayD = float3(qs * spPerspective, -spCamDist);
    float3 Ol = float3(rayO.x, rayO.y * tc - rayO.z * ts, rayO.y * ts + rayO.z * tc);
    float3 Dl = float3(rayD.x, rayD.y * tc - rayD.z * ts, rayD.y * ts + rayD.z * tc);
    float zFace = 0.5 * spThickness;
    float dzs = min(Dl.z, -0.02 * length(Dl));               // face plane divisor, kept off zero near edge-on
    float tFace = (zFace - Ol.z) / dzs;
    float3 PhL = Ol + tFace * Dl;                            // face plane hit, local frame
    float2 q = PhL.xy;
    float faceFade = spSS(0.02, 0.10, -Dl.z / length(Dl));  // the face is a sliver near edge-on: fade it, the wall remains
    float fxw = fwidth(q.x), fyw = fwidth(q.y);
    float e = sqrt(fxw * fyw);                       // disc-space AA width (geometric mean; = plain at tilt 0)
    float es = max(fwidth(qs.x), fwidth(qs.y));      // screen-space AA width
    float2 wallDelta = spThickness * Dl.xy / (-dzs); // lateral travel of the ray through the thickness (face frame)
    float3 PhW = float3(PhL.x, PhL.y * tc + PhL.z * ts, -PhL.y * ts + PhL.z * tc);
    float3 vw = normalize(camW - PhW);               // unit direction to the camera (the geometry camera), for the face's lighting
    float3 ld = spLightLocal(cs);
    // The shadow and silhouette helpers below work in orthographic screen coordinates relative to the face center: the ground
    // plane (a distance H behind the puck center) sees the same pinhole, so its coordinates are scaled by the perspective factor.
    float2 qsS = qs * (1.0 + spPerspective * 0.5 / spCamDist);
    qsS.y -= zFace * ts;
    bool isRaised = u.hubFinish > 0.5 && u.hubFinish < 1.5;
    bool isEngraved = u.hubFinish > 1.5;
    // The hub's back carries the other mark.
    float hm = back ? (u.hubMark < 0.5 ? 1.0 : 0.0) : u.hubMark;

    SpMat mat = spMaterial(u.metal);
    mat.dim *= u.roomLight;
    mat.room = u.roomLight;
    mat.glow = u.glowBrightness;
    float3 tint = samplePalette(palette, 0.62);
    tint = mix(float3(dot(tint, float3(0.33))), tint, 1.2);
    tint = max(tint, 0.0);

    // --- drop shadow geometry: the disc floats H above a ground plane parallel to the screen ---
    // A top-face point (X,Y,0) sits at screen (X, Y c) height H - Y s above the ground and its
    // shadow lands at that + shOff * height / H. Solve for the disc point per ground pixel.
    const float2 shOff = float2(0.102, -0.126) * u.shadowDistance;   // 1.2x the old plate offset (the puck is taller), times the setting
    const float H = 0.5;
    float sa = fabs(ts);
    float tEff = spShadowThickness * saturate(3.0 * sa);     // reduced thickness so shadow slits stay open
    float denom0 = tc - shOff.y * ts / H;                    // goes through 0 where the light grazes the face
    float denom = (denom0 < 0.0 ? -1.0 : 1.0) * max(fabs(denom0), 0.12);
    float shadowFade = spSS(0.02, 0.20, fabs(denom0));
    float Yt = (qsS.y - shOff.y) / denom;
    float2 sqT = float2(qsS.x - shOff.x + shOff.x * Yt * ts / H, Yt);
    float kT = clamp((H - Yt * ts) / H, 0.6, 2.0);
    float Yb = (qsS.y + tEff * ts - shOff.y * (1.0 - tEff * tc / H)) / denom;
    float2 sqB = float2(qsS.x - shOff.x * (1.0 - tEff * tc / H) + shOff.x * Yb * ts / H, Yb);
    float kB = clamp((H - tEff * tc - Yb * ts) / H, 0.6, 2.0);

    // --- rotating body, with motion blur (longer shutter so fast spins smear to rings) ---
    float sweep = u.velocity * u.frameDt * 1.5 * u.spinBlur;
    int N = clamp(int(ceil(fabs(sweep) / 0.004)), 1, 96);
    int shStride = sa < 1e-3 ? 1 : max(1, N / 24);          // tilted: shadow sampled sparsely (soft anyway)
    float emBoost = 1.0 + spEmBoost * spSS(0.02, 0.45, fabs(sweep));
    float4 body = float4(0.0);
    float4 wallAcc = float4(0.0);   // rim wall, averaged over the same motion-blur samples
    SpRimBase rimB; rimB.cov = 0.0;
    rimB = spRimMakeBase(Ol, Dl, es, cs, mat, tint, mir, camW);   // angle-independent rim work: once per pixel
    bool hasWall = rimB.cov > 0.0;
    float2 shTop = float2(0.0), shBot = float2(0.0); float shN = 0.0;
    for (int i = 0; i < N; ++i) {
        float f = N > 1 ? (float(i) / float(N - 1) - 0.5) : 0.0;
        float ang = u.angle + sweep * f;
        if (hasWall) wallAcc += spRimSample(rimB, ang, mat, emBoost);
        if (i % shStride == 0) {
            shTop += spDiscCover(float2(sqT.x, mir * sqT.y), ang, kT * u.shadowSpread, 1.0);
            if (sa > 1e-3) shBot += spDiscCover(float2(sqB.x, mir * sqB.y), ang, kB * u.shadowSpread, 1.0 - spRimChamfer);
            shN += 1.0;
        }
    }
    shTop /= shN; shBot /= shN;
    // --- front surfaces: nearest analytic hit among the outer face, the web, the hub top, the step wall and the hub wall ---
    SpCtx C;
    C.cs = cs; C.mir = mir; C.mat = mat; C.tint = tint; C.e = e; C.px = float2(fxw, fyw); C.ld = ld; C.Lk = spKeyLocal(cs);
    C.camW = camW; C.angle = u.angle; C.sweep = sweep; C.N = N; C.emBoost = emBoost; C.raised = isRaised; C.engraved = isEngraved; C.hm = hm; C.fade = faceFade;
    SpHit h0 = spSelect(Ol, Dl);
    {
        // Occlusion edges between the levels are antialiased by re-selecting at four sub-pixel taps; only where the nearest surface
        // differs between the taps is the (costlier) shading repeated per tap. (Derivative-based widths come from the centre.)
        const float2 tapOff[4] = { float2(0.40, 0.15), float2(-0.15, 0.40), float2(-0.40, -0.15), float2(0.15, -0.40) };
        SpHit ht[4];
        bool mixedKinds = false;
        for (int k = 0; k < 4; ++k) {
            float3 o, d;
            spRayLocal(qs + tapOff[k] * es, cs, o, d);
            ht[k] = spSelect(o, d);
            mixedKinds = mixedKinds || (ht[k].kind != h0.kind);
        }
        if (!mixedKinds) {
            body = spShadeHit(h0, C);
        } else {
            body = spShadeHit(h0, C);
            for (int k = 0; k < 4; ++k) body += spShadeHit(ht[k], C);
            body *= 0.2;
        }
    }
    // Only parts of the disc that are above the ground cast a shadow (a steep tilt would otherwise throw a stray lens
    // of 'shadow' up-left from the part that dips below the ground plane). Constant per pixel: applied outside the loop.
    shTop *= spSS(0.0, 0.14 * H, H - Yt * ts);
    shBot *= spSS(0.0, 0.14 * H, H - tEff * tc - Yb * ts);
    float2 shBoth = sa > 1e-3 ? max(shTop, shBot) : shTop;
    // Umbra near the object, penumbra far from it: the sharp-edged copy of the shadow counts only close to the silhouette.
    float near = 1.0 - spSS(0.0, 0.24, spSilD(qsS, cs));
    float shadow = shadowFade * (0.46 * shBoth.x + 0.26 * shBoth.y * near);
    // Contact shadow: a tight, darker soft band directly under the lowest rim silhouette (side and steep views).
    if (sa > 1e-3) {
        float sgn = ts < 0.0 ? -1.0 : 1.0;
        float cxq = qsS.x;
        float rb = sgn > 0.0 ? 1.0 - spRimChamfer : 1.0;
        float yl = sgn > 0.0 ? -sqrt(max(rb * rb - cxq * cxq, 0.0)) * tc - spThickness * sa
                             : -sqrt(max(1.0 - cxq * cxq, 0.0)) * tc;
        float dyl = yl - qsS.y;                            // > 0 below the silhouette
        float contact = spSS(-0.01, 0.0, dyl) * (1.0 - spSS(0.0, 0.07, dyl)) * (1.0 - spSS(0.6, 1.0, fabs(cxq)));
        shadow = 1.0 - (1.0 - shadow) * (1.0 - 0.55 * saturate(sa * 2.0) * contact);
    }

    // Shadow darkness setting (0.48 = the original look).
    shadow = saturate(shadow * (u.shadowDarkness / 0.48));

    // Rim wall: composited under the top face.
    if (hasWall) {
        float4 wall = wallAcc / float(N);
        body = body + (1.0 - body.a) * wall;
    }

    // Composite (premultiplied): body (with the rim under it) over shadow over background.
    float3 rgb = body.rgb;
    float a = body.a;
    a = a + (1.0 - a) * shadow;   // black shadow, premultiplied rgb = 0
    return float4(rgb, a);
}

// ============================================================================
// RealityKit spinner hand-off. The RealityKit render arrives as a premultiplied rgba16Float texture;
// these two fragment shaders turn the shadow-by-difference renders into a soft coverage and copy the result into the
// app's scene texture.
// ============================================================================

// Half-resolution coverage of the puck's shadow. Outside the puck: c = (B - A) / (B - B0) (B = ground lit by the shadow
// light, B0 = ground without it, A = puck + ground), measured, so the shadow's shape follows the puck's real depth.
// Under the puck the measurement is meaningless; the ground there is in the puck's own shadow, so the coverage is the
// puck silhouette translated by `off` (half-resolution pixels, toward lower right), the same offset a flat disc casts.
// Output (coverage, 1); blurred afterwards and read by rk_copy_fs.
struct RKCovUniforms { float2 off; float alphaThreshold; };
fragment float4 rk_shadow_cov_fs(FSQOut in [[stage_in]],
                                 constant RKCovUniforms &cu [[buffer(0)]],
                                 texture2d<float> A  [[texture(0)]],
                                 texture2d<float> B  [[texture(1)]],
                                 texture2d<float> B0 [[texture(2)]],
                                 texture2d<float> P  [[texture(3)]],
                                 sampler samp        [[sampler(0)]]) {
    int2 hp = int2(in.position.xy);
    int2 hs = int2(A.get_width(), A.get_height());
    int2 fs = int2(P.get_width(), P.get_height());
    float3 a = A.read(uint2(hp)).rgb, b = B.read(uint2(hp)).rgb, b0 = B0.read(uint2(hp)).rgb;
    float la = (a.r + a.g + a.b) / 3.0, lb = (b.r + b.g + b.b) / 3.0, lb0 = (b0.r + b0.g + b0.b) / 3.0;
    float covered = 0.0;
    for (int dy = -2; dy <= 2 && covered < 0.5; ++dy) {
        for (int dx = -2; dx <= 2 && covered < 0.5; ++dx) {
            int2 q = hp + int2(dx, dy);
            if (q.x < 0 || q.y < 0 || q.x >= hs.x || q.y >= hs.y) continue;
            for (int s = 0; s < 4; ++s) {
                int2 fp = q * 2 + int2(s & 1, s >> 1);
                if (fp.x < fs.x && fp.y < fs.y && P.read(uint2(fp)).a > cu.alphaThreshold) { covered = 1.0; break; }
            }
        }
    }
    float den = lb - lb0;
    float c = den > 1e-5 ? clamp((lb - la) / den, 0.0, 1.0) : 0.0;
    float valid = 1.0 - covered;
    // translated silhouette (slightly fattened by the 3x3 search so thin slits fill in)
    int2 hq = hp - int2(round(cu.off));
    float sil = 0.0;
    for (int dy = -1; dy <= 1 && sil < 0.5; ++dy) {
        for (int dx = -1; dx <= 1 && sil < 0.5; ++dx) {
            int2 q = hq + int2(dx, dy);
            if (q.x < 0 || q.y < 0 || q.x >= hs.x || q.y >= hs.y) continue;
            for (int s = 0; s < 4; ++s) {
                int2 fp = q * 2 + int2(s & 1, s >> 1);
                if (fp.x < fs.x && fp.y < fs.y && P.read(uint2(fp)).a > cu.alphaThreshold) { sil = 1.0; break; }
            }
        }
    }
    return float4(max(c * valid, sil), 1.0, 0.0, 1.0);
}

struct RKCopyUniforms {
    float2 sceneSize;      // scene texture size in pixels
    float2 regionOrigin;   // top-left of the puck-centred square region, scene pixels
    float2 regionSize;     // side of that region on screen, pixels (the render target is mapped onto it)
    float shadowOpacity;
    float useShadow;
};

// Premultiplied copy of the RealityKit render into the scene texture. With useShadow the soft shadow raises ONLY the
// alpha (the shadow carries no colour), like the shader spinner's per-pixel-alpha output.
fragment float4 rk_copy_fs(FSQOut in [[stage_in]],
                           texture2d<float> P [[texture(0)]],
                           texture2d<float> S [[texture(1)]],
                           sampler samp       [[sampler(0)]],
                           constant RKCopyUniforms &u [[buffer(0)]]) {
    // Scene pixel -> region uv. Outside [0,1] the sampler returns zero (clampToZero), so nothing outside the region is drawn.
    float2 uv = (in.uv * u.sceneSize - u.regionOrigin) / u.regionSize;
    float4 p = P.sample(samp, uv);
    float a = p.a;
    // RealityKit renders linear light. The app's scene values are display-referred, so apply a soft shoulder
    // (knee 0.55) and the sRGB encode to the straight colour, then premultiply by the puck's own coverage.
    float3 sc = p.a > 1e-5 ? max(p.rgb / p.a, 0.0) : float3(0.0);
    const float knee = 0.55, span = 1.0 - knee;
    float3 sh3 = select(knee + span * (1.0 - exp(-(sc - knee) / span)), sc, sc <= knee);
    float3 enc = select(1.055 * pow(sh3, 1.0 / 2.4) - 0.055, 12.92 * sh3, sh3 <= 0.0031308);
    p.rgb = enc * p.a;
    if (u.useShadow > 0.5) {
        float2 ns = S.sample(samp, uv).rg;
        float sh = ns.y > 0.02 ? min(1.0, ns.x / ns.y) : 0.0;
        a = a + (1.0 - a) * sh * u.shadowOpacity;
    }
    return float4(p.rgb, a);
}
