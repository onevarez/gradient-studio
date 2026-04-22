import SwiftUI
import AppKit

struct ControlsView: View {
    @Bindable var state: AppState
    @State private var extractionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Toggle("Animate", isOn: $state.isAnimating)
                Spacer()
                Button("Rewind") { state.time = 0 }
            }

            HStack(spacing: 8) {
                Button {
                    state.params.randomize()
                } label: {
                    Label("Randomize", systemImage: "dice")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: [.command])

                Button {
                    pickImageAndExtractPalette()
                } label: {
                    Label("Image…", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }

            if let extractionError {
                Text(extractionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            labelled("Loop (s)", value: $state.params.loopDuration, range: 1...30)

            ForEach($state.params.layers) { $entry in
                LayerRow(entry: $entry, params: $state.params)
            }

            Menu {
                ForEach(LayerKind.allCases) { kind in
                    Button(kind.label) {
                        state.params.addLayer(kind)
                    }
                }
            } label: {
                Label("Add Layer", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)

            DisclosureGroup("Post") {
                PostControls(params: $state.params).padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private func pickImageAndExtractPalette() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        extractionError = nil
        do {
            let colors = try ImagePaletteExtractor.extract(
                from: url,
                k: GradientRendererLimits.meshVertexCount
            )
            state.params.applyPalette(colors)
        } catch {
            extractionError = error.localizedDescription
        }
    }
}

/// One row per entry in `params.layers`. Header carries reorder (↑ / ↓), an
/// enable toggle, the kind label, duplicate, and trash. Body expands into the
/// kind's SwiftUI controls, which bind directly to the entry's typed params.
struct LayerRow: View {
    @Binding var entry: LayerEntry
    @Binding var params: RenderParams
    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            controlsBody.padding(.top, 4)
        } label: {
            header
        }
        // Drag-to-reorder: drag any row onto another to move it there. Taps on
        // the row's buttons and disclosure chevron still work — draggable only
        // activates on drag gestures. The ↑ / ↓ chevrons in the header are
        // kept for keyboard / single-step reorder.
        .draggable(entry.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let str = items.first,
                  let src = UUID(uuidString: str)
            else { return false }
            params.moveLayer(id: src, before: entry.id)
            return true
        }
    }

    @ViewBuilder private var controlsBody: some View {
        switch entry.layer {
        case .linear: LinearGradientControls(params: linearParamsBinding)
        case .wave:   WaveControls(params: waveParamsBinding)
        case .mesh:   MeshControls(params: meshParamsBinding)
        case .glass:  GlassControls(params: glassParamsBinding)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button {
                params.moveLayer(id: entry.id, by: -1)
            } label: {
                Image(systemName: "chevron.up").font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(isFirst)
            .help("Move layer up")

            Button {
                params.moveLayer(id: entry.id, by: 1)
            } label: {
                Image(systemName: "chevron.down").font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(isLast)
            .help("Move layer down")

            Toggle("", isOn: $entry.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(entry.enabled ? "Disable layer" : "Enable layer")

            Text(entry.layer.kindLabel)
                .foregroundStyle(entry.enabled ? Color.primary : Color.secondary)

            Spacer()

            Button {
                params.duplicateLayer(id: entry.id)
            } label: {
                Image(systemName: "plus.square.on.square").font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Duplicate layer")

            Button {
                params.removeLayer(id: entry.id)
            } label: {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Remove layer")
        }
    }

    private var isFirst: Bool { params.layers.first?.id == entry.id }
    private var isLast:  Bool { params.layers.last?.id  == entry.id }

    // MARK: - Typed params bindings into the current entry's layer case.
    //
    // The getter's fallback branch is never hit in normal operation — the
    // switch in `controlsBody` guarantees the kind matches — but we return a
    // benign default instead of crashing, so a SwiftUI diff corner case
    // doesn't tank the UI.

    private var linearParamsBinding: Binding<LinearParams> {
        Binding(
            get: {
                if case .linear(let p) = entry.layer { return p }
                return LinearParams(colorA: SIMD4(0,0,0,1),
                                    colorB: SIMD4(0,0,0,1),
                                    angle: 0,
                                    rotationSpeed: 0)
            },
            set: { entry.layer = .linear($0) }
        )
    }

    private var waveParamsBinding: Binding<WaveParams> {
        Binding(
            get: {
                if case .wave(let p) = entry.layer { return p }
                return WaveParams(amplitude: 0, frequency: 0, speed: 0)
            },
            set: { entry.layer = .wave($0) }
        )
    }

    private var meshParamsBinding: Binding<MeshParams> {
        Binding(
            get: {
                if case .mesh(let p) = entry.layer { return p }
                return MeshParams(style: .grid, opacity: 0, driftSpeed: 0, points: [])
            },
            set: { entry.layer = .mesh($0) }
        )
    }

    private var glassParamsBinding: Binding<GlassParams> {
        Binding(
            get: {
                if case .glass(let p) = entry.layer { return p }
                return GlassParams(enabled: false, aberration: 0, blurRadius: 0)
            },
            set: { entry.layer = .glass($0) }
        )
    }
}

/// Shared labelled slider used by layer controls.
@ViewBuilder
func labelled(_ label: String,
              value: Binding<Float>,
              range: ClosedRange<Float>) -> some View
{
    VStack(alignment: .leading, spacing: 2) {
        HStack {
            Text(label).font(.caption)
            Spacer()
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        Slider(value: value, in: range)
    }
}
