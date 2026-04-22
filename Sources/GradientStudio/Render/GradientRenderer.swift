import Foundation
import Metal

enum RendererError: Error {
    case noDevice
    case cannotCreateQueue
    case cannotCompileLibrary(Error)
    case missingFunction
    case bufferAllocation
    case samplerAllocation
    case textureAllocation
}

/// Multi-pass renderer. Each layer kind (Linear, Wave, Mesh, Glass) is its own
/// fragment pipeline that reads the previous layer's output (except Linear, which
/// writes a fresh gradient). A final PostFx pass applies grain + vignette and
/// writes to the target texture.
///
/// Intermediate passes use `rgba16Float` ping-pong textures so repeated render-
/// texture round-trips don't lose precision to 8-bit quantization; the final
/// PostFx pipeline writes to the caller's target (`bgra8Unorm`).
final class GradientRenderer {
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm
    static let intermediatePixelFormat: MTLPixelFormat = .rgba16Float

    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    private let linearPipeline: MTLRenderPipelineState
    private let wavePipeline: MTLRenderPipelineState
    private let meshPipeline: MTLRenderPipelineState
    private let glassPipeline: MTLRenderPipelineState
    private let postFxPipeline: MTLRenderPipelineState

    private let sampler: MTLSamplerState

    private let linearUniformsBuffer: MTLBuffer
    private let waveUniformsBuffer: MTLBuffer
    private let meshUniformsBuffer: MTLBuffer
    private let glassUniformsBuffer: MTLBuffer
    private let postFxUniformsBuffer: MTLBuffer
    private let meshPointsBuffer: MTLBuffer

    // Ping-pong textures. Lazily (re)allocated to match target size.
    private var pingA: MTLTexture?
    private var pingB: MTLTexture?

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

        // Vertex shader is shared across all passes.
        guard let vfn = library.makeFunction(name: "vertexMain") else {
            throw RendererError.missingFunction
        }

        func makePipeline(fragmentName: String, format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            guard let ffn = library.makeFunction(name: fragmentName) else {
                throw RendererError.missingFunction
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.label = fragmentName
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = format
            return try device.makeRenderPipelineState(descriptor: desc)
        }

        self.linearPipeline  = try makePipeline(fragmentName: "linearFragment",
                                                format: Self.intermediatePixelFormat)
        self.wavePipeline    = try makePipeline(fragmentName: "waveFragment",
                                                format: Self.intermediatePixelFormat)
        self.meshPipeline    = try makePipeline(fragmentName: "meshFragment",
                                                format: Self.intermediatePixelFormat)
        self.glassPipeline   = try makePipeline(fragmentName: "glassFragment",
                                                format: Self.intermediatePixelFormat)
        self.postFxPipeline  = try makePipeline(fragmentName: "postFxFragment",
                                                format: Self.pixelFormat)

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.label = "GradientRenderer linear sampler"
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let s = device.makeSamplerState(descriptor: samplerDesc) else {
            throw RendererError.samplerAllocation
        }
        self.sampler = s

        func makeBuffer<T>(_ type: T.Type, label: String) throws -> MTLBuffer {
            guard let b = device.makeBuffer(length: MemoryLayout<T>.stride,
                                            options: .storageModeShared) else {
                throw RendererError.bufferAllocation
            }
            b.label = label
            return b
        }

        self.linearUniformsBuffer  = try makeBuffer(LinearUniforms.self,  label: "LinearUniforms")
        self.waveUniformsBuffer    = try makeBuffer(WaveUniforms.self,    label: "WaveUniforms")
        self.meshUniformsBuffer    = try makeBuffer(MeshUniforms.self,    label: "MeshUniforms")
        self.glassUniformsBuffer   = try makeBuffer(GlassUniforms.self,   label: "GlassUniforms")
        self.postFxUniformsBuffer  = try makeBuffer(PostFxUniforms.self,  label: "PostFxUniforms")

        let meshBytes = MemoryLayout<MeshPoint>.stride * GradientRendererLimits.maxMeshPoints
        guard let mb = device.makeBuffer(length: meshBytes, options: .storageModeShared) else {
            throw RendererError.bufferAllocation
        }
        mb.label = "MeshPoints"
        self.meshPointsBuffer = mb
    }

    /// Encode one full-screen gradient draw into the given command buffer, writing to `target`.
    /// Caller is responsible for committing the command buffer (and optionally scheduling a
    /// drawable present for live preview).
    ///
    /// `time` is elapsed seconds. Loop phase is derived as `(time mod params.loopDuration)
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

        // Ensure ping-pong textures match the target resolution.
        let (pA, pB) = ensurePingPong(width: target.width, height: target.height)

        // Upload per-pass uniforms.
        uploadUniforms(params.makeLinearUniforms(loopPhase: phase), into: linearUniformsBuffer)
        uploadUniforms(params.makeWaveUniforms(loopPhase: phase),   into: waveUniformsBuffer)
        uploadUniforms(params.makeMeshUniforms(loopPhase: phase),   into: meshUniformsBuffer)
        uploadUniforms(params.makeGlassUniforms(),                  into: glassUniformsBuffer)
        uploadUniforms(params.makePostFxUniforms(
                          resolution: SIMD2(Float(target.width), Float(target.height)),
                          loopPhase: phase,
                          loopFrames: frames),
                       into: postFxUniformsBuffer)

        // Upload mesh points.
        let points = params.makeMeshPointsArray()
        if !points.isEmpty {
            _ = points.withUnsafeBufferPointer { buf in
                memcpy(meshPointsBuffer.contents(),
                       buf.baseAddress,
                       MemoryLayout<MeshPoint>.stride * points.count)
            }
        }

        // Clear the initial canvas so the first enabled layer has a defined
        // input (matters if Linear isn't first, or if no Linear is enabled).
        encodeClearPass(commandBuffer, target: pA)

        var current = pA
        var next    = pB

        for entry in params.layers where entry.enabled {
            switch entry.layer {
            case .linear:
                // Linear ignores its input and writes a fresh gradient.
                encodeLinearPass(commandBuffer, target: next)
            case .wave:
                encodeInputPass(commandBuffer,
                                pipeline: wavePipeline,
                                uniformsBuffer: waveUniformsBuffer,
                                input: current,
                                target: next)
            case .mesh:
                encodeMeshPass(commandBuffer, input: current, target: next)
            case .glass:
                encodeInputPass(commandBuffer,
                                pipeline: glassPipeline,
                                uniformsBuffer: glassUniformsBuffer,
                                input: current,
                                target: next)
            }
            swap(&current, &next)
        }

        // PostFx always runs last, reading the final layer output and writing
        // to the caller's target texture (bgra8Unorm).
        encodeInputPass(commandBuffer,
                        pipeline: postFxPipeline,
                        uniformsBuffer: postFxUniformsBuffer,
                        input: current,
                        target: target)
    }

    // MARK: - Pass encoders

    private func encodeLinearPass(_ cb: MTLCommandBuffer, target: MTLTexture) {
        let pass = Self.makePassDescriptor(target: target)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = "Linear pass"
        enc.setRenderPipelineState(linearPipeline)
        enc.setFragmentBuffer(linearUniformsBuffer, offset: 0, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func encodeInputPass(_ cb: MTLCommandBuffer,
                                 pipeline: MTLRenderPipelineState,
                                 uniformsBuffer: MTLBuffer,
                                 input: MTLTexture,
                                 target: MTLTexture)
    {
        let pass = Self.makePassDescriptor(target: target)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = pipeline.label
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(input, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func encodeMeshPass(_ cb: MTLCommandBuffer, input: MTLTexture, target: MTLTexture) {
        let pass = Self.makePassDescriptor(target: target)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = "Mesh pass"
        enc.setRenderPipelineState(meshPipeline)
        enc.setFragmentBuffer(meshUniformsBuffer, offset: 0, index: 0)
        enc.setFragmentBuffer(meshPointsBuffer, offset: 0, index: 1)
        enc.setFragmentTexture(input, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private static func makePassDescriptor(target: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return pass
    }

    /// Encode a no-op pass that just clears the target to black. Used to seed
    /// the first ping-pong texture when the layer loop starts, so a non-Linear
    /// first layer has a defined (black) input to sample from.
    private func encodeClearPass(_ cb: MTLCommandBuffer, target: MTLTexture) {
        let pass = Self.makePassDescriptor(target: target)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = "Clear"
        enc.endEncoding()
    }

    // MARK: - Ping-pong lifecycle

    private func ensurePingPong(width: Int, height: Int) -> (MTLTexture, MTLTexture) {
        if let a = pingA, let b = pingB, a.width == width, a.height == height {
            return (a, b)
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.intermediatePixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private

        guard let a = device.makeTexture(descriptor: desc),
              let b = device.makeTexture(descriptor: desc)
        else {
            // Preserve the previous allocation on failure so the next encode doesn't
            // crash; the frame will render with stale textures at worst.
            return (pingA ?? device.makeTexture(descriptor: desc)!,
                    pingB ?? device.makeTexture(descriptor: desc)!)
        }
        a.label = "GradientRenderer ping A"
        b.label = "GradientRenderer ping B"
        self.pingA = a
        self.pingB = b
        return (a, b)
    }

    // MARK: - Uniform helpers

    private func uploadUniforms<T>(_ value: T, into buffer: MTLBuffer) {
        _ = withUnsafeBytes(of: value) { raw in
            memcpy(buffer.contents(), raw.baseAddress, raw.count)
        }
    }
}
