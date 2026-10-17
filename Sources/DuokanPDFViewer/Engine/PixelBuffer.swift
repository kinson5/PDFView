import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public final class PixelBuffer: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]
    public let bytesPerRow: Int

    public init?(cgImage: CGImage) {
        self.width = cgImage.width
        self.height = cgImage.height
        self.bytesPerRow = width

        var rawData = [UInt8](repeating: 255, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.bytes = rawData
    }

    @inline(__always)
    public func pixel(atX x: Int, y: Int) -> UInt8 {
        guard x >= 0, x < width, y >= 0, y < height else { return 255 }
        return bytes[y * bytesPerRow + x]
    }

    /// True if pixel represents dark ink on light background
    @inline(__always)
    public func isInk(x: Int, y: Int, threshold: UInt8) -> Bool {
        return pixel(atX: x, y: y) < threshold
    }

    /// Otsu's thresholding calculation for binarization
    public func calculateOtsuThreshold() -> UInt8 {
        var histogram = [Int](repeating: 0, count: 256)
        let totalPixels = width * height
        guard totalPixels > 0 else { return 180 }

        for b in bytes {
            histogram[Int(b)] += 1
        }

        var sum: Double = 0
        for i in 0..<256 {
            sum += Double(i * histogram[i])
        }

        var sumB: Double = 0
        var wB: Int = 0
        var maxVariance: Double = 0
        var threshold: UInt8 = 180

        for t in 0..<256 {
            wB += histogram[t]
            if wB == 0 { continue }
            let wF = totalPixels - wB
            if wF == 0 { break }

            sumB += Double(t * histogram[t])
            let mB = sumB / Double(wB)
            let mF = (sum - sumB) / Double(wF)

            let variance = Double(wB) * Double(wF) * (mB - mF) * (mB - mF)
            if variance > maxVariance {
                maxVariance = variance
                threshold = UInt8(t)
            }
        }

        // Bias towards catching faint scanned text
        return max(140, min(threshold, 220))
    }

    /// Horizontal projection: counts foreground (ink) pixels for each row within rect
    public func horizontalProjection(in rect: CGRect, threshold: UInt8) -> [Int] {
        let minX = max(0, Int(rect.minX))
        let maxX = min(width - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY))
        let maxY = min(height - 1, Int(rect.maxY))

        guard minX <= maxX, minY <= maxY else { return [] }

        let rowCount = max(0, maxY - minY + 1)
        var counts = [Int](repeating: 0, count: rowCount)

        for y in minY...maxY {
            var inkCount = 0
            let rowOffset = y * bytesPerRow
            for x in minX...maxX {
                if bytes[rowOffset + x] < threshold {
                    inkCount += 1
                }
            }
            counts[y - minY] = inkCount
        }

        return counts
    }

    /// Vertical projection: counts foreground (ink) pixels for each column within rect
    public func verticalProjection(in rect: CGRect, threshold: UInt8) -> [Int] {
        let minX = max(0, Int(rect.minX))
        let maxX = min(width - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY))
        let maxY = min(height - 1, Int(rect.maxY))

        guard minX <= maxX, minY <= maxY else { return [] }

        let colCount = max(0, maxX - minX + 1)
        var counts = [Int](repeating: 0, count: colCount)

        for x in minX...maxX {
            var inkCount = 0
            for y in minY...maxY {
                if bytes[y * bytesPerRow + x] < threshold {
                    inkCount += 1
                }
            }
            counts[x - minX] = inkCount
        }

        return counts
    }
}
