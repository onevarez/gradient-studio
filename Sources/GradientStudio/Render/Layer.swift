import Foundation
import simd

// Per-layer parameter structs and the Layer enum that composes them.
//
// Day-1 of the composable-pipeline refactor: RenderParams now stores `[Layer]` +
// `Globals` as its canonical state. The existing flat properties on RenderParams
// (lgColorA, waveAmplitude, …) remain available as computed projections so the
// shader, renderer, preset, controls, and export path keep working untouched.
//
// Invariants for Day-1 only (relaxed in later phases):
//   - `layers` has exactly four entries, one of each kind, in the order
//     [.linear, .wave, .mesh, .glass]. Default, randomize, preset.apply, and
//     undo/redo all preserve this shape.

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

/// Scene-wide knobs that don't belong to any one layer. Post-fx (grain, vignette)
/// live here because they're applied after the layer stack, and `loopDuration` is
/// a time property of the scene as a whole.
struct Globals: Equatable {
    var loopDuration: Float           // seconds, used to snap rates to integer cycles/loop
    var grainAmount: Float            // 0..0.3
    var vignetteAmount: Float         // 0..1
}

/// One layer kind with its parameters.
enum Layer: Equatable {
    case linear(LinearParams)
    case wave(WaveParams)
    case mesh(MeshParams)
    case glass(GlassParams)

    /// Short label used in UI headers and logs.
    var kindLabel: String {
        switch self {
        case .linear: return "Linear Gradient"
        case .wave:   return "Wave Distortion"
        case .mesh:   return "Mesh"
        case .glass:  return "Glass"
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
