import SwiftUI
import AppKit
import AVFoundation

@main
struct GradientStudioApp: App {
    @State private var state = AppState()

    init() {
        // Optional headless export path for smoke tests / batch jobs.
        // Set GRADIENT_EXPORT_PATH=/absolute/path.mp4 and (optionally)
        // GRADIENT_EXPORT_DURATION / _FPS / _WIDTH / _HEIGHT to customize.
        if let path = ProcessInfo.processInfo.environment["GRADIENT_EXPORT_PATH"] {
            Self.runHeadlessExport(toPath: path)
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }

    private static func runHeadlessExport(toPath path: String) {
        let env = ProcessInfo.processInfo.environment
        let width  = Int(env["GRADIENT_EXPORT_WIDTH"]    ?? "1280") ?? 1280
        let height = Int(env["GRADIENT_EXPORT_HEIGHT"]   ?? "720")  ?? 720
        let dur    = Double(env["GRADIENT_EXPORT_DURATION"] ?? "2") ?? 2
        let fps    = Int32(env["GRADIENT_EXPORT_FPS"]    ?? "30")   ?? 30

        let settings = VideoExporter.Settings(
            width: width,
            height: height,
            duration: dur,
            fps: fps,
            codec: .h264,
            outputURL: URL(fileURLWithPath: path)
        )

        let sem = DispatchSemaphore(value: 0)
        var failure: Error?

        Task.detached {
            do {
                try await VideoExporter.export(params: .default, settings: settings) { pct in
                    if Int(pct * 100).isMultiple(of: 10) {
                        fputs(String(format: "export %.0f%%\n", pct * 100), stderr)
                    }
                }
            } catch {
                failure = error
            }
            sem.signal()
        }
        sem.wait()

        if let failure {
            fputs("export failed: \(failure.localizedDescription)\n", stderr)
            exit(2)
        }
        fputs("export complete: \(path)\n", stderr)
    }

    var body: some Scene {
        WindowGroup("GradientStudio") {
            ContentView(state: state)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
    }
}
