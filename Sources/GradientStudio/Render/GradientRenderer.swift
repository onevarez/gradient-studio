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
/// fragment pipeline that reads the previous layer's output (except Linear,
/// which writes a fresh gradient). A final PostFx pass applies grain + vignette
/// and writes to the target texture.
///
/// Intermediate passes use `rgba16Float` ping-pong textures so repeated render-
/// texture round-trips don't lose precision to 8-bit quantization; the final
/// PostFx pipeline writes to the caller's target (`bgra8Unorm`).
///
/// Multiple layers of the same kind are supported. Each layer gets its own
/// uniform buffer from a per-kind pool, grown lazily as needed.
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

    // Per-kind uniform buffer pools. Each pass in the layer loop gets its own
    // buffer so the GPU sees distinct uniforms per pass even when the CPU has
    // written to several "of the same kind" within one command buffer.
    private var linearUniformsBuffers: [MTLBuffer] = []
    private var waveUniformsBuffers:   [MTLBuffer] = []
    private var meshUniformsBuffers:   [MTLBuffer] = []
    private var meshPointsBuffers:     [MTLBuffer] = []
    private var glassUniformsBuffers:  [MTLBuffer] = []

    private let postFxUniformsBuffer: MTLBuffer

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

        guard let pfxBuf = device.makeBuffer(length: MemoryLayout<PostFxUniforms>.stride,
                                             options: .storageModeShared) else {
            throw RendererError.bufferAllocation
        }
        pfxBuf.label = "PostFxUniforms"
        self.postFxUniformsBuffer = pfxBuf
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

        // Seed canvas so a non-Linear first layer has a defined (black) input.
        encodeClearPass(commandBuffer, target: pA)

        var current = pA
        var next    = pB

        // Per-kind indices into the uniform buffer pools. Advance on use so
        // successive layers of the same kind bind distinct buffers.
        var linearIdx = 0
        var waveIdx   = 0
        var meshIdx   = 0
        var glassIdx  = 0

        for entry in params.layers where entry.enabled {
            switch entry.layer {
            case .linear(let p):
                let buf = linearBuffer(at: linearIdx)
                uploadUniforms(p.uniforms(loopPhase: phase, loopDuration: duration),
                               into: buf)
                encodeLinearPass(commandBuffer, uniformsBuffer: buf, target: next)
                linearIdx += 1

            case .wave(let p):
                let buf = waveBuffer(at: waveIdx)
                uploadUniforms(p.uniforms(loopPhase: phase, loopDuration: duration),
                               into: buf)
                encodeInputPass(commandBuffer,
                                pipeline: wavePipeline,
                                uniformsBuffer: buf,
                                input: current,
                                target: next)
                waveIdx += 1

            case .mesh(let p):
                let ubuf = meshBuffer(at: meshIdx)
                let pbuf = meshPointsBuffer(at: meshIdx)
                uploadUniforms(p.uniforms(loopPhase: phase, loopDuration: duration),
                               into: ubuf)
                uploadMeshPoints(p.metalMeshPoints(), into: pbuf)
                encodeMeshPass(commandBuffer,
                               uniformsBuffer: ubuf,
                               meshPointsBuffer: pbuf,
                               input: current,
                               target: next)
                meshIdx += 1

            case .glass(let p):
                let buf = glassBuffer(at: glassIdx)
                uploadUniforms(p.uniforms(), into: buf)
                encodeInputPass(commandBuffer,
                                pipeline: glassPipeline,
                                uniformsBuffer: buf,
                                input: current,
                                target: next)
                glassIdx += 1
            }
            swap(&current, &next)
        }

        // PostFx always runs last, reading the final layer output and writing
        // to the caller's target texture (bgra8Unorm).
        uploadUniforms(params.globals.postFxUniforms(
                         resolution: SIMD2(Float(target.width), Float(target.height)),
                         loopPhase: phase,
                         loopFrames: frames),
                       into: postFxUniformsBuffer)
        encodeInputPass(commandBuffer,
                        pipeline: postFxPipeline,
                        uniformsBuffer: postFxUniformsBuffer,
                        input: current,
                        target: target)
    }

    // MARK: - Pass encoders

    private func encodeLinearPass(_ cb: MTLCommandBuffer,
                                  uniformsBuffer: MTLBuffer,
                                  target: MTLTexture)
    {
        let pass = Self.makePassDescriptor(target: target)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = "Linear pass"
        enc.setRenderPipelineState(linearPipeline)
        enc.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
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

    private func encodeMeshPass(_ cb: MTLCommandBuffer,
                                uniformsBuffer: MTLBuffer,
                                meshPointsBuffer: MTLBuffer,
                                input: MTLTexture,
                                target: MTLTexture)
    {
        let pass = Self.makePassDescriptor(target: target)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = "Mesh pass"
        enc.setRenderPipelineState(meshPipeline)
        enc.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
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

    /// Encode a no-op pass that just clears the target to black.
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
            return (pingA ?? device.makeTexture(descriptor: desc)!,
                    pingB ?? device.makeTexture(descriptor: desc)!)
        }
        a.label = "GradientRenderer ping A"
        b.label = "GradientRenderer ping B"
        self.pingA = a
        self.pingB = b
        return (a, b)
    }

    // MARK: - Uniform buffer pools

    private func linearBuffer(at idx: Int) -> MTLBuffer {
        while linearUniformsBuffers.count <= idx {
            let i = linearUniformsBuffers.count
            let buf = device.makeBuffer(length: MemoryLayout<LinearUniforms>.stride,
                                        options: .storageModeShared)!
            buf.label = "LinearUniforms[\(i)]"
            linearUniformsBuffers.append(buf)
        }
        return linearUniformsBuffers[idx]
    }

    private func waveBuffer(at idx: Int) -> MTLBuffer {
        while waveUniformsBuffers.count <= idx {
            let i = waveUniformsBuffers.count
            let buf = device.makeBuffer(length: MemoryLayout<WaveUniforms>.stride,
                                        options: .storageModeShared)!
            buf.label = "WaveUniforms[\(i)]"
            waveUniformsBuffers.append(buf)
        }
        return waveUniformsBuffers[idx]
    }

    private func meshBuffer(at idx: Int) -> MTLBuffer {
        while meshUniformsBuffers.count <= idx {
            let i = meshUniformsBuffers.count
            let buf = device.makeBuffer(length: MemoryLayout<MeshUniforms>.stride,
                                        options: .storageModeShared)!
            buf.label = "MeshUniforms[\(i)]"
            meshUniformsBuffers.append(buf)
        }
        return meshUniformsBuffers[idx]
    }

    private func meshPointsBuffer(at idx: Int) -> MTLBuffer {
        while meshPointsBuffers.count <= idx {
            let i = meshPointsBuffers.count
            let bytes = MemoryLayout<MeshPoint>.stride * GradientRendererLimits.maxMeshPoints
            let buf = device.makeBuffer(length: bytes, options: .storageModeShared)!
            buf.label = "MeshPoints[\(i)]"
            meshPointsBuffers.append(buf)
        }
        return meshPointsBuffers[idx]
    }

    private func glassBuffer(at idx: Int) -> MTLBuffer {
        while glassUniformsBuffers.count <= idx {
            let i = glassUniformsBuffers.count
            let buf = device.makeBuffer(length: MemoryLayout<GlassUniforms>.stride,
                                        options: .storageModeShared)!
            buf.label = "GlassUniforms[\(i)]"
            glassUniformsBuffers.append(buf)
        }
        return glassUniformsBuffers[idx]
    }

    // MARK: - Upload helpers

    private func uploadUniforms<T>(_ value: T, into buffer: MTLBuffer) {
        _ = withUnsafeBytes(of: value) { raw in
            memcpy(buffer.contents(), raw.baseAddress, raw.count)
        }
    }

    private func uploadMeshPoints(_ points: [MeshPoint], into buffer: MTLBuffer) {
        guard !points.isEmpty else { return }
        _ = points.withUnsafeBufferPointer { ptr in
            memcpy(buffer.contents(),
                   ptr.baseAddress,
                   MemoryLayout<MeshPoint>.stride * points.count)
        }
    }
}
