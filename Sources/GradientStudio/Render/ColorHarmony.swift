import Foundation
import simd

// Perceptually-uniform color utilities inspired by `pastel` (github.com/sharkdp/pastel).
// We work in OKLCh (Björn Ottosson, 2020) and generate palettes by varying hue on a
// controlled chroma/lightness range, then convert to sRGB for the shader uniforms.
//
// OKLCh is polar OKLab:  L = perceived lightness 0..1,  C = chroma 0..~0.37,  h = hue in radians.

enum ColorHarmony {

    enum Strategy: CaseIterable {
        case analogous          // neighbors on the wheel, coherent
        case triadic            // 120° apart — lively but balanced
        case complementary      // 180° apart — high contrast
        case splitComplementary // 150°/210° — softer complementary
        case tetradic           // two pairs of complements
        case monochromatic      // one hue, varied L

        static func random() -> Strategy { allCases.randomElement()! }
    }

    /// Generate `count` colors spread over the palette defined by `strategy`, seeded at
    /// `baseHue` (radians). Lightness and chroma jitter within tight perceptual bands so
    /// neighbors always read as "a family" rather than random noise.
    static func palette(count: Int,
                        baseHue: Float,
                        strategy: Strategy,
                        lightness: ClosedRange<Float> = 0.55...0.8,
                        chroma: ClosedRange<Float> = 0.12...0.2) -> [SIMD4<Float>]
    {
        let anchors = hueAnchors(for: strategy, base: baseHue)
        return (0..<count).map { i in
            let anchor = anchors[i % anchors.count]
            // small hue jitter around the anchor keeps multiple points on the same anchor
            // from being identical
            let h = anchor + Float.random(in: -0.15...0.15)
            let L = Float.random(in: lightness)
            let C = Float.random(in: chroma)
            return SIMD4(oklchToSRGB(L: L, C: C, hRadians: h), 1.0)
        }
    }

    /// Two dark tones in the same family — good for the linear-gradient base.
    static func deepPair(baseHue: Float, strategy: Strategy) -> (SIMD4<Float>, SIMD4<Float>) {
        let anchors = hueAnchors(for: strategy, base: baseHue)
        let h1 = anchors[0]
        let h2 = anchors.count > 1 ? anchors[1] : anchors[0]
        let a = SIMD4(oklchToSRGB(L: .random(in: 0.08...0.2),
                                  C: .random(in: 0.04...0.12),
                                  hRadians: h1), 1.0)
        let b = SIMD4(oklchToSRGB(L: .random(in: 0.02...0.1),
                                  C: .random(in: 0.02...0.08),
                                  hRadians: h2), 1.0)
        return (a, b)
    }

    // MARK: - Palette geometry

    private static func hueAnchors(for strategy: Strategy, base: Float) -> [Float] {
        let twoPi = Float.pi * 2
        let deg: (Float) -> Float = { $0 * .pi / 180 }
        let raw: [Float]
        switch strategy {
        case .analogous:          raw = [base - deg(30), base, base + deg(30)]
        case .triadic:            raw = [base, base + deg(120), base + deg(240)]
        case .complementary:      raw = [base, base + deg(180)]
        case .splitComplementary: raw = [base, base + deg(150), base + deg(210)]
        case .tetradic:           raw = [base, base + deg(60), base + deg(180), base + deg(240)]
        case .monochromatic:      raw = [base]
        }
        return raw.map { h in
            let w = h.truncatingRemainder(dividingBy: twoPi)
            return (w + twoPi).truncatingRemainder(dividingBy: twoPi)
        }
    }

    // MARK: - OKLCh → sRGB

    static func oklchToSRGB(L: Float, C: Float, hRadians h: Float) -> SIMD3<Float> {
        let a = C * cos(h)
        let b = C * sin(h)
        return oklabToSRGB(L: L, a: a, b: b)
    }

    /// OKLab → linear sRGB → gamma-encoded sRGB (clamped to 0..1).
    static func oklabToSRGB(L: Float, a: Float, b: Float) -> SIMD3<Float> {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b

        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_

        let r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

        return SIMD3(srgbEncode(Float(r)),
                     srgbEncode(Float(g)),
                     srgbEncode(Float(bl)))
    }

    private static func srgbEncode(_ x: Float) -> Float {
        let c = max(0, min(1, x))
        // standard sRGB transfer
        return c <= 0.0031308
            ? 12.92 * c
            : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }
}
