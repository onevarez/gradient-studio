import Foundation
import AppKit
import CoreGraphics
import simd

enum ImagePaletteError: LocalizedError {
    case cannotReadImage
    case noUsablePixels

    var errorDescription: String? {
        switch self {
        case .cannotReadImage: return "Could not decode the selected image."
        case .noUsablePixels:  return "Image had no usable pixels (all transparent?)."
        }
    }
}

enum ImagePaletteExtractor {
    /// Pull `k` representative colors from the image at `url` using k-means in OKLab.
    /// OKLab distance matches perceptual difference, so clusters group visually-similar
    /// colors rather than RGB-close ones.
    static func extract(from url: URL, k: Int) throws -> [SIMD4<Float>] {
        guard let image = NSImage(contentsOf: url) else {
            throw ImagePaletteError.cannotReadImage
        }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw ImagePaletteError.cannotReadImage
        }
        let samples = sampleLab(cg, maxSide: 128)
        guard samples.count >= k else { throw ImagePaletteError.noUsablePixels }
        let centers = kmeans(samples: samples, k: k, iterations: 10)
        return centers.map { lab in
            SIMD4(ColorHarmony.oklabToSRGB(L: lab.x, a: lab.y, b: lab.z), 1.0)
        }
    }

    // MARK: - sampling

    /// Downsample via a tiny CGContext (cap at `maxSide` on the long edge) and convert
    /// each opaque pixel to OKLab. 128² ≈ 16k samples — plenty for stable clustering and
    /// keeps k-means under ~50ms for k=16 / 10 iters.
    private static func sampleLab(_ cg: CGImage, maxSide: Int) -> [SIMD3<Float>] {
        let w = cg.width, h = cg.height
        let scale = Float(maxSide) / Float(max(w, h))
        let dstW = max(1, Int(Float(w) * scale))
        let dstH = max(1, Int(Float(h) * scale))

        let bytesPerRow = dstW * 4
        var data = [UInt8](repeating: 0, count: dstH * bytesPerRow)

        var samples: [SIMD3<Float>] = []
        data.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            let cs = CGColorSpaceCreateDeviceRGB()
            let info = CGImageAlphaInfo.premultipliedLast.rawValue
                     | CGBitmapInfo.byteOrder32Big.rawValue
            guard let ctx = CGContext(
                data: base,
                width: dstW,
                height: dstH,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: cs,
                bitmapInfo: info
            ) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))

            let p = base.assumingMemoryBound(to: UInt8.self)
            let total = dstW * dstH
            samples.reserveCapacity(total)
            for i in 0..<total {
                let o = i * 4
                let a = Float(p[o+3]) / 255
                if a < 0.5 { continue }
                let r = Float(p[o+0]) / 255
                let g = Float(p[o+1]) / 255
                let b = Float(p[o+2]) / 255
                samples.append(srgbToOKLab(SIMD3(r, g, b)))
            }
        }
        return samples
    }

    // MARK: - color conversion

    private static func srgbDecode(_ x: Float) -> Float {
        let c = max(0, min(1, x))
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    private static func srgbToOKLab(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let r = srgbDecode(rgb.x), g = srgbDecode(rgb.y), b = srgbDecode(rgb.z)
        let l = 0.4122214708*r + 0.5363325363*g + 0.0514459929*b
        let m = 0.2119034982*r + 0.6806995451*g + 0.1073969566*b
        let s = 0.0883024619*r + 0.2817188376*g + 0.6299787005*b
        let l_ = cbrtf(l), m_ = cbrtf(m), s_ = cbrtf(s)
        return SIMD3(
            0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_,
            1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_,
            0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_
        )
    }

    // MARK: - k-means

    /// Lloyd's algorithm in OKLab. Initialized by picking `k` distinct random samples.
    /// Fixed iteration count is good enough for palette extraction — we don't need
    /// true convergence, just visually-distinct clusters.
    private static func kmeans(samples: [SIMD3<Float>], k: Int, iterations: Int) -> [SIMD3<Float>] {
        var centers: [SIMD3<Float>] = []
        var picked = Set<Int>()
        while centers.count < k {
            let idx = Int.random(in: 0..<samples.count)
            if picked.insert(idx).inserted {
                centers.append(samples[idx])
            }
        }

        var assignments = [Int](repeating: 0, count: samples.count)
        for _ in 0..<iterations {
            // assign each sample to the nearest center
            for i in 0..<samples.count {
                let s = samples[i]
                var best = 0
                var bestD = Float.infinity
                for ci in 0..<k {
                    let d = simd_distance_squared(s, centers[ci])
                    if d < bestD { bestD = d; best = ci }
                }
                assignments[i] = best
            }
            // recompute centers as mean of assigned samples
            var sums   = [SIMD3<Float>](repeating: .zero, count: k)
            var counts = [Int](repeating: 0, count: k)
            for i in 0..<samples.count {
                let a = assignments[i]
                sums[a] += samples[i]
                counts[a] += 1
            }
            for ci in 0..<k where counts[ci] > 0 {
                centers[ci] = sums[ci] / Float(counts[ci])
            }
        }

        // Sort by lightness so the mesh grid reads dark→light from bottom-left, which
        // tends to look more natural.
        return centers.sorted { $0.x < $1.x }
    }
}
