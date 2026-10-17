import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct ImageEnhancer {
    /// Crops a CGImage to a sub-rectangle
    public static func crop(image: CGImage, to rect: CGRect) -> CGImage? {
        // Ensure rect is within image bounds
        let imgWidth = CGFloat(image.width)
        let imgHeight = CGFloat(image.height)

        let safeRect = CGRect(
            x: max(0, min(rect.minX, imgWidth - 1)),
            y: max(0, min(rect.minY, imgHeight - 1)),
            width: max(1, min(rect.width, imgWidth - rect.minX)),
            height: max(1, min(rect.height, imgHeight - rect.minY))
        )

        return image.cropping(to: safeRect)
    }

    /// Enhances contrast, darkens ink, thickens strokes, and sharpens edges for optimal scanned reading
    public static func enhance(
        image: CGImage,
        mode: BinarizationMode,
        threshold: UInt8,
        config: ReflowConfig = ReflowConfig(),
        isGraphic: Bool = false
    ) -> CGImage {
        switch mode {
        case .original:
            return image

        case .contrastEnhanced:
            // High-contrast, darkened, sharpened and anti-aliased image enhancement
            return applyFullClarityPipeline(
                image: image,
                config: config,
                isGraphic: isGraphic
            ) ?? image

        case .adaptive, .otsu:
            // Clean black-and-white binarization
            return binarize(image: image, threshold: threshold) ?? image
        }
    }

    /// Full Image Clarity & Ink Enhancement Pipeline:
    /// 1. Dynamic Contrast Stretching & Background Whitening
    /// 2. Non-linear Ink Darkening (Gamma Curve)
    /// 3. Morphological Dilation / Stroke Thickening (Repair fine breaks)
    /// 4. Edge Sharpening / Unsharp Masking
    public static func applyFullClarityPipeline(
        image: CGImage,
        config: ReflowConfig,
        isGraphic: Bool
    ) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        guard var rawData = extractGrayscalePixels(from: image) else {
            return nil
        }

        if isGraphic {
            // For photos / tables: apply gentle contrast without crushing gradients
            let bF: Double = 35.0
            let wF: Double = 230.0
            let range = max(1.0, wF - bF)
            for i in 0..<rawData.count {
                let v = Double(rawData[i])
                if v <= bF {
                    rawData[i] = 0
                } else if v >= wF {
                    rawData[i] = 255
                } else {
                    let scaled = ((v - bF) / range) * 255.0
                    rawData[i] = UInt8(clamping: Int(scaled.rounded()))
                }
            }
            return makeCGImage(from: rawData, width: width, height: height)
        }

        // --- 1. Dynamic Contrast & Whitening Thresholds ---
        let contrast = max(1.0, config.textContrast)
        // Background whitening: whitePoint moves down from 245 as contrast increases
        let whitePoint: Double
        if config.autoWhitenBackground {
            whitePoint = max(190.0, 245.0 - (contrast - 1.0) * 45.0)
        } else {
            whitePoint = 248.0
        }
        // Black point moves up from 45 as contrast increases
        let blackPoint = min(90.0, 45.0 + (contrast - 1.0) * 35.0)
        let range = max(1.0, whitePoint - blackPoint)

        // --- 2. Non-linear Ink Darkening Curve (Gamma LUT) ---
        let darkening = max(0.0, min(1.0, config.textDarkening))
        let gamma = 1.0 + darkening * 1.5 // Gamma > 1 pushes intermediate grays toward deep black

        var lut = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            let val = Double(i)
            if val <= blackPoint {
                lut[i] = 0
            } else if val >= whitePoint {
                lut[i] = 255
            } else {
                let normalized = (val - blackPoint) / range // 0.0 ... 1.0
                let darkened = pow(normalized, gamma)
                lut[i] = UInt8(clamping: Int((darkened * 255.0).rounded()))
            }
        }

        // Apply LUT to raw grayscale buffer
        for i in 0..<rawData.count {
            rawData[i] = lut[Int(rawData[i])]
        }

        // --- 3. Morphological Dilation / Stroke Thickening (Repair thin strokes) ---
        if config.strokeThickening > 0 && width > 2 && height > 2 {
            var thickened = rawData
            for y in 1..<(height - 1) {
                let row = y * width
                let rowAbove = (y - 1) * width
                let rowBelow = (y + 1) * width
                for x in 1..<(width - 1) {
                    let c = rawData[row + x]
                    let up = rawData[rowAbove + x]
                    let down = rawData[rowBelow + x]
                    let left = rawData[row + x - 1]
                    let right = rawData[row + x + 1]
                    let minNeighbor = min(c, min(up, min(down, min(left, right))))
                    if minNeighbor < c {
                        // Smoothly blend 60% toward the darker neighbor to reinforce broken strokes
                        let blended = Double(c) * 0.4 + Double(minNeighbor) * 0.6
                        thickened[row + x] = UInt8(blended.rounded())
                    }
                }
            }
            rawData = thickened
        }

        // --- 4. Edge Sharpening / Unsharp Masking ---
        if config.textSharpening > 0.05 && width > 2 && height > 2 {
            var sharpened = rawData
            let strength = min(1.5, config.textSharpening)
            for y in 1..<(height - 1) {
                let row = y * width
                let rowAbove = (y - 1) * width
                let rowBelow = (y + 1) * width
                for x in 1..<(width - 1) {
                    let c = Double(rawData[row + x])
                    let localAvg = (
                        Double(rawData[rowAbove + x]) +
                        Double(rawData[rowBelow + x]) +
                        Double(rawData[row + x - 1]) +
                        Double(rawData[row + x + 1]) +
                        c
                    ) / 5.0
                    let diff = c - localAvg
                    let res = c + strength * diff
                    sharpened[row + x] = UInt8(clamping: Int(res.rounded()))
                }
            }
            rawData = sharpened
        }

        return makeCGImage(from: rawData, width: width, height: height)
    }

    private static func extractGrayscalePixels(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

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
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return rawData
    }

    private static func makeCGImage(from pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        let cfData = CFDataCreate(kCFAllocatorDefault, pixels, pixels.count)
        guard let data = cfData, let provider = CGDataProvider(data: data) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func binarize(image: CGImage, threshold: UInt8) -> CGImage? {
        guard var rawData = extractGrayscalePixels(from: image) else { return nil }
        for i in 0..<rawData.count {
            rawData[i] = rawData[i] < threshold ? 0 : 255
        }
        return makeCGImage(from: rawData, width: image.width, height: image.height)
    }
}
