import Foundation

enum Shaders {
    static let source: String = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution;
        float loopPhase;         // [0,1), precomputed on CPU
        int meshPointCount;
        float4 lgColorA;
        float4 lgColorB;
        float lgAngle;
        float lgRotationSpeed;
        float waveAmplitude;
        float waveFrequency;
        float waveSpeed;
        float meshDriftSpeed;
        float meshOpacity;
        float glassAberration;
        float glassBlurRadius;
        int glassEnabled;
        float _pad0;
        float _pad1;
        float grainAmount;
        float vignetteAmount;
        int meshStyle;           // 0 = grid bilinear, 1 = blobs
        float _pad2;
        float loopDuration;      // seconds, used to snap rates to integer cycles/loop
        int loopFrames;          // number of distinct grain samples across the loop
        float _pad3;
        float _pad4;
        float4 smokeColor;       // brightest palette entry — used by Smoke style
    };

    constant float TAU     = 6.2831853;
    constant float INV_TAU = 0.15915494;

    // A "rate in rad/sec" gets snapped to the nearest integer count of full cycles
    // across the loop, so `phi * TAU * cycles` returns to its start at phi=1.
    static float cyclesForRate(float radPerSec, float loopDuration) {
        return round(radPerSec * loopDuration * INV_TAU);
    }

    struct MeshPoint {
        float4 posAndSeed;   // xy = position in 0..1, zw = drift phase seed
        float4 color;
    };

    // ---- 2D simplex noise (Ashima Arts, public domain) ----
    static float2 _mod289_2(float2 x) { return x - floor(x * (1.0/289.0)) * 289.0; }
    static float3 _mod289_3(float3 x) { return x - floor(x * (1.0/289.0)) * 289.0; }
    static float3 _permute(float3 x)  { return _mod289_3(((x*34.0)+1.0)*x); }

    static float snoise(float2 v) {
        const float4 C = float4(0.211324865405187, 0.366025403784439,
                               -0.577350269189626, 0.024390243902439);
        float2 i  = floor(v + dot(v, C.yy));
        float2 x0 = v - i + dot(i, C.xx);
        float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
        float4 x12 = x0.xyxy + C.xxzz;
        x12.xy -= i1;
        i = _mod289_2(i);
        float3 p = _permute(_permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));
        float3 m = max(0.5 - float3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
        m = m*m; m = m*m;
        float3 x = 2.0 * fract(p * C.www) - 1.0;
        float3 h = abs(x) - 0.5;
        float3 ox = floor(x + 0.5);
        float3 a0 = x - ox;
        m *= 1.79284291400159 - 0.85373472095314 * (a0*a0 + h*h);
        float3 g;
        g.x  = a0.x * x0.x  + h.x  * x0.y;
        g.yz = a0.yz * x12.xz + h.yz * x12.yw;
        return 130.0 * dot(m, g);
    }

    // ---- layer primitives ----
    static float4 linearLayer(float2 uv, float4 colorA, float4 colorB, float angle) {
        float2 dir = float2(cos(angle), sin(angle));
        float t = saturate(dot(uv - 0.5, dir) + 0.5);
        return mix(colorA, colorB, t);
    }

    // Looping wave distortion. Instead of offsetting the noise axis linearly with
    // time, we trace a circle in noise-space whose circumference equals the linear
    // path that `speed` would cover in one loop. This keeps the perceived evolution
    // rate roughly the same, but the result is exactly periodic in phase.
    static float2 waveDistort(float2 uv, float amp, float freq, float speed,
                              float phase, float loopDuration)
    {
        float2 p = uv * max(freq, 0.0001);
        float  a = phase * TAU;
        float  R = speed * loopDuration * INV_TAU;
        float2 ox = R * float2(cos(a),          sin(a));
        float2 oy = R * float2(cos(a + 1.5708), sin(a + 1.5708));  // decorrelate x/y
        float nx = snoise(p + ox);
        float ny = snoise(p + oy + float2(11.3, 7.7));
        return uv + float2(nx, ny) * amp;
    }

    // 4x4 grid mesh gradient, patterned after SwiftUI's `MeshGradient`:
    // colors sit on a regular grid of vertices, interior vertices drift with time,
    // and in-cell interpolation is smoothstep-bilinear for continuous color fields
    // (no radial hotspots like an inverse-squared-distance blob mesh).
    constant int GRID_W = 4;
    constant int GRID_H = 4;

    static float4 meshLayer(float2 uv,
                            device const MeshPoint* points,
                            float phase,
                            float driftSpeed,
                            float loopDuration)
    {
        // "Interior vertex drift" — the article animates interior points on a 4x4
        // with sin/cos. Inverse-bilinear for moving vertices is expensive; instead
        // we warp UV by a low-frequency field that's zero at the edges, producing
        // a visually equivalent "breathing" feel on a fixed-topology grid.
        float edgeFadeX = sin(uv.x * 3.14159265);   // 0 at x=0/1, 1 at x=0.5
        float edgeFadeY = sin(uv.y * 3.14159265);
        float edgeFade  = edgeFadeX * edgeFadeY;
        float cycles    = cyclesForRate(driftSpeed, loopDuration);
        float a         = phase * TAU * cycles;
        float2 warp = 0.05 * edgeFade * float2(
            sin(a          + uv.y * TAU),
            cos(a + 1.5708 + uv.x * TAU)
        );
        float2 w_uv = saturate(uv + warp);

        float fx = w_uv.x * float(GRID_W - 1);
        float fy = w_uv.y * float(GRID_H - 1);
        int ix = clamp(int(floor(fx)), 0, GRID_W - 2);
        int iy = clamp(int(floor(fy)), 0, GRID_H - 2);
        float tx = fx - float(ix);
        float ty = fy - float(iy);

        // smoothstep — rounder than pure bilinear, closer to SwiftUI's bicubic feel.
        tx = tx * tx * (3.0 - 2.0 * tx);
        ty = ty * ty * (3.0 - 2.0 * ty);

        float3 c00 = points[iy       * GRID_W + ix    ].color.rgb;
        float3 c10 = points[iy       * GRID_W + ix + 1].color.rgb;
        float3 c01 = points[(iy + 1) * GRID_W + ix    ].color.rgb;
        float3 c11 = points[(iy + 1) * GRID_W + ix + 1].color.rgb;

        float3 top = mix(c00, c10, tx);
        float3 bot = mix(c01, c11, tx);
        return float4(mix(top, bot, ty), 1.0);
    }

    // 3-octave FBM on 2D simplex — the building block for cloud/smoke fields.
    static float fbm3(float2 p) {
        float s  = snoise(p);
               s += 0.5  * snoise(p * 2.0);
               s += 0.25 * snoise(p * 4.0);
        return s / 1.75;
    }

    // Domain-warped single-octave simplex ("Smoke"). Stacking fbm octaves was adding
    // vein/caustic detail that fought the broad soft-arm look of reference #11.
    // Single-octave snoise at freq ≈1 plus a light domain warp gives one or two
    // large swirled shapes per frame, which is the target.
    static float4 meshSmokeLayer(float2 uv,
                                 float3 glowColor,
                                 float phase,
                                 float driftSpeed,
                                 float loopDuration)
    {
        // Flow: circle in noise-space, periodic in phase so the loop stays seamless.
        // Scale chosen so driftSpeed ≈ 0.3 gives clearly visible evolution and the
        // slider's full range (1.5) gives dramatic motion without becoming chaotic.
        float R = driftSpeed * loopDuration * INV_TAU * 1.5;
        float a = phase * TAU;
        float2 flow = R * float2(cos(a), sin(a));

        float2 p = uv * 1.0 + flow;

        // Single-level domain warp using single-octave snoise. Warp magnitude 1.8 is
        // enough to bend the isocontours into smoke-arm curves without fragmenting
        // them into small swirls.
        float2 r = float2(snoise(p + float2(1.7, 9.2)),
                          snoise(p + float2(8.3, 2.8)));
        float  d = snoise(p + 1.8 * r);

        // Remap [-1,1] → [0,1], then narrow smoothstep + square tail so most of the
        // canvas fades to true black and only density peaks glow.
        float t = d * 0.5 + 0.5;
        float density = smoothstep(0.45, 0.9, t);
        density = density * density;

        return float4(glowColor * density, density);
    }

    // Inverse-squared radial "blob" mesh — restored as a second style so images with
    // a few soft light sources on a dark canvas are expressible. The grid bilinear is
    // the default for continuous color fields.
    static float4 meshBlobLayer(float2 uv,
                                device const MeshPoint* points,
                                int count,
                                float phase,
                                float driftSpeed,
                                float loopDuration)
    {
        float cycles = cyclesForRate(driftSpeed, loopDuration);
        float a      = phase * TAU * cycles;
        float3 accum = float3(0.0);
        float totalW = 0.0;
        for (int i = 0; i < count; i++) {
            float2 base = points[i].posAndSeed.xy;
            float2 seed = points[i].posAndSeed.zw;
            float2 drift = 0.14 * float2(
                sin(a + seed.x * TAU),
                cos(a + seed.y * TAU)
            );
            float2 pos = base + drift;
            float d = distance(uv, pos);
            float w = 1.0 / (1.0 + 28.0 * d * d);
            accum  += points[i].color.rgb * w;
            totalW += w;
        }
        return float4(accum / max(totalW, 1e-4), 1.0);
    }

    // Dave Hoskins' "Hash without Sine" — hash13, proven-good spatial dispersion
    // without the directional bias that `fract(sin(...))` or simpler mixes produce.
    // https://www.shadertoy.com/view/4djSRW
    static float hash13(float3 p3) {
        p3 = fract(p3 * 0.1031);
        p3 += dot(p3, p3.zyx + 31.32);
        return fract((p3.x + p3.y) * p3.z);
    }

    static float grainNoise(float2 px, float phase, int loopFrames) {
        // Quantize phase to one of `loopFrames` distinct seeds. At phase=0 and phase=1
        // the same seed is used → the grain wraps cleanly with the rest of the clip.
        float t = floor(phase * float(loopFrames));
        return hash13(float3(px, t)) - 0.5;
    }

    static float3 computeScene(float2 uv,
                               constant Uniforms& u,
                               device const MeshPoint* points)
    {
        float rotCycles = cyclesForRate(u.lgRotationSpeed, u.loopDuration);
        float angle = u.lgAngle + u.loopPhase * TAU * rotCycles;
        float4 base = linearLayer(uv, u.lgColorA, u.lgColorB, angle);
        float2 dUV  = waveDistort(uv, u.waveAmplitude, u.waveFrequency, u.waveSpeed,
                                   u.loopPhase, u.loopDuration);

        // Smoke has its own rich domain warp — stacking the wave layer on top of it
        // produced water-caustic ripples instead of soft smoke. Sample from raw uv
        // so the smoke shader fully owns the shape.
        if (u.meshStyle == 2) {
            // Feed the wave-distorted UV into smoke so Amp/Freq/Speed do affect it.
            // With single-octave low-freq smoke, wave warp only gently wobbles arm
            // edges — no more caustic-ripple mess like the old high-freq version.
            float4 smoke = meshSmokeLayer(dUV, u.smokeColor.rgb, u.loopPhase,
                                          u.meshDriftSpeed, u.loopDuration);
            return base.rgb + smoke.rgb * saturate(u.meshOpacity);
        }

        float4 mesh = (u.meshStyle == 1)
            ? meshBlobLayer(dUV, points, u.meshPointCount, u.loopPhase,
                            u.meshDriftSpeed, u.loopDuration)
            : meshLayer(dUV, points, u.loopPhase, u.meshDriftSpeed, u.loopDuration);
        return mix(base.rgb, mesh.rgb, saturate(u.meshOpacity));
    }

    // ---- entry points ----
    struct VSOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VSOut vertexMain(uint vid [[vertex_id]]) {
        // fullscreen triangle — (+Y up, UV origin bottom-left)
        float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        float2 uvs[3]       = { float2(0,  0), float2(2,  0), float2(0, 2) };
        VSOut o;
        o.position = float4(positions[vid], 0.0, 1.0);
        o.uv = uvs[vid];
        return o;
    }

    fragment float4 fragmentMain(VSOut in [[stage_in]],
                                  constant Uniforms& u        [[buffer(0)]],
                                  device const MeshPoint* mp  [[buffer(1)]])
    {
        float2 uv = in.uv;
        float3 color;
        if (u.glassEnabled != 0) {
            // Chromatic aberration — channel-wise radial UV split.
            // Scale tuned so slider=1 produces obvious fringing on smooth gradients.
            float2 dir = uv - 0.5;
            float  ab  = u.glassAberration * 0.08;
            float3 r = computeScene(uv + dir * ab, u, mp);
            float3 g = computeScene(uv,            u, mp);
            float3 b = computeScene(uv - dir * ab, u, mp);
            color = float3(r.r, g.g, b.b);

            // Box-ish blur — 8 symmetric taps on a ring of radius `br`, wide enough
            // to soften edges visibly. Sampling `computeScene` is the cheap path: it
            // re-rolls aberration too, but that keeps the result color-consistent.
            if (u.glassBlurRadius > 0.0) {
                float br = u.glassBlurRadius * 0.06;
                float3 acc = color;
                acc += computeScene(uv + float2( br,     0.0),    u, mp);
                acc += computeScene(uv + float2(-br,     0.0),    u, mp);
                acc += computeScene(uv + float2( 0.0,    br),     u, mp);
                acc += computeScene(uv + float2( 0.0,   -br),     u, mp);
                acc += computeScene(uv + float2( br*0.7, br*0.7), u, mp);
                acc += computeScene(uv + float2(-br*0.7, br*0.7), u, mp);
                acc += computeScene(uv + float2( br*0.7,-br*0.7), u, mp);
                acc += computeScene(uv + float2(-br*0.7,-br*0.7), u, mp);
                color = acc / 9.0;
            }
        } else {
            color = computeScene(uv, u, mp);
        }

        // Vignette — soft dark edge falloff (dist-from-center ramp).
        if (u.vignetteAmount > 0.0) {
            float d = distance(uv, float2(0.5));
            float v = 1.0 - smoothstep(0.25, 0.9, d) * u.vignetteAmount;
            color *= v;
        }

        // Grain — monochrome luminance noise (single hash, applied to all channels).
        // Per-channel hashes produce rainbow "TV static"; a single grayscale value
        // reads as fine film texture. Pixel-space input for resolution-independent size.
        if (u.grainAmount > 0.0) {
            float2 px = uv * u.resolution;
            float  n  = grainNoise(px, u.loopPhase, u.loopFrames);
            color += float3(n) * u.grainAmount;
        }

        return float4(color, 1.0);
    }
    """#
}
