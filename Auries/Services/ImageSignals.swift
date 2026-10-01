import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Extracts the two Layer-1 signals from a photo (§10):
///   - dominant color: the object's main color, ignoring the background
///   - shape: bounding-box aspect ratio + a 0-1 roundness estimate
///
/// Method: downsample to a small grid, estimate the background color from the
/// border pixels, mask "foreground" as pixels far from that background, then
/// take the most common (saturation-weighted) quantized foreground color and
/// measure the mask's bounding box and circularity. Cheap, deterministic, and
/// good enough — a bad photo just makes a plainer creature (§5).
enum ImageSignals {

    struct Result {
        let dominantColor: Rgb
        let shape: ShapeSignal
    }

    static let fallback = Result(dominantColor: Rgb(150, 150, 150),
                                 shape: ShapeSignal(aspectRatio: 1, roundness: 0.6))

    #if canImport(UIKit)
    /// Async wrapper for the app: runs the pixel crunch off the main actor.
    nonisolated static func extract(from image: UIImage) async -> Result {
        extract(from: image.cgImage)
    }
    #endif

    /// Core, CoreGraphics-only (also compiled by the macOS verification script).
    nonisolated static func extract(from cgImage: CGImage?) -> Result {
        guard let cgImage else { return fallback }

        // 1. Downsample to a 48x48 RGBA grid.
        let n = 48
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8,
                                  bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return fallback }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let raw = ctx.data else { return fallback }
        let px = raw.bindMemory(to: UInt8.self, capacity: n * n * 4)
        func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * n + x) * 4
            return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
        }

        // 2. Background estimate: average of the two-pixel border ring.
        var sum = (r: 0, g: 0, b: 0), count = 0
        for y in 0..<n {
            for x in 0..<n where x < 2 || x >= n - 2 || y < 2 || y >= n - 2 {
                let c = rgb(x, y)
                sum = (sum.r + c.r, sum.g + c.g, sum.b + c.b)
                count += 1
            }
        }
        let bg = (r: sum.r / count, g: sum.g / count, b: sum.b / count)

        // 3. Foreground mask: pixels far from the background color.
        var mask = [Bool](repeating: false, count: n * n)
        var minX = n, maxX = -1, minY = n, maxY = -1, area = 0
        for y in 0..<n {
            for x in 0..<n {
                let c = rgb(x, y)
                let dist = abs(c.r - bg.r) + abs(c.g - bg.g) + abs(c.b - bg.b)
                guard dist > 90 else { continue }
                mask[y * n + x] = true
                area += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }

        // 4. Dominant color: most common quantized color among foreground
        //    pixels (whole image if the mask is tiny), weighted toward
        //    saturated buckets so a colorful object beats grey shadow.
        //
        // 2026-09-26: this fallback used to fire below 5% of the grid
        // (115 px), which is a subject filling a quarter of the frame —
        // ordinary framing for a phone photo of an object on a table. The
        // whole image then decided the colour, so a red apple or a green
        // can on a wooden table produced a TABLE-coloured creature. The
        // fallback exists only to stop a degenerate, near-empty mask from
        // picking a speck, so it now fires an order of magnitude later:
        // 24 px is roughly a 5x5 patch, below which the mask really is
        // noise. Measured on a cut-out subject over a wooden ground, the
        // recovered colour goes from the table's (148,108,70) back to the
        // subject's (176,43,41) at a quarter-frame subject.
        let useAll = area < 24
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for y in 0..<n {
            for x in 0..<n where useAll || mask[y * n + x] {
                let c = rgb(x, y)
                let key = (c.r >> 5) << 10 | (c.g >> 5) << 5 | (c.b >> 5)
                var e = buckets[key] ?? (0, 0, 0, 0)
                e = (e.count + 1, e.r + c.r, e.g + c.g, e.b + c.b)
                buckets[key] = e
            }
        }
        var best = (weight: 0.0, color: fallback.dominantColor)
        for e in buckets.values {
            let r = e.r / e.count, g = e.g / e.count, b = e.b / e.count
            let mx = max(r, g, b), mn = min(r, g, b)
            let saturation = mx == 0 ? 0 : Double(mx - mn) / Double(mx)
            let weight = Double(e.count) * (0.35 + saturation)
            if weight > best.weight { best = (weight, Rgb(r, g, b)) }
        }

        // 5. Shape: bbox aspect + roundness. Roundness blends circularity
        //    (4πA/P², penalizes jagged outlines) with how well the mask fills
        //    its bounding-box ellipse (penalizes squares), so circle ≈ 1,
        //    square ≈ 0.65, crescent/jagged ≈ 0.2.
        guard area > 8, maxX >= minX, maxY >= minY else {
            return Result(dominantColor: best.color, shape: fallback.shape)
        }
        let w = maxX - minX + 1, h = maxY - minY + 1
        var perimeter = 0
        for y in 0..<n {
            for x in 0..<n where mask[y * n + x] {
                let onEdge = x == 0 || x == n - 1 || y == 0 || y == n - 1
                if onEdge || !mask[y * n + x - 1] || !mask[y * n + x + 1]
                    || !mask[(y - 1) * n + x] || !mask[(y + 1) * n + x] {
                    perimeter += 1
                }
            }
        }
        let circularity = min(4.0 * .pi * Double(area) / Double(perimeter * perimeter), 1)
        let ellipseArea = .pi / 4 * Double(w) * Double(h)
        let ellipseFill = min(Double(area) / ellipseArea, ellipseArea / Double(area))
        let roundness = Float(max(min(circularity * ellipseFill, 1), 0))

        return Result(dominantColor: best.color,
                      shape: ShapeSignal(aspectRatio: Float(w) / Float(h), roundness: roundness))
    }
}
