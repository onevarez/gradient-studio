import Foundation
import simd

// Versioned JSON schema for sharing a `RenderParams` snapshot via clipboard/file.
// v2 carries the full composable layer list (order + per-layer enabled state)
// because users can now reorder and toggle layers — a v1 preset can't represent
// that state. v1 presets are still readable via `GradientPresetV1.upgraded()`.

struct GradientPreset: Codable {
    static let kindIdentifier       = "GradientStudio.Preset"
    static let currentSchemaVersion = 2

    var kind: String
    var schemaVersion: Int
    var layers: [LayerPreset]
    var globals: GlobalsPreset

    struct LayerPreset: Codable {
        var kind: String              // "linear" | "wave" | "mesh" | "glass"
        var enabled: Bool
        var params: LayerParamsPreset

        enum CodingKeys: String, CodingKey {
            case kind, enabled, params
        }

        init(kind: String, enabled: Bool, params: LayerParamsPreset) {
            self.kind = kind
            self.enabled = enabled
            self.params = params
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.kind = try c.decode(String.self, forKey: .kind)
            self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            switch kind {
            case "linear":
                self.params = .linear(try c.decode(LinearPresetParams.self, forKey: .params))
            case "wave":
                self.params = .wave(try c.decode(WavePresetParams.self, forKey: .params))
            case "mesh":
                self.params = .mesh(try c.decode(MeshPresetParams.self, forKey: .params))
            case "glass":
                self.params = .glass(try c.decode(GlassPresetParams.self, forKey: .params))
            default:
                throw PresetError.unknownLayerKind(kind)
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind, forKey: .kind)
            try c.encode(enabled, forKey: .enabled)
            switch params {
            case .linear(let p): try c.encode(p, forKey: .params)
            case .wave(let p):   try c.encode(p, forKey: .params)
            case .mesh(let p):   try c.encode(p, forKey: .params)
            case .glass(let p):  try c.encode(p, forKey: .params)
            }
        }
    }

    enum LayerParamsPreset {
        case linear(LinearPresetParams)
        case wave(WavePresetParams)
        case mesh(MeshPresetParams)
        case glass(GlassPresetParams)
    }

    struct LinearPresetParams: Codable {
        var colorA: [Float]
        var colorB: [Float]
        var angleRadians: Float
        var rotationSpeed: Float
    }

    struct WavePresetParams: Codable {
        var amplitude: Float
        var frequency: Float
        var speed: Float
    }

    struct MeshPresetParams: Codable {
        var style: String              // "grid" | "blobs" | "smoke"
        var opacity: Float
        var driftSpeed: Float
        var points: [MeshPointPreset]
    }

    struct MeshPointPreset: Codable {
        var position: [Float]
        var seed: [Float]
        var color: [Float]
    }

    struct GlassPresetParams: Codable {
        var enabled: Bool
        var aberration: Float
        var blurRadius: Float
    }

    struct GlobalsPreset: Codable {
        var loopDuration: Float
        var grain: Float
        var vignette: Float
    }
}

// MARK: - RenderParams ↔ GradientPreset (v2)

extension GradientPreset {
    init(from params: RenderParams) {
        self.kind = Self.kindIdentifier
        self.schemaVersion = Self.currentSchemaVersion
        self.layers = params.layers.map { entry in
            LayerPreset(
                kind: Self.kindString(of: entry.layer),
                enabled: entry.enabled,
                params: Self.paramsPreset(of: entry.layer)
            )
        }
        self.globals = GlobalsPreset(
            loopDuration: params.loopDuration,
            grain: params.grainAmount,
            vignette: params.vignetteAmount
        )
    }

    /// Copy preset values into `params`. Replaces the entire layer list (preserving
    /// preset order and per-layer enabled state) and overwrites globals. Mesh point
    /// `id`s are regenerated as fresh UUIDs since they're not part of the wire format.
    func apply(to params: inout RenderParams) throws {
        var newLayers: [LayerEntry] = []
        for p in layers {
            let layer = try Self.makeLayer(from: p.params)
            newLayers.append(LayerEntry(layer: layer, enabled: p.enabled))
        }

        // Day-1..3 invariant: exactly one of each kind present. Later phases will
        // relax this to support add / duplicate / remove.
        let kinds = Set(newLayers.map { Self.kindString(of: $0.layer) })
        let expected: Set<String> = ["linear", "wave", "mesh", "glass"]
        guard kinds == expected else {
            throw PresetError.missingLayerKinds(got: kinds, expected: expected)
        }

        params.layers = newLayers
        params.loopDuration    = globals.loopDuration
        params.grainAmount     = globals.grain
        params.vignetteAmount  = globals.vignette
    }

    private static func makeLayer(from p: LayerParamsPreset) throws -> Layer {
        switch p {
        case .linear(let l):
            return .linear(LinearParams(
                colorA: simd4(l.colorA),
                colorB: simd4(l.colorB),
                angle: l.angleRadians,
                rotationSpeed: l.rotationSpeed
            ))
        case .wave(let w):
            return .wave(WaveParams(
                amplitude: w.amplitude,
                frequency: w.frequency,
                speed: w.speed
            ))
        case .mesh(let m):
            let expected = GradientRendererLimits.meshVertexCount
            guard m.points.count == expected else {
                throw PresetError.meshPointCountMismatch(got: m.points.count, expected: expected)
            }
            return .mesh(MeshParams(
                style: meshStyle(from: m.style),
                opacity: m.opacity,
                driftSpeed: m.driftSpeed,
                points: m.points.map { pp in
                    MeshPointParams(
                        position: SIMD2(scalar(pp.position, 0), scalar(pp.position, 1)),
                        seed:     SIMD2(scalar(pp.seed, 0),     scalar(pp.seed, 1)),
                        color:    simd4(pp.color)
                    )
                }
            ))
        case .glass(let g):
            return .glass(GlassParams(
                enabled: g.enabled,
                aberration: g.aberration,
                blurRadius: g.blurRadius
            ))
        }
    }

    fileprivate static func kindString(of layer: Layer) -> String {
        switch layer {
        case .linear: return "linear"
        case .wave:   return "wave"
        case .mesh:   return "mesh"
        case .glass:  return "glass"
        }
    }

    private static func paramsPreset(of layer: Layer) -> LayerParamsPreset {
        switch layer {
        case .linear(let p):
            return .linear(LinearPresetParams(
                colorA: floats(p.colorA),
                colorB: floats(p.colorB),
                angleRadians: p.angle,
                rotationSpeed: p.rotationSpeed
            ))
        case .wave(let p):
            return .wave(WavePresetParams(
                amplitude: p.amplitude,
                frequency: p.frequency,
                speed: p.speed
            ))
        case .mesh(let p):
            return .mesh(MeshPresetParams(
                style: meshStyleString(p.style),
                opacity: p.opacity,
                driftSpeed: p.driftSpeed,
                points: p.points.map { pt in
                    MeshPointPreset(
                        position: [pt.position.x, pt.position.y],
                        seed:     [pt.seed.x, pt.seed.y],
                        color:    floats(pt.color)
                    )
                }
            ))
        case .glass(let p):
            return .glass(GlassPresetParams(
                enabled: p.enabled,
                aberration: p.aberration,
                blurRadius: p.blurRadius
            ))
        }
    }

    // MARK: - shared helpers

    fileprivate static func floats(_ v: SIMD4<Float>) -> [Float] { [v.x, v.y, v.z, v.w] }

    fileprivate static func simd4(_ a: [Float]) -> SIMD4<Float> {
        SIMD4(scalar(a, 0), scalar(a, 1), scalar(a, 2), scalar(a, 3, default: 1))
    }

    fileprivate static func scalar(_ a: [Float], _ i: Int, default defaultValue: Float = 0) -> Float {
        i < a.count ? a[i] : defaultValue
    }

    fileprivate static func meshStyleString(_ s: MeshStyle) -> String {
        switch s {
        case .grid:  return "grid"
        case .blobs: return "blobs"
        case .smoke: return "smoke"
        }
    }

    fileprivate static func meshStyle(from s: String) -> MeshStyle {
        switch s {
        case "blobs": return .blobs
        case "smoke": return .smoke
        default:      return .grid
        }
    }
}

// MARK: - V1 legacy schema (decode + migrate)

/// Older preset format (`schemaVersion == 1`). Flat fields per layer, no layer
/// order or enabled state. Decoding this produces an in-memory v1 struct; call
/// `.upgraded()` to lift it into a `GradientPreset` (v2) with the canonical
/// layer order `[linear, mesh, wave, glass]` and all-enabled flags.
struct GradientPresetV1: Codable {
    static let schemaVersion = 1

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
        var style: String
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

    /// Lift this v1 preset into the v2 schema. Layer order matches the current
    /// app default (`[linear, mesh, wave, glass]`) and all layers are enabled.
    func upgraded() -> GradientPreset {
        let layers: [GradientPreset.LayerPreset] = [
            GradientPreset.LayerPreset(
                kind: "linear",
                enabled: true,
                params: .linear(GradientPreset.LinearPresetParams(
                    colorA: linearGradient.colorA,
                    colorB: linearGradient.colorB,
                    angleRadians: linearGradient.angleRadians,
                    rotationSpeed: linearGradient.rotationSpeed
                ))
            ),
            GradientPreset.LayerPreset(
                kind: "mesh",
                enabled: true,
                params: .mesh(GradientPreset.MeshPresetParams(
                    style: mesh.style,
                    opacity: mesh.opacity,
                    driftSpeed: mesh.driftSpeed,
                    points: mesh.points.map { p in
                        GradientPreset.MeshPointPreset(
                            position: p.position,
                            seed: p.seed,
                            color: p.color
                        )
                    }
                ))
            ),
            GradientPreset.LayerPreset(
                kind: "wave",
                enabled: true,
                params: .wave(GradientPreset.WavePresetParams(
                    amplitude: wave.amplitude,
                    frequency: wave.frequency,
                    speed: wave.speed
                ))
            ),
            GradientPreset.LayerPreset(
                kind: "glass",
                enabled: true,
                params: .glass(GradientPreset.GlassPresetParams(
                    enabled: glass.enabled,
                    aberration: glass.aberration,
                    blurRadius: glass.blurRadius
                ))
            )
        ]
        return GradientPreset(
            kind: GradientPreset.kindIdentifier,
            schemaVersion: GradientPreset.currentSchemaVersion,
            layers: layers,
            globals: GradientPreset.GlobalsPreset(
                loopDuration: loop.duration,
                grain: post.grain,
                vignette: post.vignette
            )
        )
    }
}

// MARK: - Errors

enum PresetError: LocalizedError {
    case emptyClipboard
    case notAPreset
    case invalidJSON(String)
    case unsupportedVersion(Int)
    case meshPointCountMismatch(got: Int, expected: Int)
    case unknownLayerKind(String)
    case missingLayerKinds(got: Set<String>, expected: Set<String>)

    var errorDescription: String? {
        switch self {
        case .emptyClipboard:
            return "Clipboard is empty."
        case .notAPreset:
            return "Clipboard doesn't contain a GradientStudio preset."
        case .invalidJSON(let detail):
            return "Couldn't parse preset JSON: \(detail)"
        case .unsupportedVersion(let v):
            return "Unsupported preset version \(v). This app understands versions 1 and \(GradientPreset.currentSchemaVersion)."
        case .meshPointCountMismatch(let got, let expected):
            return "Preset has \(got) mesh points; this app expects \(expected)."
        case .unknownLayerKind(let k):
            return "Preset references unknown layer kind \"\(k)\"."
        case .missingLayerKinds(let got, let expected):
            let missing = expected.subtracting(got).sorted().joined(separator: ", ")
            return "Preset is missing required layer kinds: \(missing)."
        }
    }
}
