#include <metal_stdlib>
using namespace metal;

constant float MAX_TILT = 0.84106867; // acos(1.0 / 1.5)
constant float3 DARK = float3(0.003, 0.004, 0.005);

struct Uniforms {
    float2 imageSize;
    float2 cover;
    float aspect;
    float turn;
    float blurStrength;
    float reflectionIntensity;
    float sampleCount;   // adaptive quality: 12 / 20 / 32 (float for Swift layout parity)
    float motionBoost;   // velocity-aware extra blur radius (0 = still, larger = fast close)
    float sideVoid;      // 0 = frame keeps full width, 1 = physical default, >1 = deeper side blackout
    float effectMode;
    float eyeDistance;
    float foldRadians;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut foldVertex(uint vid [[vertex_id]]) {
    const float2 positions[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0)
    };
    
    VertexOut out;
    float2 pos = positions[vid];
    out.position = float4(pos, 0.0, 1.0);
    // UV origin: (0,0) at top-left, (1,1) at bottom-right
    out.uv = float2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5);
    return out;
}

// True gaussian downsample: binomial 3x3 (σ ≈ 1.2 source texels), rendered
// once per texture upload into each mip level. Chained levels double σ, so
// mip k holds a genuine blur of σ ≈ 1.2 · 2^k texels — not a box average.
struct PyramidParams {
    float2 srcTexel;
    float srcLod;
    float pad;
};

fragment float4 gaussianDownsampleFragment(VertexOut in [[stage_in]],
                                           texture2d<float> tex [[texture(0)]],
                                           sampler s [[sampler(0)]],
                                           constant PyramidParams &p [[buffer(0)]]) {
    float2 uv = in.uv;
    float3 acc = tex.sample(s, uv, level(p.srcLod)).rgb * 4.0;
    acc += tex.sample(s, uv + float2( p.srcTexel.x, 0.0), level(p.srcLod)).rgb * 2.0;
    acc += tex.sample(s, uv + float2(-p.srcTexel.x, 0.0), level(p.srcLod)).rgb * 2.0;
    acc += tex.sample(s, uv + float2(0.0,  p.srcTexel.y), level(p.srcLod)).rgb * 2.0;
    acc += tex.sample(s, uv + float2(0.0, -p.srcTexel.y), level(p.srcLod)).rgb * 2.0;
    acc += tex.sample(s, uv + float2( p.srcTexel.x,  p.srcTexel.y), level(p.srcLod)).rgb;
    acc += tex.sample(s, uv + float2(-p.srcTexel.x,  p.srcTexel.y), level(p.srcLod)).rgb;
    acc += tex.sample(s, uv + float2( p.srcTexel.x, -p.srcTexel.y), level(p.srcLod)).rgb;
    acc += tex.sample(s, uv + float2(-p.srcTexel.x, -p.srcTexel.y), level(p.srcLod)).rgb;
    return float4(acc / 16.0, 1.0);
}

inline float3 sampleSmoothMatteBlur(texture2d<float> tex,
                                    sampler s,
                                    float2 uv,
                                    float radius,
                                    float2 cover,
                                    float2 uiPixel,
                                    float2 screenCoord,
                                    int maxSamples) {
    float2 tuv = (uv - 0.5) * cover + 0.5;

    // When radius is near zero, return razor-sharp native Retina sample at level 0
    if (radius <= 0.15) {
        return tex.sample(s, tuv, level(0.0)).rgb;
    }

    // REAL GAUSSIAN BLUR via the pyramid (see gaussianDownsampleFragment):
    // each mip level is a true binomial blur with σ doubling per level, so
    // trilinear sampling at a radius-mapped LOD yields a smooth continuous
    // gaussian of ANY width. The old approach widened a sparse spatial tap
    // disc with radius — which is DISPERSION, not blur: bright text appeared
    // as multiple discrete ghost copies, plus frosted grain and white haze.
    float lod = clamp(log2(max(1.0, radius * 0.25)), 0.0, 5.0);

    // Tiny Vogel disc at the CURRENT mip's texel scale (±1.2 texels): dense,
    // heavily overlapping taps that polish trilinear level steps and edges —
    // the spread NEVER scales with radius, so dispersion cannot come back.
    float2 mipTexel = uiPixel * 0.5 * exp2(lod);

    // Minimal per-pixel micro-rotation to break residual ring banding.
    float rot = (fract(sin(dot(screenCoord, float2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.12;
    float cosRot = cos(rot);
    float sinRot = sin(rot);

    float3 accum = float3(0.0);
    float totalWeight = 0.0;

    constexpr int NUM_SAMPLES = 32;
    constexpr float GOLDEN_ANGLE = 2.39996323; // pi * (3.0 - sqrt(5.0))
    int activeSamples = clamp(maxSamples, 4, NUM_SAMPLES);

    for (int i = 0; i < NUM_SAMPLES; i++) {
        if (i >= activeSamples) { break; }
        float fi = float(i);
        float theta = fi * GOLDEN_ANGLE;
        float r = sqrt((fi + 0.5) / float(activeSamples));
        float uX = cos(theta);
        float uY = sin(theta);
        float dirX = uX * cosRot - uY * sinRot;
        float dirY = uX * sinRot + uY * cosRot;

        float2 offset = float2(dirX, dirY) * (r * 1.2 * mipTexel);
        float2 sampleUV = clamp(tuv + offset, 0.0, 1.0);
        float weight = exp(-2.3 * r * r);

        accum += tex.sample(s, sampleUV, level(lod)).rgb * weight;
        totalWeight += weight;
    }

    float3 blurred = accum / totalWeight;

    // Smooth transition from sharp to matte blur as fold begins
    float3 sharp = tex.sample(s, tuv, level(0.0)).rgb;
    return mix(sharp, blurred, smoothstep(0.0, 2.0, radius));
}

// Adapted from Elijah Semyonov's DuoLikeAnimation, DuoFold.metal (MIT).
// See ThirdParty/DuoLikeAnimation/LICENSE and INTEGRATION.md.
// Same fixed UI plane, eye-to-glass ray intersection, gap-based Vogel blur
// and attenuation. The phone's side hinge becomes the Mac's bottom hinge.
// Coordinates use a virtual 900-point screen height so blur/grain do not
// change with Retina resolution or a different preview size.
inline float3 duoSample(texture2d<float> tex, sampler s, float2 point,
                        float2 size, float2 cover) {
    if (any(point < 0.0) || any(point > size)) { return float3(0.0); }
    return tex.sample(s, (point / size - 0.5) * cover + 0.5, level(0.0)).rgb;
}

inline float4 duoMacFold(VertexOut in, texture2d<float> tex, sampler s,
                          constant Uniforms &u) {
    const float turn = clamp(u.turn, 0.0, 1.0);
    const float2 size = float2(max(u.aspect, 0.1), 1.0) * 900.0;
    const float2 p = in.uv * size;
    const float tilt = turn * clamp(u.foldRadians, 0.01, M_PI_F);
    if (tilt < 1e-5) { return float4(duoSample(tex, s, p, size, u.cover), 1.0); }

    const float d = size.y - p.y;
    const float3 glass = float3(p.x, size.y - d * cos(tilt), d * sin(tilt));
    const float3 eye = float3(size * 0.5, max(u.eyeDistance, 1.05) * size.y);
    const float depth = eye.z - glass.z;
    if (depth <= 1e-3) { return float4(0, 0, 0, 1); }
    const float t = eye.z / depth;
    float2 hit = eye.xy + (glass.xy - eye.xy) * t;
    // Existing macTilt art-direction control; 1 preserves upstream projection.
    hit.x = mix(p.x, hit.x, clamp(u.sideVoid, 0.0, 2.0));
    const float radius = 0.12 * max(u.blurStrength, 0.0) * glass.z;
    if (any(hit < -radius) || any(hit > size + radius)) { return float4(0, 0, 0, 1); }
    const float attenuation = max(1.0 - 0.015 * radius, 0.0);
    float3 color;
    if (radius < 0.5) {
        color = duoSample(tex, s, hit, size, u.cover);
    } else {
        const int taps = clamp(int(radius * 2.0), 6, 32);
        const float rotation = fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453) * 6.28318530718;
        float3 sum = float3(0.0);
        for (int i = 0; i < taps; ++i) {
            const float r = radius * sqrt((float(i) + 0.5) / float(taps));
            const float a = float(i) * 2.39996322973 + rotation;
            sum += duoSample(tex, s, hit + r * float2(cos(a), sin(a)), size, u.cover);
        }
        color = sum / float(taps);
    }
    color *= attenuation;
    // macTilt's optional glass reflection and final close hand-off.
    const float fromHinge = d / size.y;
    color += float3(0.82, 0.85, 0.86) * exp(-pow((fromHinge - 0.65) / 0.35, 2.0))
        * sin(tilt) * (0.025 * u.reflectionIntensity);
    color *= 1.0 - smoothstep(0.90, 1.0, turn);
    return float4(color, 1.0);
}

fragment float4 foldFragment(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler s [[sampler(0)]],
                             constant Uniforms &u [[buffer(0)]]) {
    if (u.effectMode > 0.5) { return duoMacFold(in, tex, s, u); }
    float turn = clamp(u.turn, 0.0, 1.0);
    float2 uiPixel = 2.0 / max(float2(1.0), u.imageSize);
    int quality = int(clamp(u.sampleCount, 4.0, 32.0));
    
    if (turn <= 0.00001) {
        return float4(sampleSmoothMatteBlur(tex, s, in.uv, 0.0, u.cover, uiPixel, in.position.xy, quality), 1.0);
    }
    
    // Up-to-Down Clamshell Fold: Hinge is at the bottom edge (in.uv.y = 1.0)
    float fromHinge = clamp(1.0 - in.uv.y, 0.0, 1.0);
    
    // Scale bend smoothly across the ENTIRE 0.0 -> 1.0 closing turn
    float bend = turn * MAX_TILT;
    float cosine = cos(bend);
    float sine = sin(bend);
    
    // Stable perspective projection that spans the whole closing arc without exploding
    float invAspect = 1.0 / max(0.1, u.aspect);
    float eye = 3.2 * max(invAspect, 1.0);
    float depth = fromHinge * (0.80 * invAspect) * sine;
    float perspective = eye / max(0.01, (eye - depth));
    
    float2 plane;
    plane.y = 1.0 - fromHinge * cosine * perspective;
    // Horizontal parallax spread. `perspective` pushes the folded plane wider
    // than the panel as it tilts away; the mask further down turns everything
    // outside the unit square into the void — that is the black that creeps in
    // from the left and right edges as the lid folds. `sideVoid` scales ONLY
    // that horizontal divergence, so the vertical geometry (recession, blur,
    // void fade) stays identical: 0 keeps the frame at its full width with no
    // side blackout at all, 1 reproduces the physical projection, and >1
    // exaggerates the falloff.
    float sideSpread = 1.0 + (perspective - 1.0) * clamp(u.sideVoid, 0.0, 2.0);
    plane.x = 0.5 + (in.uv.x - 0.5) * sideSpread;
    
    // Defocus blur: smooth progression that remains continuous and silky.
    // Depth-weighted (hinge stays sharper, outer edge falls off) + velocity-aware:
    // fast lid motion adds directional-feel blur via motionBoost, decaying as lid stops.
    float blurSpread = pow(smoothstep(0.0, 0.85, fromHinge), 1.2);
    float motion = smoothstep(0.0, 1.0, turn) * mix(0.20, 1.0, blurSpread);
    float velocityTerm = clamp(u.motionBoost, 0.0, 24.0) * blurSpread;
    float radius = 56.0 * motion * max(0.05, u.blurStrength) + velocityTerm;
    
    // Side margins softness
    float softness = fwidth(in.uv.x) + radius * 0.002;
    float mask = 1.0 - smoothstep(0.5 - softness, 0.5 + softness, abs(plane.x - 0.5));
    
    // Sample texture using adaptive Vogel disc continuous matte blur
    float3 color = sampleSmoothMatteBlur(tex, s, plane, radius, u.cover, uiPixel, in.position.xy, quality);
    
    // Grazing-angle tint & specular rim. There is NO refraction here: the
    // frozen image is never bent or lensed. `grazingTint` dims the image up
    // to 20% toward the top as the panel tilts (light through glass at a
    // grazing angle); `specularRim` is a Gaussian highlight band centered
    // 65% up from the hinge that strengthens with tilt.
    float grazingTint = sine * pow(fromHinge, 1.5);
    color *= 1.0 - 0.20 * grazingTint;
    float specularRim = exp(-pow((fromHinge - 0.65) / 0.35, 2.0)) * sine;
    color += float3(0.82, 0.85, 0.86) * specularRim * (0.025 * u.reflectionIntensity);

    // Subtle hinge highlight: narrow specular line near the hinge that grows
    // with bend angle. Sells the physical hinge without faking a crease.
    float hingeLine = exp(-pow(fromHinge / 0.06, 2.0)) * sine;
    color += float3(0.90, 0.93, 0.95) * hingeLine * 0.035;
    
    // Smooth void fade: gradual falloff that only fully darkens at the very end
    float fadeDistance = clamp((fromHinge - 0.20) / 0.80, 0.0, 1.0);
    float voidAmount = pow(turn, 1.1) * fadeDistance;
    color *= (1.0 - 0.80 * voidAmount);
    
    // Final closure into deep black right as the lid completely shuts (turn > 0.90)
    float finalClose = 1.0 - smoothstep(0.90, 1.0, turn);
    color *= finalClose;
    
    return float4(mix(DARK, color, mask * finalClose), 1.0);
}
