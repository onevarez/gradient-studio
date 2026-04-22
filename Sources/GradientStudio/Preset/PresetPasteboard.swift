import Foundation
import AppKit

enum PresetPasteboard {
    /// Encode `params` as pretty-printed v2 JSON and write to the general pasteboard as
    /// `.string` (so users can paste into a text editor or chat) plus a custom type
    /// marker so round-trip copy/paste within the app can skip ambiguity.
    static func copy(_ params: RenderParams) throws {
        let preset = GradientPreset(from: params)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preset)
        guard let text = String(data: data, encoding: .utf8) else {
            throw PresetError.invalidJSON("could not stringify encoded preset")
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        pb.setString(text, forType: customType)
    }

    /// Read the pasteboard's string contents and decode a `GradientPreset`.
    /// Supports v1 (legacy flat shape, migrated on read) and v2 (current schema).
    /// Throws `PresetError` with an actionable description if the contents are missing,
    /// unrelated, malformed, or from a future schema version.
    static func paste() throws -> GradientPreset {
        let pb = NSPasteboard.general
        guard let raw = pb.string(forType: customType) ?? pb.string(forType: .string) else {
            throw PresetError.emptyClipboard
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = text.data(using: .utf8) else {
            throw PresetError.notAPreset
        }

        // First decode just the envelope to dispatch on schemaVersion.
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch DecodingError.keyNotFound, DecodingError.typeMismatch, DecodingError.valueNotFound {
            throw PresetError.notAPreset
        } catch DecodingError.dataCorrupted(let ctx) {
            throw PresetError.invalidJSON(ctx.debugDescription)
        } catch {
            throw PresetError.notAPreset
        }

        guard envelope.kind == GradientPreset.kindIdentifier else {
            throw PresetError.notAPreset
        }

        switch envelope.schemaVersion {
        case GradientPresetV1.schemaVersion:
            let v1: GradientPresetV1
            do {
                v1 = try JSONDecoder().decode(GradientPresetV1.self, from: data)
            } catch DecodingError.dataCorrupted(let ctx) {
                throw PresetError.invalidJSON(ctx.debugDescription)
            } catch {
                throw PresetError.notAPreset
            }
            return v1.upgraded()

        case GradientPreset.currentSchemaVersion:
            do {
                return try JSONDecoder().decode(GradientPreset.self, from: data)
            } catch let error as PresetError {
                throw error
            } catch DecodingError.dataCorrupted(let ctx) {
                throw PresetError.invalidJSON(ctx.debugDescription)
            } catch {
                throw PresetError.notAPreset
            }

        default:
            throw PresetError.unsupportedVersion(envelope.schemaVersion)
        }
    }

    /// Minimal shape used to peek at the preset's kind and schemaVersion before
    /// choosing a full decoder.
    private struct Envelope: Decodable {
        var kind: String
        var schemaVersion: Int
    }

    // Custom pasteboard type — tagged so app-to-app paste of our JSON is unambiguous.
    private static let customType =
        NSPasteboard.PasteboardType("com.gradientstudio.preset.json")
}
