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

            DisclosureGroup("Linear Gradient") {
                LinearGradientControls(params: $state.params).padding(.top, 4)
            }
            DisclosureGroup("Wave Distortion") {
                WaveControls(params: $state.params).padding(.top, 4)
            }
            DisclosureGroup("Mesh") {
                MeshControls(params: $state.params).padding(.top, 4)
            }
            DisclosureGroup("Glass") {
                GlassControls(params: $state.params).padding(.top, 4)
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
