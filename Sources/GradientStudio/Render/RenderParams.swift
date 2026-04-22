import Foundation
import simd

// Per-pass uniform structs. Memory layout MUST match the corresponding struct
// in Shaders.swift. Each layer's fragment function reads one of these. Any field
// reorder or new field requires a coordinated edit on both sides.

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
    /// call `RenderParams.randomize()` instead so all colors share a base hue.
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

// Canonical storage is `layers: [LayerEntry]` + `globals: Globals`. The flat
// `lg*`, `wave*`, `mesh*`, `glass*`, and post-fx properties below are computed
// projections over the layer list — the UI, preset, shader-uniform builder, and
// export path all continue to use them unchanged.
//
// Invariant: `layers` contains exactly one entry of each kind. Order and
// per-entry `enabled` are user-editable (reorder + toggle). Later phases will
// relax "exactly one of each kind" to support add / duplicate / remove.
struct RenderParams: Equatable {
    var layers: [LayerEntry]
    var globals: Globals

    // MARK: - Typed layer accessors
    //
    // These locate the first entry of each kind and read/write via the enum case.
    // `preconditionFailure` guards the invariant — the code paths that build
    // `RenderParams` (default, randomize, preset.apply, undo/redo) all produce
    // four-entry arrays with exactly one of each kind.

    private var linear: LinearParams {
        get {
            for entry in layers { if case .linear(let p) = entry.layer { return p } }
            preconditionFailure("RenderParams has no linear layer")
        }
        set {
            for i in layers.indices {
                if case .linear = layers[i].layer { layers[i].layer = .linear(newValue); return }
            }
            preconditionFailure("RenderParams has no linear layer")
        }
    }

    private var wave: WaveParams {
        get {
            for entry in layers { if case .wave(let p) = entry.layer { return p } }
            preconditionFailure("RenderParams has no wave layer")
        }
        set {
            for i in layers.indices {
                if case .wave = layers[i].layer { layers[i].layer = .wave(newValue); return }
            }
            preconditionFailure("RenderParams has no wave layer")
        }
    }

    private var mesh: MeshParams {
        get {
            for entry in layers { if case .mesh(let p) = entry.layer { return p } }
            preconditionFailure("RenderParams has no mesh layer")
        }
        set {
            for i in layers.indices {
                if case .mesh = layers[i].layer { layers[i].layer = .mesh(newValue); return }
            }
            preconditionFailure("RenderParams has no mesh layer")
        }
    }

    private var glass: GlassParams {
        get {
            for entry in layers { if case .glass(let p) = entry.layer { return p } }
            preconditionFailure("RenderParams has no glass layer")
        }
        set {
            for i in layers.indices {
                if case .glass = layers[i].layer { layers[i].layer = .glass(newValue); return }
            }
            preconditionFailure("RenderParams has no glass layer")
        }
    }

    // MARK: - Layer reorder

    /// Move the layer identified by `id` up (`delta = -1`) or down (`delta = +1`)
    /// in the render order. No-op if the move would fall outside the array.
    mutating func moveLayer(id: LayerEntry.ID, by delta: Int) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0 && j < layers.count else { return }
        layers.swapAt(i, j)
    }

    // MARK: - Flat computed projections (back-compat surface)

    // Linear
    var lgColorA: SIMD4<Float> {
        get { linear.colorA } set { linear.colorA = newValue }
    }
    var lgColorB: SIMD4<Float> {
        get { linear.colorB } set { linear.colorB = newValue }
    }
    var lgAngle: Float {
        get { linear.angle } set { linear.angle = newValue }
    }
    var lgRotationSpeed: Float {
        get { linear.rotationSpeed } set { linear.rotationSpeed = newValue }
    }

    // Wave
    var waveAmplitude: Float {
        get { wave.amplitude } set { wave.amplitude = newValue }
    }
    var waveFrequency: Float {
        get { wave.frequency } set { wave.frequency = newValue }
    }
    var waveSpeed: Float {
        get { wave.speed } set { wave.speed = newValue }
    }

    // Mesh
    var meshOpacity: Float {
        get { mesh.opacity } set { mesh.opacity = newValue }
    }
    var meshDriftSpeed: Float {
        get { mesh.driftSpeed } set { mesh.driftSpeed = newValue }
    }
    var meshPoints: [MeshPointParams] {
        get { mesh.points } set { mesh.points = newValue }
    }
    var meshStyle: MeshStyle {
        get { mesh.style } set { mesh.style = newValue }
    }

    // Glass
    var glassEnabled: Bool {
        get { glass.enabled } set { glass.enabled = newValue }
    }
    var glassAberration: Float {
        get { glass.aberration } set { glass.aberration = newValue }
    }
    var glassBlurRadius: Float {
        get { glass.blurRadius } set { glass.blurRadius = newValue }
    }

    // Globals
    var grainAmount: Float {
        get { globals.grainAmount } set { globals.grainAmount = newValue }
    }
    var vignetteAmount: Float {
        get { globals.vignetteAmount } set { globals.vignetteAmount = newValue }
    }
    var loopDuration: Float {
        get { globals.loopDuration } set { globals.loopDuration = newValue }
    }

    // MARK: - Defaults

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
        // Order matches the render pipeline: Linear → Mesh → Wave → Glass, with
        // Wave deliberately after Mesh so its UV distortion re-samples the
        // composited scene (not just the bare background).
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

    // MARK: - Mesh-palette helpers

    /// Replace the mesh palette and (dark) background colors with an externally-supplied
    /// set — e.g. from image extraction. Positions and seeds of mesh points are preserved
    /// so motion stays continuous; only colors change. The two darkest palette entries
    /// become the linear-gradient stops so Smoke/Blobs styles still read correctly
    /// against the background.
    mutating func applyPalette(_ colors: [SIMD4<Float>]) {
        guard !colors.isEmpty else { return }
        let n = GradientRendererLimits.meshVertexCount
        for i in 0..<n {
            meshPoints[i].color = colors[i % colors.count]
        }
        let byLuma = colors.sorted { Self.relativeLuminance($0) < Self.relativeLuminance($1) }
        lgColorA = byLuma[0]
        lgColorB = byLuma.count > 1 ? byLuma[1] : byLuma[0]
    }

    private static func relativeLuminance(_ c: SIMD4<Float>) -> Float {
        0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
    }

    /// Rotate the mesh palette one step clockwise around the 4×4 grid. The outer ring
    /// (12 cells) and inner ring (4 cells) each rotate by one — after 12 calls the grid
    /// returns to its starting arrangement (LCM of ring periods 12 and 4).
    mutating func cycleMeshClockwise() {
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
        rotateMeshColors(along: outer)
        rotateMeshColors(along: inner)
    }

    private mutating func rotateMeshColors(along indices: [Int]) {
        guard indices.count > 1 else { return }
        let last = meshPoints[indices.last!].color
        for i in stride(from: indices.count - 1, through: 1, by: -1) {
            meshPoints[indices[i]].color = meshPoints[indices[i - 1]].color
        }
        meshPoints[indices[0]].color = last
    }

    /// Set the leftmost and rightmost grid columns to black.
    mutating func blackoutMeshSides() {
        let black = SIMD4<Float>(0, 0, 0, 1)
        let w = GradientRendererLimits.meshGridWidth
        let h = GradientRendererLimits.meshGridHeight
        for row in 0..<h {
            meshPoints[row * w + 0].color = black
            meshPoints[row * w + (w - 1)].color = black
        }
    }

    /// Set the top and bottom grid rows to black.
    mutating func blackoutMeshTopBottom() {
        let black = SIMD4<Float>(0, 0, 0, 1)
        let w = GradientRendererLimits.meshGridWidth
        let h = GradientRendererLimits.meshGridHeight
        for col in 0..<w {
            meshPoints[0 * w + col].color = black
            meshPoints[(h - 1) * w + col].color = black
        }
    }

    mutating func reseedMeshPoints() {
        let baseHue = Float.random(in: 0...(.pi * 2))
        let palette = ColorHarmony.palette(count: GradientRendererLimits.meshVertexCount,
                                           baseHue: baseHue,
                                           strategy: .analogous)
        meshPoints = palette.map { color in
            MeshPointParams(position: MeshPointParams.randomPosition(),
                            seed: MeshPointParams.randomSeed(),
                            color: color)
        }
    }

    mutating func randomize() {
        let baseHue = Float.random(in: 0...(.pi * 2))
        let strategy = ColorHarmony.Strategy.random()

        // Linear gradient: two deep tones in the same family as the mesh, for a cohesive
        // background that the vivid mesh points pop against.
        let (deepA, deepB) = ColorHarmony.deepPair(baseHue: baseHue, strategy: strategy)
        lgColorA = deepA
        lgColorB = deepB
        lgAngle = .random(in: 0...(.pi * 2))
        lgRotationSpeed = .random(in: -0.3...0.3)

        // Wave range spans both subtle breathing and the glitch/zigzag look.
        waveAmplitude = Bool.random()
            ? .random(in: 0...0.08)     // subtle
            : .random(in: 0.15...0.35)  // glitchy
        waveFrequency = .random(in: 0.5...5)
        waveSpeed = .random(in: 0...0.5)

        meshOpacity = .random(in: 0.6...1.0)
        meshDriftSpeed = .random(in: 0...1.0)

        let palette = ColorHarmony.palette(count: GradientRendererLimits.meshVertexCount,
                                           baseHue: baseHue,
                                           strategy: strategy)
        meshPoints = palette.map { color in
            MeshPointParams(position: MeshPointParams.randomPosition(),
                            seed: MeshPointParams.randomSeed(),
                            color: color)
        }

        glassEnabled = Bool.random()
        glassAberration = .random(in: 0...0.5)
        glassBlurRadius = .random(in: 0...0.3)

        // Mesh style: grid looks great edge-to-edge; blobs and smoke look great on a
        // dark canvas. Weight toward grid so the "black canvas" styles don't dominate.
        switch Int.random(in: 0..<6) {
        case 0:  meshStyle = .blobs
        case 1:  meshStyle = .smoke
        default: meshStyle = .grid
        }

        // Smoke animation is driven entirely by meshDriftSpeed — pin to a lively range
        // so randomize never produces a static scene.
        if meshStyle == .smoke {
            meshDriftSpeed = .random(in: 0.4...1.0)
        }
        grainAmount = .random(in: 0.02...0.06)
        vignetteAmount = .random(in: 0...0.6)
    }

    // MARK: - Shader adapters

    func makeLinearUniforms(loopPhase: Float) -> LinearUniforms {
        LinearUniforms(
            colorA: lgColorA,
            colorB: lgColorB,
            angle: lgAngle,
            rotationSpeed: lgRotationSpeed,
            loopPhase: loopPhase,
            loopDuration: max(loopDuration, 0.001)
        )
    }

    func makeWaveUniforms(loopPhase: Float) -> WaveUniforms {
        WaveUniforms(
            amplitude: waveAmplitude,
            frequency: waveFrequency,
            speed: waveSpeed,
            loopPhase: loopPhase,
            loopDuration: max(loopDuration, 0.001)
        )
    }

    func makeMeshUniforms(loopPhase: Float) -> MeshUniforms {
        MeshUniforms(
            smokeColor: brightestMeshColor(),
            opacity: meshOpacity,
            driftSpeed: meshDriftSpeed,
            loopPhase: loopPhase,
            loopDuration: max(loopDuration, 0.001),
            pointCount: Int32(meshPoints.count),
            style: meshStyle.rawValue
        )
    }

    func makeGlassUniforms() -> GlassUniforms {
        GlassUniforms(
            aberration: glassAberration,
            blurRadius: glassBlurRadius,
            enabled: glassEnabled ? 1 : 0
        )
    }

    func makePostFxUniforms(resolution: SIMD2<Float>,
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

    /// Brightest palette entry — used as Smoke's emission color so the glow stands
    /// out against the (dark) linear-gradient background regardless of palette order.
    private func brightestMeshColor() -> SIMD4<Float> {
        meshPoints
            .map(\.color)
            .max(by: { Self.relativeLuminance($0) < Self.relativeLuminance($1) })
            ?? SIMD4(1, 1, 1, 1)
    }

    func makeMeshPointsArray() -> [MeshPoint] {
        meshPoints.map { p in
            MeshPoint(
                posAndSeed: SIMD4(p.position.x, p.position.y, p.seed.x, p.seed.y),
                color: p.color
            )
        }
    }
}

enum GradientRendererLimits {
    // 4x4 grid mesh, matching the Metal shader. Changing this requires shader updates.
    static let meshGridWidth = 4
    static let meshGridHeight = 4
    static var meshVertexCount: Int { meshGridWidth * meshGridHeight }
    static let maxMeshPoints = meshVertexCount
}
