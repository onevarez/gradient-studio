import Foundation
import AppKit

enum PresetPasteboard {
    /// Encode `params` as pretty-printed JSON and write to the general pasteboard as
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

    /// Read the pasteboard's string contents and decode a `GradientPreset`. Throws
    /// `PresetError` with an actionable description if the contents are missing,
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

        let preset: GradientPreset
        do {
            preset = try JSONDecoder().decode(GradientPreset.self, from: data)
        } catch DecodingError.keyNotFound, DecodingError.typeMismatch, DecodingError.valueNotFound {
            throw PresetError.notAPreset
        } catch DecodingError.dataCorrupted(let ctx) {
            throw PresetError.invalidJSON(ctx.debugDescription)
        } catch {
            throw PresetError.notAPreset
        }

        guard preset.kind == GradientPreset.kindIdentifier else {
            throw PresetError.notAPreset
        }
        guard preset.schemaVersion == GradientPreset.currentSchemaVersion else {
            throw PresetError.unsupportedVersion(preset.schemaVersion)
        }
        return preset
    }

    // Custom pasteboard type — tagged so app-to-app paste of our JSON is unambiguous.
    private static let customType =
        NSPasteboard.PasteboardType("com.gradientstudio.preset.json")
}
