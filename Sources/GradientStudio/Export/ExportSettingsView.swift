import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct ExportSettingsView: View {
    @Bindable var state: AppState
    @Binding var isPresented: Bool

    @State private var width: Int = 1920
    @State private var height: Int = 1080
    @State private var duration: Double = 5
    @State private var fps: Int32 = 30
    @State private var codec: Codec = .h264
    @State private var isExporting = false
    @State private var progress: Double = 0
    @State private var errorText: String?

    enum Codec: String, CaseIterable, Identifiable {
        case h264 = "H.264"
        case hevc = "HEVC"
        var id: String { rawValue }
        var avType: AVVideoCodecType {
            self == .h264 ? .h264 : .hevc
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export MP4").font(.title2.bold())

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Resolution")
                    HStack {
                        TextField("W", value: $width, format: .number).frame(width: 80)
                        Text("×")
                        TextField("H", value: $height, format: .number).frame(width: 80)
                        Menu("Preset") {
                            Button("1280 × 720") { width = 1280; height = 720 }
                            Button("1920 × 1080") { width = 1920; height = 1080 }
                            Button("2560 × 1440") { width = 2560; height = 1440 }
                            Button("3840 × 2160") { width = 3840; height = 2160 }
                            Button("1080 × 1080 (square)") { width = 1080; height = 1080 }
                        }
                    }
                }
                GridRow {
                    Text("Duration (s)")
                    TextField("", value: $duration, format: .number).frame(width: 100)
                }
                GridRow {
                    Text("FPS")
                    Picker("", selection: $fps) {
                        Text("30").tag(Int32(30))
                        Text("60").tag(Int32(60))
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .labelsHidden()
                }
                GridRow {
                    Text("Codec")
                    Picker("", selection: $codec) {
                        ForEach(Codec.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .labelsHidden()
                }
            }

            if isExporting {
                ProgressView(value: progress, total: 1.0) {
                    Text(String(format: "Exporting… %.0f%%", progress * 100))
                        .font(.caption)
                }
            }

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isExporting)
                Button("Export…") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isExporting || width <= 0 || height <= 0 || duration <= 0)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func start() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.mpeg4Movie]
        panel.nameFieldStringValue = "gradient.mp4"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        errorText = nil
        progress = 0
        isExporting = true

        let settings = VideoExporter.Settings(
            width: width,
            height: height,
            duration: duration,
            fps: fps,
            codec: codec.avType,
            outputURL: url
        )
        let params = state.params

        Task {
            do {
                try await VideoExporter.export(params: params, settings: settings) { p in
                    Task { @MainActor in
                        progress = p
                    }
                }
                await MainActor.run {
                    state.lastExportURL = url
                    isExporting = false
                    isPresented = false
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
}
