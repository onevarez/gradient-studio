import Foundation
import MetalKit
import QuartzCore

final class PreviewRenderer: NSObject, MTKViewDelegate {
    let renderer: GradientRenderer
    var state: AppState
    private var lastTime: CFTimeInterval = CACurrentMediaTime()

    init(state: AppState) throws {
        self.state = state
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.noDevice
        }
        self.renderer = try GradientRenderer(device: device)
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }

        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now
        if state.isAnimating {
            state.time += Float(dt)
        }

        guard let cb = renderer.commandQueue.makeCommandBuffer() else { return }
        renderer.encode(
            into: cb,
            target: drawable.texture,
            time: state.time,
            params: state.params
        )
        cb.present(drawable)
        cb.commit()
    }
}
