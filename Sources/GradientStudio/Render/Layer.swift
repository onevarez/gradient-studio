import Foundation
import simd

// Per-layer parameter structs and the Layer enum that composes them. Canonical
// state on `RenderParams` is `layers: [LayerEntry]` + `globals: Globals`; the
// renderer iterates the layer list in order, respecting `enabled`. Users can
// reorder, toggle, duplicate, add, and remove layers — multiple layers of the
// same kind are allowed.

struct LinearParams: Equatable {
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
    var angle: Float                  // radians
    var rotationSpeed: Float          // rad/sec
}

struct WaveParams: Equatable {
    var amplitude: Float              // uv units, typical 0..0.2
    var frequency: Float              // noise freq, typical 0..8
    var speed: Float                  // time scale
}

struct MeshParams: Equatable {
    var style: MeshStyle
    var opacity: Float                // 0..1 blend over base
    var driftSpeed: Float
    var points: [MeshPointParams]
}

struct GlassParams: Equatable {
    var enabled: Bool
    var aberration: Float             // 0..1
    var blurRadius: Float             // 0..1
}

/// Soft circular bloom that adds onto the layer beneath it. Models the
/// "hero blur" look — a single bright spot with smooth falloff, optionally
/// drifting on a small orbit.
struct RadialParams: Equatable {
    var color: SIMD4<Float>           // bloom emission color
    var center: SIMD2<Float>          // 0..1 normalized
    var radius: Float                 // 0..1.5 (uv units)
    var falloff: Float                // 0.5..6, exponent on the bell curve
    var intensity: Float              // 0..2, brightness multiplier
    var driftSpeed: Float             // rad/sec orbital drift of `center`
    var driftRadius: Float            // 0..0.3, how far center wanders
}

/// Three flavors of grain. `film` is uncorrelated white noise (the original
/// behavior). `halftoneDots` and `halftoneLines` mimic newspaper printing —
/// at high `grainAmount` they read as a graphic texture, not photo noise,
/// matching the "Japaneasy / Chaotic Gradients" aesthetic.
enum GrainStyle: Int32, CaseIterable, Identifiable {
    case film         = 0
    case halftoneDots = 1
    case halftoneLines = 2

    var id: Int32 { rawValue }

    var label: String {
        switch self {
        case .film:          return "Film"
        case .halftoneDots:  return "Halftone Dots"
        case .halftoneLines: return "Halftone Lines"
        }
    }
}

/// Scene-wide knobs that don't belong to any one layer. Post-fx (grain, vignette)
/// live here because they're applied after the layer stack, and `loopDuration` is
/// a time property of the scene as a whole.
struct Globals: Equatable {
    var loopDuration: Float           // seconds, used to snap rates to integer cycles/loop
    var grainAmount: Float            // 0..1 — at high values dominates the image (chaotic look)
    var grainStyle: GrainStyle        // film vs. halftone variants
    var grainScale: Float             // halftone cell size in screen pixels (4..40); ignored for film
    var vignetteAmount: Float         // 0..1
}

/// One layer kind with its parameters.
enum Layer: Equatable {
    case linear(LinearParams)
    case wave(WaveParams)
    case mesh(MeshParams)
    case glass(GlassParams)
    case radial(RadialParams)

    var kind: LayerKind {
        switch self {
        case .linear: return .linear
        case .wave:   return .wave
        case .mesh:   return .mesh
        case .glass:  return .glass
        case .radial: return .radial
        }
    }

    /// Short label used in UI headers and logs.
    var kindLabel: String { kind.label }
}

/// Value-typed tag for a layer's kind — used by the "+ Add Layer" menu and for
/// kind-discriminated operations that don't need to crack open the params.
enum LayerKind: String, CaseIterable, Identifiable {
    case linear, wave, mesh, glass, radial

    var id: String { rawValue }

    var label: String {
        switch self {
        case .linear: return "Linear Gradient"
        case .wave:   return "Wave Distortion"
        case .mesh:   return "Mesh"
        case .glass:  return "Glass"
        case .radial: return "Radial Bloom"
        }
    }

    /// Fresh params for a newly-added layer of this kind. Values match the
    /// original default preset so adding a new layer "feels" like getting a
    /// known-good baseline to tweak from.
    func makeDefaultLayer() -> Layer {
        switch self {
        case .linear:
            return .linear(LinearParams(
                colorA: SIMD4(0.04, 0.01, 0.12, 1.0),
                colorB: SIMD4(0.02, 0.02, 0.04, 1.0),
                angle: .pi * 0.25,
                rotationSpeed: 0.05
            ))
        case .wave:
            return .wave(WaveParams(
                amplitude: 0.08,
                frequency: 2.2,
                speed: 0.15
            ))
        case .mesh:
            var m = MeshParams(style: .grid, opacity: 0.85, driftSpeed: 0.4, points: [])
            m.reseed()
            return .mesh(m)
        case .glass:
            return .glass(GlassParams(
                enabled: true,
                aberration: 0.3,
                blurRadius: 0.15
            ))
        case .radial:
            return .radial(RadialParams(
                color: SIMD4(1.0, 0.45, 0.1, 1.0),
                center: SIMD2(0.5, 0.55),
                radius: 0.55,
                falloff: 2.2,
                intensity: 1.0,
                driftSpeed: 0.0,
                driftRadius: 0.05
            ))
        }
    }
}

/// An entry in the composable layer list — the layer itself plus its enabled
/// state. The entry's `id` is stable across reorder/toggle so SwiftUI can track
/// identity in `ForEach`.
struct LayerEntry: Equatable, Identifiable {
    let id = UUID()
    var layer: Layer
    var enabled: Bool = true
}

// MARK: - MeshParams actions

extension MeshParams {
    /// Rotate the mesh palette one step clockwise around the 4×4 grid. The outer
    /// ring (12 cells) and inner ring (4 cells) each rotate by one — after 12
    /// calls the grid returns to its starting arrangement (LCM of ring periods
    /// 12 and 4).
    mutating func cycleClockwise() {
        // Index layout (row 0 = bottom, row 3 = top):
        //   12 13 14 15
        //    8  9 10 11
        //    4  5  6  7
        //    0  1  2  3
        //
        // Clockwise from top-left: top row L→R, right col top→bottom,
        // bottom row R→L, left col bottom→top.
        let outer: [Int] = [12, 13, 14, 15, 11, 7, 3, 2, 1, 0, 4, 8]
        let inner: [Int] = [9, 10, 6, 5]
        rotateColors(along: outer)
        rotateColors(along: inner)
    }

    private mutating func rotateColors(along indices: [Int]) {
        guard indices.count > 1, indices.allSatisfy({ $0 < points.count }) else { return }
        let last = points[indices.last!].color
        for i in stride(from: indices.count - 1, through: 1, by: -1) {
            points[indices[i]].color = points[indices[i - 1]].color
        }
        points[indices[0]].color = last
    }

    /// Set the leftmost and rightmost grid columns to black.
    mutating func blackoutSides() {
        let black = SIMD4<Float>(0, 0, 0, 1)
        let w = GradientRendererLimits.meshGridWidth
        let h = GradientRendererLimits.meshGridHeight
        guard points.count >= w * h else { return }
        for row in 0..<h {
            points[row * w + 0].color = black
            points[row * w + (w - 1)].color = black
        }
    }

    /// Set the top and bottom grid rows to black.
    mutating func blackoutTopBottom() {
        let black = SIMD4<Float>(0, 0, 0, 1)
        let w = GradientRendererLimits.meshGridWidth
        let h = GradientRendererLimits.meshGridHeight
        guard points.count >= w * h else { return }
        for col in 0..<w {
            points[0 * w + col].color = black
            points[(h - 1) * w + col].color = black
        }
    }

    /// Regenerate this mesh's points with fresh positions, seeds, and an
    /// analogous color palette from a new random base hue.
    mutating func reseed() {
        let baseHue = Float.random(in: 0...(.pi * 2))
        let palette = ColorHarmony.palette(count: GradientRendererLimits.meshVertexCount,
                                           baseHue: baseHue,
                                           strategy: .analogous)
        points = palette.map { color in
            MeshPointParams(position: MeshPointParams.randomPosition(),
                            seed: MeshPointParams.randomSeed(),
                            color: color)
        }
    }

    /// Replace colors on this mesh from an external palette (e.g. extracted from
    /// an image). Positions and seeds are preserved so motion stays continuous.
    mutating func applyColors(_ colors: [SIMD4<Float>]) {
        guard !colors.isEmpty else { return }
        let n = GradientRendererLimits.meshVertexCount
        for i in 0..<n where i < points.count {
            points[i].color = colors[i % colors.count]
        }
    }

    /// Brightest palette entry — used as Smoke's emission color so the glow
    /// stands out against the (dark) linear-gradient background regardless of
    /// palette order.
    var brightestColor: SIMD4<Float> {
        points
            .map(\.color)
            .max(by: { Self.relativeLuminance($0) < Self.relativeLuminance($1) })
            ?? SIMD4(1, 1, 1, 1)
    }

    static func relativeLuminance(_ c: SIMD4<Float>) -> Float {
        0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
    }
}
