import Foundation
import simd

// Per-pass uniform structs. Memory layout MUST match the corresponding struct
// in Shaders.swift. Any field reorder or new field requires a coordinated edit
// on both sides.

struct LinearUniforms {
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
    var angle: Float
    var rotationSpeed: Float
    var loopPhase: Float
    var loopDuration: Float
}

struct WaveUniforms {
    var amplitude: Float
    var frequency: Float
    var speed: Float
    var loopPhase: Float
    var loopDuration: Float
    var _pad0: Float = 0
    var _pad1: Float = 0
    var _pad2: Float = 0
}

struct MeshUniforms {
    var smokeColor: SIMD4<Float>
    var opacity: Float
    var driftSpeed: Float
    var loopPhase: Float
    var loopDuration: Float
    var pointCount: Int32
    var style: Int32               // 0 grid, 1 blobs, 2 smoke
    var _pad0: Float = 0
    var _pad1: Float = 0
}

struct GlassUniforms {
    var aberration: Float
    var blurRadius: Float
    var enabled: Int32
    var _pad0: Float = 0
}

struct PostFxUniforms {
    var resolution: SIMD2<Float>
    var loopPhase: Float
    var grainAmount: Float
    var vignetteAmount: Float
    var loopFrames: Int32
    var _pad0: Float = 0
    var _pad1: Float = 0
}

enum MeshStyle: Int32 {
    case grid  = 0
    case blobs = 1
    case smoke = 2
}

// Memory layout MUST match `MeshPoint` in Shaders.swift.
struct MeshPoint {
    var posAndSeed: SIMD4<Float>
    var color: SIMD4<Float>
}

struct MeshPointParams: Equatable, Identifiable {
    let id = UUID()
    var position: SIMD2<Float>
    var seed: SIMD2<Float>
    var color: SIMD4<Float>

    /// Standalone random point — used when the caller just needs "one more mesh point"
    /// and doesn't care about harmonizing with siblings. For a full palette refresh,
    /// call `MeshParams.reseed()` instead so all colors share a base hue.
    static func random() -> MeshPointParams {
        let baseHue = Float.random(in: 0...(.pi * 2))
        return MeshPointParams(
            position: randomPosition(),
            seed: randomSeed(),
            color: ColorHarmony.palette(count: 1,
                                        baseHue: baseHue,
                                        strategy: .analogous).first!
        )
    }

    static func randomPosition() -> SIMD2<Float> {
        SIMD2(.random(in: 0.1...0.9), .random(in: 0.1...0.9))
    }

    static func randomSeed() -> SIMD2<Float> {
        SIMD2(.random(in: 0...1), .random(in: 0...1))
    }
}

// MARK: - RenderParams

/// Canonical scene state: an ordered, user-editable list of layers plus scene
/// globals. Multiple layers of the same kind are allowed (two mesh layers, no
/// glass, three waves in a row — all valid). The per-kind SwiftUI controls
/// bind directly to a specific layer's params via `LayerRow`, so mutations
/// target a single entry even when several of the same kind exist.
struct RenderParams: Equatable {
    var layers: [LayerEntry]
    var globals: Globals

    // MARK: - Convenience projections onto globals

    var loopDuration: Float {
        get { globals.loopDuration }   set { globals.loopDuration = newValue }
    }
    var grainAmount: Float {
        get { globals.grainAmount }    set { globals.grainAmount = newValue }
    }
    var vignetteAmount: Float {
        get { globals.vignetteAmount } set { globals.vignetteAmount = newValue }
    }

    // MARK: - Layer operations

    /// Move the layer identified by `id` up (`delta = -1`) or down (`delta = +1`)
    /// in the render order. No-op if the move would fall outside the array.
    mutating func moveLayer(id: LayerEntry.ID, by delta: Int) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0 && j < layers.count else { return }
        layers.swapAt(i, j)
    }

    /// Move the layer identified by `sourceID` so it sits immediately before the
    /// layer identified by `targetID`. Used by drag-and-drop reorder.
    mutating func moveLayer(id sourceID: LayerEntry.ID, before targetID: LayerEntry.ID) {
        guard let src = layers.firstIndex(where: { $0.id == sourceID }),
              let dst = layers.firstIndex(where: { $0.id == targetID }),
              src != dst
        else { return }
        let entry = layers.remove(at: src)
        let insertAt = src < dst ? dst - 1 : dst
        layers.insert(entry, at: insertAt)
    }

    /// Insert a fresh default layer of `kind` immediately after the entry with
    /// the given `id`, or at the end if `id` is nil.
    mutating func addLayer(_ kind: LayerKind, after id: LayerEntry.ID? = nil) {
        let entry = LayerEntry(layer: kind.makeDefaultLayer())
        if let id, let i = layers.firstIndex(where: { $0.id == id }) {
            layers.insert(entry, at: i + 1)
        } else {
            layers.append(entry)
        }
    }

    /// Insert a copy of the layer identified by `id` immediately after it. The
    /// copy gets a fresh UUID so SwiftUI treats the rows as distinct.
    mutating func duplicateLayer(id: LayerEntry.ID) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        let source = layers[i]
        let copy = LayerEntry(layer: source.layer, enabled: source.enabled)
        layers.insert(copy, at: i + 1)
    }

    /// Remove the layer identified by `id`. No-op if it doesn't exist. Removing
    /// every layer leaves an empty pipeline — post-fx runs on a black canvas.
    mutating func removeLayer(id: LayerEntry.ID) {
        layers.removeAll { $0.id == id }
    }

    // MARK: - Default

    static let `default`: RenderParams = {
        let baseHue = Float.random(in: 0...(.pi * 2))
        let palette = ColorHarmony.palette(count: GradientRendererLimits.meshVertexCount,
                                           baseHue: baseHue,
                                           strategy: .analogous)
        let points = palette.map { color in
            MeshPointParams(position: MeshPointParams.randomPosition(),
                            seed: MeshPointParams.randomSeed(),
                            color: color)
        }
        // Render order: Linear → Mesh → Wave → Glass. Wave after Mesh so its
        // UV distortion re-samples the composited scene and visibly ripples
        // the mesh pattern.
        return RenderParams(
            layers: [
                LayerEntry(layer: .linear(LinearParams(
                    colorA: SIMD4(0.04, 0.01, 0.12, 1.0),
                    colorB: SIMD4(0.02, 0.02, 0.04, 1.0),
                    angle: .pi * 0.25,
                    rotationSpeed: 0.05
                ))),
                LayerEntry(layer: .mesh(MeshParams(
                    style: .grid,
                    opacity: 0.85,
                    driftSpeed: 0.4,
                    points: points
                ))),
                LayerEntry(layer: .wave(WaveParams(
                    amplitude: 0.08,
                    frequency: 2.2,
                    speed: 0.15
                ))),
                LayerEntry(layer: .glass(GlassParams(
                    enabled: true,
                    aberration: 0.3,
                    blurRadius: 0.15
                )))
            ],
            globals: Globals(
                loopDuration: 6.0,
                grainAmount: 0.06,
                vignetteAmount: 0.2
            )
        )
    }()

    // MARK: - Whole-scene helpers

    /// Apply an externally-supplied palette (e.g. extracted from an image) to
    /// every mesh and linear layer. Mesh layers share the same color list;
    /// linear layers get the two darkest entries as their gradient stops so
    /// Smoke/Blobs styles still read correctly against the background.
    mutating func applyPalette(_ colors: [SIMD4<Float>]) {
        guard !colors.isEmpty else { return }
        let byLuma = colors.sorted { MeshParams.relativeLuminance($0) < MeshParams.relativeLuminance($1) }
        let deepA = byLuma[0]
        let deepB = byLuma.count > 1 ? byLuma[1] : byLuma[0]

        for i in layers.indices {
            switch layers[i].layer {
            case .linear(var l):
                l.colorA = deepA
                l.colorB = deepB
                layers[i].layer = .linear(l)
            case .mesh(var m):
                m.applyColors(colors)
                layers[i].layer = .mesh(m)
            case .wave, .glass:
                break
            }
        }
    }

    /// Randomize every layer and the post-fx globals with a shared base hue
    /// and harmony strategy so the result stays cohesive across multiple layers
    /// of the same kind.
    mutating func randomize() {
        let baseHue = Float.random(in: 0...(.pi * 2))
        let strategy = ColorHarmony.Strategy.random()
        let (deepA, deepB) = ColorHarmony.deepPair(baseHue: baseHue, strategy: strategy)
        let palette = ColorHarmony.palette(count: GradientRendererLimits.meshVertexCount,
                                           baseHue: baseHue,
                                           strategy: strategy)

        for i in layers.indices {
            switch layers[i].layer {
            case .linear(var l):
                l.colorA = deepA
                l.colorB = deepB
                l.angle = .random(in: 0...(.pi * 2))
                l.rotationSpeed = .random(in: -0.3...0.3)
                layers[i].layer = .linear(l)

            case .wave(var w):
                // Wave range spans both subtle breathing and the glitch/zigzag look.
                w.amplitude = Bool.random()
                    ? .random(in: 0...0.08)
                    : .random(in: 0.15...0.35)
                w.frequency = .random(in: 0.5...5)
                w.speed = .random(in: 0...0.5)
                layers[i].layer = .wave(w)

            case .mesh(var m):
                m.opacity = .random(in: 0.6...1.0)
                m.driftSpeed = .random(in: 0...1.0)
                m.points = palette.map { color in
                    MeshPointParams(position: MeshPointParams.randomPosition(),
                                    seed: MeshPointParams.randomSeed(),
                                    color: color)
                }
                // Style: grid looks great edge-to-edge; blobs and smoke look great
                // on a dark canvas. Weight toward grid.
                switch Int.random(in: 0..<6) {
                case 0:  m.style = .blobs
                case 1:  m.style = .smoke
                default: m.style = .grid
                }
                // Smoke animation is driven entirely by driftSpeed — pin to a
                // lively range so randomize never produces a static scene.
                if m.style == .smoke {
                    m.driftSpeed = .random(in: 0.4...1.0)
                }
                layers[i].layer = .mesh(m)

            case .glass(var g):
                g.enabled = Bool.random()
                g.aberration = .random(in: 0...0.5)
                g.blurRadius = .random(in: 0...0.3)
                layers[i].layer = .glass(g)
            }
        }

        globals.grainAmount    = .random(in: 0.02...0.06)
        globals.vignetteAmount = .random(in: 0...0.6)
    }
}

// MARK: - Uniform builders on each params struct

extension LinearParams {
    func uniforms(loopPhase: Float, loopDuration: Float) -> LinearUniforms {
        LinearUniforms(
            colorA: colorA,
            colorB: colorB,
            angle: angle,
            rotationSpeed: rotationSpeed,
            loopPhase: loopPhase,
            loopDuration: max(loopDuration, 0.001)
        )
    }
}

extension WaveParams {
    func uniforms(loopPhase: Float, loopDuration: Float) -> WaveUniforms {
        WaveUniforms(
            amplitude: amplitude,
            frequency: frequency,
            speed: speed,
            loopPhase: loopPhase,
            loopDuration: max(loopDuration, 0.001)
        )
    }
}

extension MeshParams {
    func uniforms(loopPhase: Float, loopDuration: Float) -> MeshUniforms {
        MeshUniforms(
            smokeColor: brightestColor,
            opacity: opacity,
            driftSpeed: driftSpeed,
            loopPhase: loopPhase,
            loopDuration: max(loopDuration, 0.001),
            pointCount: Int32(points.count),
            style: style.rawValue
        )
    }

    /// Pack `MeshPointParams` into the wire format the shader expects.
    func metalMeshPoints() -> [MeshPoint] {
        points.map { p in
            MeshPoint(
                posAndSeed: SIMD4(p.position.x, p.position.y, p.seed.x, p.seed.y),
                color: p.color
            )
        }
    }
}

extension GlassParams {
    func uniforms() -> GlassUniforms {
        GlassUniforms(
            aberration: aberration,
            blurRadius: blurRadius,
            enabled: enabled ? 1 : 0
        )
    }
}

extension Globals {
    func postFxUniforms(resolution: SIMD2<Float>,
                        loopPhase: Float,
                        loopFrames: Int32) -> PostFxUniforms
    {
        PostFxUniforms(
            resolution: resolution,
            loopPhase: loopPhase,
            grainAmount: grainAmount,
            vignetteAmount: vignetteAmount,
            loopFrames: max(loopFrames, 1)
        )
    }
}

enum GradientRendererLimits {
    // 4x4 grid mesh, matching the Metal shader. Changing this requires shader updates.
    static let meshGridWidth = 4
    static let meshGridHeight = 4
    static var meshVertexCount: Int { meshGridWidth * meshGridHeight }
    static let maxMeshPoints = meshVertexCount
}
