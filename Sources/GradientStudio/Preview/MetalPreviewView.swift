import SwiftUI
import MetalKit

struct MetalPreviewView: NSViewRepresentable {
    let state: AppState

    func makeCoordinator() -> PreviewRenderer {
        do {
            return try PreviewRenderer(state: state)
        } catch {
            fatalError("Failed to create preview renderer: \(error)")
        }
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.renderer.device
        view.colorPixelFormat = GradientRenderer.pixelFormat
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Keep the coordinator's state reference fresh if SwiftUI re-binds it.
        context.coordinator.state = state
    }
}
