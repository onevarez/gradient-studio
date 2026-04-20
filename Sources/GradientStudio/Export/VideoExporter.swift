import Foundation
import AVFoundation
import Metal
import CoreVideo

enum ExportError: Error, LocalizedError {
    case noDevice
    case textureCacheFailed
    case cannotAddInput
    case cannotStartWriter(Error?)
    case pixelBufferPoolMissing
    case pixelBufferAllocationFailed
    case textureWrapFailed
    case commandBufferCreationFailed
    case appendFailed(Error?)
    case finalizeFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .noDevice: return "No Metal device available."
        case .textureCacheFailed: return "Failed to create CVMetalTextureCache."
        case .cannotAddInput: return "AVAssetWriter rejected the video input."
        case .cannotStartWriter(let e): return "Could not start writer: \(e?.localizedDescription ?? "unknown")"
        case .pixelBufferPoolMissing: return "AVAssetWriterInputPixelBufferAdaptor has no pixel buffer pool."
        case .pixelBufferAllocationFailed: return "Could not allocate a pixel buffer from the pool."
        case .textureWrapFailed: return "Could not wrap pixel buffer as a Metal texture."
        case .commandBufferCreationFailed: return "Could not create a Metal command buffer."
        case .appendFailed(let e): return "Appending a frame failed: \(e?.localizedDescription ?? "unknown")"
        case .finalizeFailed(let e): return "Finalizing the writer failed: \(e?.localizedDescription ?? "unknown")"
        }
    }
}

enum VideoExporter {
    struct Settings {
        var width: Int
        var height: Int
        var duration: Double
        var fps: Int32
        var codec: AVVideoCodecType
        var outputURL: URL
    }

    /// Renders every frame offscreen and muxes into an mp4. `progress` is called with
    /// values in 0...1 as frames are finalized, on whichever executor the exporter happens
    /// to be running on. Callers that touch UI state should hop to `MainActor` themselves.
    static func export(params: RenderParams,
                       settings: Settings,
                       progress: @escaping @Sendable (Double) -> Void) async throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else { throw ExportError.noDevice }
        let renderer = try GradientRenderer(device: device)

        // Clean up any stale file at the output location.
        try? FileManager.default.removeItem(at: settings.outputURL)

        let writer = try AVAssetWriter(outputURL: settings.outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: settings.codec,
            AVVideoWidthKey: settings.width,
            AVVideoHeightKey: settings.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: defaultBitrate(width: settings.width, height: settings.height, fps: settings.fps)
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: settings.width,
            kCVPixelBufferHeightKey as String: settings.height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttrs
        )

        guard writer.canAdd(input) else { throw ExportError.cannotAddInput }
        writer.add(input)

        guard writer.startWriting() else { throw ExportError.cannotStartWriter(writer.error) }
        writer.startSession(atSourceTime: .zero)

        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard cacheStatus == kCVReturnSuccess, let textureCache = cache else {
            throw ExportError.textureCacheFailed
        }

        let totalFrames = max(1, Int((settings.duration * Double(settings.fps)).rounded()))
        let timescale = CMTimeScale(settings.fps)

        // Force the clip's loop period to match the export duration so phase runs
        // 0 → (totalFrames-1)/totalFrames exactly, and the wrap from last frame to
        // first is seamless.
        var loopingParams = params
        loopingParams.loopDuration = Float(settings.duration)

        for frame in 0..<totalFrames {
            // Backpressure: wait for the writer to accept more data.
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 500_000)
            }

            guard let pool = adaptor.pixelBufferPool else {
                throw ExportError.pixelBufferPoolMissing
            }
            var maybePB: CVPixelBuffer?
            let alloc = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybePB)
            guard alloc == kCVReturnSuccess, let pixelBuffer = maybePB else {
                throw ExportError.pixelBufferAllocationFailed
            }

            var cvMetalTex: CVMetalTexture?
            let wrap = CVMetalTextureCacheCreateTextureFromImage(
                nil,
                textureCache,
                pixelBuffer,
                nil,
                GradientRenderer.pixelFormat,
                CVPixelBufferGetWidth(pixelBuffer),
                CVPixelBufferGetHeight(pixelBuffer),
                0,
                &cvMetalTex
            )
            guard wrap == kCVReturnSuccess,
                  let cvm = cvMetalTex,
                  let texture = CVMetalTextureGetTexture(cvm)
            else {
                throw ExportError.textureWrapFailed
            }

            guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
                throw ExportError.commandBufferCreationFailed
            }
            let time = Float(frame) / Float(settings.fps)
            renderer.encode(into: commandBuffer,
                            target: texture,
                            time: time,
                            params: loopingParams,
                            loopFramesOverride: Int32(totalFrames))
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            let pt = CMTime(value: CMTimeValue(frame), timescale: timescale)
            if !adaptor.append(pixelBuffer, withPresentationTime: pt) {
                throw ExportError.appendFailed(writer.error)
            }

            let pct = Double(frame + 1) / Double(totalFrames)
            progress(pct)
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw ExportError.finalizeFailed(writer.error)
        }
    }

    private static func defaultBitrate(width: Int, height: Int, fps: Int32) -> Int {
        // Rough bits-per-pixel * area * fps heuristic (~0.1 bpp gives a clean gradient).
        let bpp = 0.12
        return Int(bpp * Double(width * height) * Double(fps))
    }
}
