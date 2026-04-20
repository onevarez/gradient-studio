import Foundation
import Metal

enum RendererError: Error {
    case noDevice
    case cannotCreateQueue
    case cannotCompileLibrary(Error)
    case missingFunction
    case bufferAllocation
}

final class GradientRenderer {
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let uniformsBuffer: MTLBuffer
    private let meshPointsBuffer: MTLBuffer

    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.cannotCreateQueue
        }
        self.commandQueue = queue

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Shaders.source, options: nil)
        } catch {
            throw RendererError.cannotCompileLibrary(error)
        }

        guard let vfn = library.makeFunction(name: "vertexMain"),
              let ffn = library.makeFunction(name: "fragmentMain")
        else {
            throw RendererError.missingFunction
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = Self.pixelFormat
        self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)

        guard let ub = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: .storageModeShared) else {
            throw RendererError.bufferAllocation
        }
        self.uniformsBuffer = ub

        let meshBytes = MemoryLayout<MeshPoint>.stride * GradientRendererLimits.maxMeshPoints
        guard let mb = device.makeBuffer(length: meshBytes, options: .storageModeShared) else {
            throw RendererError.bufferAllocation
        }
        self.meshPointsBuffer = mb
    }

    /// Encode one full-screen gradient draw into the given command buffer, writing to `target`.
    /// Caller is responsible for committing the command buffer (and optionally scheduling a
    /// drawable present for live preview).
    ///
    /// `time` is the elapsed seconds. Loop phase is derived as `(time mod params.loopDuration)
    /// / params.loopDuration`, so animation wraps cleanly at every `loopDuration` boundary.
    /// Pass `loopFramesOverride` from the exporter to quantize grain to the exact output
    /// frame count (so the last frame's grain pattern matches the first's).
    func encode(into commandBuffer: MTLCommandBuffer,
                target: MTLTexture,
                time: Float,
                params: RenderParams,
                loopFramesOverride: Int32? = nil)
    {
        let duration = max(params.loopDuration, 0.001)
        let wrapped  = time.truncatingRemainder(dividingBy: duration)
        let phase    = (wrapped < 0 ? wrapped + duration : wrapped) / duration
        let frames   = loopFramesOverride ?? Int32(max(1, (duration * 30).rounded()))

        // Upload uniforms
        var uniforms = params.makeUniforms(
            resolution: SIMD2(Float(target.width), Float(target.height)),
            loopPhase: phase,
            loopFrames: frames
        )
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        // Upload mesh points
        let points = params.makeMeshPointsArray()
        if !points.isEmpty {
            _ = points.withUnsafeBufferPointer { buf in
                memcpy(meshPointsBuffer.contents(), buf.baseAddress, MemoryLayout<MeshPoint>.stride * points.count)
            }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(meshPointsBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
