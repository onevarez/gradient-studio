import Foundation
import simd

// Memory layout MUST match `Uniforms` in Shaders.swift.
struct Uniforms {
    var resolution: SIMD2<Float>
    var loopPhase: Float
    var meshPointCount: Int32
    var lgColorA: SIMD4<Float>
    var lgColorB: SIMD4<Float>
    var lgAngle: Float
    var lgRotationSpeed: Float
    var waveAmplitude: Float
    var waveFrequency: Float
    var waveSpeed: Float
    var meshDriftSpeed: Float
    var meshOpacity: Float
    var glassAberration: Float
    var glassBlurRadius: Float
    var glassEnabled: Int32
    var _pad0: Float = 0
    var _pad1: Float = 0
    var grainAmount: Float
    var vignetteAmount: Float
    var meshStyle: Int32        // 0 = grid, 1 = blobs
    var _pad2: Float = 0
    var loopDuration: Float
    var loopFrames: Int32
    var _pad3: Float = 0
    var _pad4: Float = 0
    var smokeColor: SIMD4<Float>
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

struct RenderParams: Equatable {
    // Linear
    var lgColorA: SIMD4<Float>
    var lgColorB: SIMD4<Float>
    var lgAngle: Float                // radians
    var lgRotationSpeed: Float        // rad/sec

    // Wave
    var waveAmplitude: Float          // uv units, typical 0..0.2
    var waveFrequency: Float          // noise freq, typical 0..8
    var waveSpeed: Float               // time scale

    // Mesh
    var meshOpacity: Float             // 0..1 blend over base
    var meshDriftSpeed: Float
    var meshPoints: [MeshPointParams]

    // Glass
    var glassEnabled: Bool
    var glassAberration: Float         // 0..1
    var glassBlurRadius: Float         // 0..1

    // Post / Style
    var meshStyle: MeshStyle
    var grainAmount: Float              // 0..0.3
    var vignetteAmount: Float           // 0..1

    // Loop — clip length for seamless looping. Export overrides with its duration.
    var loopDuration: Float             // seconds

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
        return RenderParams(
            lgColorA: SIMD4(0.04, 0.01, 0.12, 1.0),
            lgColorB: SIMD4(0.02, 0.02, 0.04, 1.0),
            lgAngle: .pi * 0.25,
            lgRotationSpeed: 0.05,
            waveAmplitude: 0.08,
            waveFrequency: 2.2,
            waveSpeed: 0.15,
            meshOpacity: 0.85,
            meshDriftSpeed: 0.4,
            meshPoints: points,
            glassEnabled: true,
            glassAberration: 0.3,
            glassBlurRadius: 0.15,
            meshStyle: .grid,
            grainAmount: 0.06,
            vignetteAmount: 0.2,
            loopDuration: 6.0
        )
    }()

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

    func makeUniforms(resolution: SIMD2<Float>,
                      loopPhase: Float,
                      loopFrames: Int32) -> Uniforms
    {
        Uniforms(
            resolution: resolution,
            loopPhase: loopPhase,
            meshPointCount: Int32(meshPoints.count),
            lgColorA: lgColorA,
            lgColorB: lgColorB,
            lgAngle: lgAngle,
            lgRotationSpeed: lgRotationSpeed,
            waveAmplitude: waveAmplitude,
            waveFrequency: waveFrequency,
            waveSpeed: waveSpeed,
            meshDriftSpeed: meshDriftSpeed,
            meshOpacity: meshOpacity,
            glassAberration: glassAberration,
            glassBlurRadius: glassBlurRadius,
            glassEnabled: glassEnabled ? 1 : 0,
            grainAmount: grainAmount,
            vignetteAmount: vignetteAmount,
            meshStyle: meshStyle.rawValue,
            loopDuration: max(loopDuration, 0.001),
            loopFrames: max(loopFrames, 1),
            smokeColor: brightestMeshColor()
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
