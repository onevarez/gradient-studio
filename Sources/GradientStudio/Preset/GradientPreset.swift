import Foundation
import simd

// Versioned JSON schema for sharing a `RenderParams` snapshot via clipboard/file.
// Deliberately decoupled from the runtime `RenderParams` struct so we can rename
// internal fields (e.g. `lgColorA`) without breaking presets users have already shared.

struct GradientPreset: Codable {
    static let kindIdentifier    = "GradientStudio.Preset"
    static let currentSchemaVersion = 1

    var kind: String
    var schemaVersion: Int

    var linearGradient: LinearGradientPreset
    var wave: WavePreset
    var mesh: MeshPreset
    var glass: GlassPreset
    var post: PostPreset
    var loop: LoopPreset

    struct LinearGradientPreset: Codable {
        var colorA: [Float]
        var colorB: [Float]
        var angleRadians: Float
        var rotationSpeed: Float
    }

    struct WavePreset: Codable {
        var amplitude: Float
        var frequency: Float
        var speed: Float
    }

    struct MeshPreset: Codable {
        var style: String          // "grid" | "blobs" | "smoke"
        var opacity: Float
        var driftSpeed: Float
        var points: [MeshPointPreset]
    }

    struct MeshPointPreset: Codable {
        var position: [Float]
        var seed: [Float]
        var color: [Float]
    }

    struct GlassPreset: Codable {
        var enabled: Bool
        var aberration: Float
        var blurRadius: Float
    }

    struct PostPreset: Codable {
        var grain: Float
        var vignette: Float
    }

    struct LoopPreset: Codable {
        var duration: Float
    }
}

// MARK: - RenderParams ↔ Preset

extension GradientPreset {
    init(from params: RenderParams) {
        self.kind = Self.kindIdentifier
        self.schemaVersion = Self.currentSchemaVersion
        self.linearGradient = LinearGradientPreset(
            colorA: Self.floats(params.lgColorA),
            colorB: Self.floats(params.lgColorB),
            angleRadians: params.lgAngle,
            rotationSpeed: params.lgRotationSpeed
        )
        self.wave = WavePreset(
            amplitude: params.waveAmplitude,
            frequency: params.waveFrequency,
            speed: params.waveSpeed
        )
        self.mesh = MeshPreset(
            style: Self.styleString(params.meshStyle),
            opacity: params.meshOpacity,
            driftSpeed: params.meshDriftSpeed,
            points: params.meshPoints.map { p in
                MeshPointPreset(
                    position: [p.position.x, p.position.y],
                    seed:     [p.seed.x, p.seed.y],
                    color:    Self.floats(p.color)
                )
            }
        )
        self.glass = GlassPreset(
            enabled: params.glassEnabled,
            aberration: params.glassAberration,
            blurRadius: params.glassBlurRadius
        )
        self.post = PostPreset(
            grain: params.grainAmount,
            vignette: params.vignetteAmount
        )
        self.loop = LoopPreset(duration: params.loopDuration)
    }

    /// Copy preset values into `params`. Mesh point `id`s are regenerated as fresh
    /// UUIDs since they're not part of the wire format.
    func apply(to params: inout RenderParams) throws {
        let expectedPointCount = GradientRendererLimits.meshVertexCount
        guard mesh.points.count == expectedPointCount else {
            throw PresetError.meshPointCountMismatch(got: mesh.points.count,
                                                     expected: expectedPointCount)
        }

        params.lgColorA        = Self.simd4(linearGradient.colorA)
        params.lgColorB        = Self.simd4(linearGradient.colorB)
        params.lgAngle         = linearGradient.angleRadians
        params.lgRotationSpeed = linearGradient.rotationSpeed

        params.waveAmplitude = wave.amplitude
        params.waveFrequency = wave.frequency
        params.waveSpeed     = wave.speed

        params.meshStyle      = Self.style(from: mesh.style)
        params.meshOpacity    = mesh.opacity
        params.meshDriftSpeed = mesh.driftSpeed
        params.meshPoints = mesh.points.map { p in
            MeshPointParams(
                position: SIMD2(Self.scalar(p.position, 0), Self.scalar(p.position, 1)),
                seed:     SIMD2(Self.scalar(p.seed, 0),     Self.scalar(p.seed, 1)),
                color:    Self.simd4(p.color)
            )
        }

        params.glassEnabled     = glass.enabled
        params.glassAberration  = glass.aberration
        params.glassBlurRadius  = glass.blurRadius

        params.grainAmount    = post.grain
        params.vignetteAmount = post.vignette

        params.loopDuration = loop.duration
    }

    // MARK: - helpers

    private static func floats(_ v: SIMD4<Float>) -> [Float] { [v.x, v.y, v.z, v.w] }

    private static func simd4(_ a: [Float]) -> SIMD4<Float> {
        SIMD4(scalar(a, 0), scalar(a, 1), scalar(a, 2), scalar(a, 3, default: 1))
    }

    private static func scalar(_ a: [Float], _ i: Int, default defaultValue: Float = 0) -> Float {
        i < a.count ? a[i] : defaultValue
    }

    private static func styleString(_ s: MeshStyle) -> String {
        switch s {
        case .grid:  return "grid"
        case .blobs: return "blobs"
        case .smoke: return "smoke"
        }
    }

    private static func style(from s: String) -> MeshStyle {
        switch s {
        case "blobs": return .blobs
        case "smoke": return .smoke
        default:      return .grid   // unknown → safest default
        }
    }
}

// MARK: - Errors

enum PresetError: LocalizedError {
    case emptyClipboard
    case notAPreset
    case invalidJSON(String)
    case unsupportedVersion(Int)
    case meshPointCountMismatch(got: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case .emptyClipboard:
            return "Clipboard is empty."
        case .notAPreset:
            return "Clipboard doesn't contain a GradientStudio preset."
        case .invalidJSON(let detail):
            return "Couldn't parse preset JSON: \(detail)"
        case .unsupportedVersion(let v):
            return "Unsupported preset version \(v). This app understands version \(GradientPreset.currentSchemaVersion)."
        case .meshPointCountMismatch(let got, let expected):
            return "Preset has \(got) mesh points; this app expects \(expected)."
        }
    }
}
