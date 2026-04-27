import Foundation

enum Shaders {
    // Multi-pass pipeline. Each layer is its own fragment function with its own
    // typed uniform struct. Intermediate passes read/write an rgba16Float texture;
    // the final post-fx pass writes to the app-facing target (bgra8Unorm).
    //
    // Binding convention per pass:
    //   buffer(0)  — pass-specific uniforms
    //   buffer(1)  — mesh-points array (mesh pass only)
    //   texture(0) — previous layer's output (all passes except linear)
    //   sampler(0) — linear clamp-to-edge sampler (all passes except linear)
    //
    // Pipeline order is Linear → Mesh → Wave → Glass → PostFx. Wave runs AFTER
    // Mesh so its UV distortion re-samples the composited scene (linear + mesh),
    // which preserves the "mesh pattern ripples" behavior from the monolithic
    // shader — users expect moving the Wave sliders to visibly warp what they
    // see, which is dominated by the mesh overlay.
    static let source: String = #"""
    #include <metal_stdlib>
    using namespace metal;

    constant float TAU     = 6.2831853;
    constant float INV_TAU = 0.15915494;

    // ---- per-pass uniforms ----
    struct LinearUniforms {
        float4 colorA;
        float4 colorB;
        float  angle;
        float  rotationSpeed;
        float  loopPhase;
        float  loopDuration;
    };

    struct WaveUniforms {
        float  amplitude;
        float  frequency;
        float  speed;
        float  loopPhase;
        float  loopDuration;
        float  _pad0;
        float  _pad1;
        float  _pad2;
    };

    struct MeshUniforms {
        float4 smokeColor;
        float  opacity;
        float  driftSpeed;
        float  loopPhase;
        float  loopDuration;
        int    pointCount;
        int    style;            // 0 grid, 1 blobs, 2 smoke
        float  _pad0;
        float  _pad1;
    };

    struct GlassUniforms {
        float aberration;
        float blurRadius;
        int   enabled;
        float _pad0;
    };

    struct RadialUniforms {
        float4 color;
        float2 center;
        float  radius;
        float  falloff;
        float  intensity;
        float  driftSpeed;
        float  driftRadius;
        float  loopPhase;
        float  loopDuration;
        float  _pad0;
    };

    struct PostFxUniforms {
        float2 resolution;
        float  loopPhase;
        float  grainAmount;
        float  vignetteAmount;
        int    loopFrames;
        int    grainStyle;       // 0 film, 1 halftone-dots, 2 halftone-lines
        float  grainScale;       // cell size in screen pixels (halftone modes)
        float  _pad0;
    };

    struct MeshPoint {
        float4 posAndSeed;       // xy = position, zw = drift phase seed
        float4 color;
    };

    // ---- helpers ----

    // A "rate in rad/sec" gets snapped to the nearest integer count of full cycles
    // across the loop, so `phi * TAU * cycles` returns to its start at phi=1.
    static float cyclesForRate(float radPerSec, float loopDuration) {
        return round(radPerSec * loopDuration * INV_TAU);
    }

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

    // Dave Hoskins' "Hash without Sine" — hash13. Used by grain.
    static float hash13(float3 p3) {
        p3 = fract(p3 * 0.1031);
        p3 += dot(p3, p3.zyx + 31.32);
        return fract((p3.x + p3.y) * p3.z);
    }

    // ---- mesh primitives (preserved from monolithic shader) ----

    // 4x4 grid mesh gradient with interior vertex "breathing" approximated via a
    // low-frequency UV warp that's zero at the edges.
    constant int GRID_W = 4;
    constant int GRID_H = 4;

    static float4 meshGridLayer(float2 uv,
                                device const MeshPoint* points,
                                float phase,
                                float driftSpeed,
                                float loopDuration)
    {
        float edgeFadeX = sin(uv.x * 3.14159265);
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

    // Inverse-squared radial "blob" mesh.
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

    // Domain-warped single-octave simplex ("Smoke"). Emissive, combined additively
    // with the base by the mesh fragment shader.
    static float4 meshSmokeLayer(float2 uv,
                                 float3 glowColor,
                                 float phase,
                                 float driftSpeed,
                                 float loopDuration)
    {
        float R = driftSpeed * loopDuration * INV_TAU * 1.5;
        float a = phase * TAU;
        float2 flow = R * float2(cos(a), sin(a));
        float2 p = uv + flow;
        float2 r = float2(snoise(p + float2(1.7, 9.2)),
                          snoise(p + float2(8.3, 2.8)));
        float  d = snoise(p + 1.8 * r);
        float t = d * 0.5 + 0.5;
        float density = smoothstep(0.45, 0.9, t);
        density = density * density;
        return float4(glowColor * density, density);
    }

    static float grainNoise(float2 px, float phase, int loopFrames) {
        float t = floor(phase * float(loopFrames));
        return hash13(float3(px, t)) - 0.5;
    }

    // Halftone dots: at each pixel, find the cell it lives in, take distance
    // from cell center, and threshold by source luminance. Dot radius shrinks
    // as luminance grows — bright areas → small dots, dark → large dots, like
    // newspaper printing. `phase` jitters cell centers per loop frame to keep
    // the pattern alive in animation without distracting strobe.
    static float halftoneDots(float2 px, float lum, float scale, float phase, int loopFrames) {
        float t = floor(phase * float(loopFrames));
        // 1 px sub-cell jitter so static frames don't show a perfect grid.
        float2 jitter = float2(hash13(float3(0.0, 0.0, t)) - 0.5,
                               hash13(float3(1.0, 0.0, t)) - 0.5);
        float2 cell = floor((px + jitter) / scale);
        float2 cellCenter = cell * scale + 0.5 * scale;
        float d = distance(px + jitter, cellCenter) / (0.5 * scale);  // 0 center, 1 edge
        // Dot radius driven by inverse luminance — stays in 0..1.
        float r = sqrt(saturate(1.0 - lum));
        // Soft 1-px edge so dots anti-alias.
        return smoothstep(r + 0.06, r - 0.06, d);  // 1 inside dot, 0 outside
    }

    // Halftone lines: same idea on a 1-D axis. Diagonal so it doesn't fight
    // the typical horizontal/vertical of underlying gradients.
    static float halftoneLines(float2 px, float lum, float scale, float phase, int loopFrames) {
        float t = floor(phase * float(loopFrames));
        float jitter = (hash13(float3(0.0, 1.0, t)) - 0.5) * scale * 0.2;
        // 45° projection.
        float u = (px.x + px.y + jitter) / scale;
        float f = fract(u) - 0.5;        // -0.5..0.5 within a stripe
        float r = sqrt(saturate(1.0 - lum)) * 0.5;
        return smoothstep(r + 0.04, r - 0.04, abs(f));
    }

    // ---- vertex (shared fullscreen triangle) ----
    struct VSOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VSOut vertexMain(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        float2 uvs[3]       = { float2(0,  0), float2(2,  0), float2(0, 2) };
        VSOut o;
        o.position = float4(positions[vid], 0.0, 1.0);
        o.uv = uvs[vid];
        return o;
    }

    // ---- Linear: base gradient, ignores input ----
    fragment float4 linearFragment(VSOut in [[stage_in]],
                                    constant LinearUniforms& u [[buffer(0)]])
    {
        float rotCycles = cyclesForRate(u.rotationSpeed, u.loopDuration);
        float angle = u.angle + u.loopPhase * TAU * rotCycles;
        float2 dir = float2(cos(angle), sin(angle));
        float t = saturate(dot(in.uv - 0.5, dir) + 0.5);
        return mix(u.colorA, u.colorB, t);
    }

    // ---- Wave: distorts sampling UV, reads input at the distorted coord ----
    fragment float4 waveFragment(VSOut in [[stage_in]],
                                  constant WaveUniforms& u [[buffer(0)]],
                                  texture2d<float, access::sample> inputTex [[texture(0)]],
                                  sampler s [[sampler(0)]])
    {
        float2 p = in.uv * max(u.frequency, 0.0001);
        float  a = u.loopPhase * TAU;
        float  R = u.speed * u.loopDuration * INV_TAU;
        float2 ox = R * float2(cos(a),          sin(a));
        float2 oy = R * float2(cos(a + 1.5708), sin(a + 1.5708));
        float nx = snoise(p + ox);
        float ny = snoise(p + oy + float2(11.3, 7.7));
        float2 dUV = in.uv + float2(nx, ny) * u.amplitude;
        return inputTex.sample(s, dUV);
    }

    // ---- Mesh: overlays mesh-style color over input ----
    fragment float4 meshFragment(VSOut in [[stage_in]],
                                  constant MeshUniforms& u [[buffer(0)]],
                                  device const MeshPoint* points [[buffer(1)]],
                                  texture2d<float, access::sample> inputTex [[texture(0)]],
                                  sampler s [[sampler(0)]])
    {
        float3 base = inputTex.sample(s, in.uv).rgb;

        if (u.style == 2) {
            // Smoke: additive glow over base (matches monolithic behavior).
            float4 smoke = meshSmokeLayer(in.uv, u.smokeColor.rgb, u.loopPhase,
                                          u.driftSpeed, u.loopDuration);
            return float4(base + smoke.rgb * saturate(u.opacity), 1.0);
        }

        float4 mesh = (u.style == 1)
            ? meshBlobLayer(in.uv, points, u.pointCount, u.loopPhase, u.driftSpeed, u.loopDuration)
            : meshGridLayer(in.uv, points, u.loopPhase, u.driftSpeed, u.loopDuration);
        return float4(mix(base, mesh.rgb, saturate(u.opacity)), 1.0);
    }

    // ---- Glass: chromatic aberration + 8-tap blur on top of input ----
    fragment float4 glassFragment(VSOut in [[stage_in]],
                                   constant GlassUniforms& u [[buffer(0)]],
                                   texture2d<float, access::sample> inputTex [[texture(0)]],
                                   sampler s [[sampler(0)]])
    {
        if (u.enabled == 0) {
            return inputTex.sample(s, in.uv);
        }

        // Chromatic aberration — radial per-channel UV split.
        float2 dir = in.uv - 0.5;
        float  ab  = u.aberration * 0.08;
        float3 r = inputTex.sample(s, in.uv + dir * ab).rgb;
        float3 g = inputTex.sample(s, in.uv           ).rgb;
        float3 b = inputTex.sample(s, in.uv - dir * ab).rgb;
        float3 color = float3(r.r, g.g, b.b);

        // 8-tap symmetric box blur.
        if (u.blurRadius > 0.0) {
            float br = u.blurRadius * 0.06;
            float3 acc = color;
            acc += inputTex.sample(s, in.uv + float2( br,     0.0)).rgb;
            acc += inputTex.sample(s, in.uv + float2(-br,     0.0)).rgb;
            acc += inputTex.sample(s, in.uv + float2( 0.0,    br )).rgb;
            acc += inputTex.sample(s, in.uv + float2( 0.0,   -br )).rgb;
            acc += inputTex.sample(s, in.uv + float2( br*0.7, br*0.7)).rgb;
            acc += inputTex.sample(s, in.uv + float2(-br*0.7, br*0.7)).rgb;
            acc += inputTex.sample(s, in.uv + float2( br*0.7,-br*0.7)).rgb;
            acc += inputTex.sample(s, in.uv + float2(-br*0.7,-br*0.7)).rgb;
            color = acc / 9.0;
        }
        return float4(color, 1.0);
    }

    // ---- Radial: additive bloom over input ----
    fragment float4 radialFragment(VSOut in [[stage_in]],
                                    constant RadialUniforms& u [[buffer(0)]],
                                    texture2d<float, access::sample> inputTex [[texture(0)]],
                                    sampler s [[sampler(0)]])
    {
        float3 base = inputTex.sample(s, in.uv).rgb;

        // Orbital drift of the bloom center: a small circle whose radius is
        // `driftRadius`. Snap to integer cycles per loop so the animation
        // returns to its starting position seamlessly.
        float cycles = cyclesForRate(u.driftSpeed, u.loopDuration);
        float a      = u.loopPhase * TAU * cycles;
        float2 anim  = u.center + u.driftRadius * float2(cos(a), sin(a));

        // Radial bell curve. Distance is normalized by `radius`; the smoothstep
        // gives a soft edge, and `falloff` reshapes the curve from a wide halo
        // (low exponent) to a tight hot-spot (high exponent).
        float d = distance(in.uv, anim) / u.radius;
        float t = pow(1.0 - smoothstep(0.0, 1.0, saturate(d)), max(u.falloff, 0.1));

        // Additive blend so stacking radials over a darker base brightens it
        // without flattening colors below — matches the "hero blur" aesthetic
        // where the bloom *adds* light rather than overlaying it.
        float3 bloom = u.color.rgb * (t * u.intensity);
        return float4(base + bloom, 1.0);
    }

    // ---- Post-fx: vignette + grain, writes to target ----
    fragment float4 postFxFragment(VSOut in [[stage_in]],
                                    constant PostFxUniforms& u [[buffer(0)]],
                                    texture2d<float, access::sample> inputTex [[texture(0)]],
                                    sampler s [[sampler(0)]])
    {
        float3 color = inputTex.sample(s, in.uv).rgb;

        if (u.vignetteAmount > 0.0) {
            float d = distance(in.uv, float2(0.5));
            float v = 1.0 - smoothstep(0.25, 0.9, d) * u.vignetteAmount;
            color *= v;
        }

        if (u.grainAmount > 0.0) {
            float2 px = in.uv * u.resolution;
            if (u.grainStyle == 1) {
                // Halftone dots: dot coverage drives toward black; we mix from
                // the source color to black by `coverage * grainAmount` so the
                // print pattern stays in-key with the underlying gradient.
                float lum = dot(color, float3(0.2126, 0.7152, 0.0722));
                float c   = halftoneDots(px, lum, max(u.grainScale, 1.0),
                                          u.loopPhase, u.loopFrames);
                color = mix(color, float3(0.0), c * u.grainAmount);
            } else if (u.grainStyle == 2) {
                float lum = dot(color, float3(0.2126, 0.7152, 0.0722));
                float c   = halftoneLines(px, lum, max(u.grainScale, 1.0),
                                           u.loopPhase, u.loopFrames);
                color = mix(color, float3(0.0), c * u.grainAmount);
            } else {
                float n = grainNoise(px, u.loopPhase, u.loopFrames);
                color += float3(n) * u.grainAmount;
            }
        }

        return float4(color, 1.0);
    }
    """#
}
