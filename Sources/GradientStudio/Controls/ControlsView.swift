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

            ForEach(state.params.layers) { entry in
                LayerRow(entry: entry, params: $state.params)
            }

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
/// enable toggle, and the kind label. Body expands into the kind's existing
/// SwiftUI controls, which bind through `RenderParams`' computed projections.
struct LayerRow: View {
    let entry: LayerEntry
    @Binding var params: RenderParams
    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            controls.padding(.top, 4)
        } label: {
            header
        }
    }

    @ViewBuilder private var controls: some View {
        switch entry.layer {
        case .linear: LinearGradientControls(params: $params)
        case .wave:   WaveControls(params: $params)
        case .mesh:   MeshControls(params: $params)
        case .glass:  GlassControls(params: $params)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button {
                params.moveLayer(id: entry.id, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(isFirst)
            .help("Move layer up")

            Button {
                params.moveLayer(id: entry.id, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(isLast)
            .help("Move layer down")

            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(entry.enabled ? "Disable layer" : "Enable layer")

            Text(entry.layer.kindLabel)
                .foregroundStyle(entry.enabled ? Color.primary : Color.secondary)

            Spacer()
        }
    }

    private var isFirst: Bool { params.layers.first?.id == entry.id }
    private var isLast:  Bool { params.layers.last?.id  == entry.id }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { entry.enabled },
            set: { value in
                if let i = params.layers.firstIndex(where: { $0.id == entry.id }) {
                    params.layers[i].enabled = value
                }
            }
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
