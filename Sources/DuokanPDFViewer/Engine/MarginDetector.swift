import Foundation
import CoreGraphics

public struct MarginDetector {
    public static func detectContentBounds(
        pixelBuffer: PixelBuffer,
        threshold: UInt8,
        noiseToleranceRatio: Double = 0.002
    ) -> CGRect {
        let width = pixelBuffer.width
        let height = pixelBuffer.height
        guard width > 20, height > 20 else {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)

        // 1. Check whether outer perimeter is a dark desk/background (e.g. photos of books/docs on desks)
        var outerBorderDarkCount = 0
        var outerBorderSampleTotal = 0
        let step = max(2, min(width, height) / 80)

        for x in stride(from: 0, to: width, by: step) {
            outerBorderSampleTotal += 2
            if pixelBuffer.pixel(atX: x, y: 2) < 100 { outerBorderDarkCount += 1 }
            if pixelBuffer.pixel(atX: x, y: height - 3) < 100 { outerBorderDarkCount += 1 }
        }
        for y in stride(from: 0, to: height, by: step) {
            outerBorderSampleTotal += 2
            if pixelBuffer.pixel(atX: 2, y: y) < 100 { outerBorderDarkCount += 1 }
            if pixelBuffer.pixel(atX: width - 3, y: y) < 100 { outerBorderDarkCount += 1 }
        }

        let isDarkDeskSurrounding = outerBorderSampleTotal > 0 && (Double(outerBorderDarkCount) / Double(outerBorderSampleTotal) >= 0.40)

        let searchRect: CGRect
        if isDarkDeskSurrounding {
            // Find transition boundary from dark desk (< 100) to paper (> 125)
            let darkThreshold: UInt8 = 110
            var pTop = 0
            while pTop < height / 3 {
                var darkRow = 0
                var totalRow = 0
                for x in stride(from: 0, to: width, by: step) {
                    totalRow += 1
                    if pixelBuffer.pixel(atX: x, y: pTop) < darkThreshold { darkRow += 1 }
                }
                if Double(darkRow) / Double(max(1, totalRow)) >= 0.35 {
                    pTop += 1
                } else {
                    break
                }
            }

            var pBottom = height - 1
            while pBottom > 2 * height / 3 {
                var darkRow = 0
                var totalRow = 0
                for x in stride(from: 0, to: width, by: step) {
                    totalRow += 1
                    if pixelBuffer.pixel(atX: x, y: pBottom) < darkThreshold { darkRow += 1 }
                }
                if Double(darkRow) / Double(max(1, totalRow)) >= 0.35 {
                    pBottom -= 1
                } else {
                    break
                }
            }

            var pLeft = 0
            while pLeft < width / 3 {
                var darkCol = 0
                var totalCol = 0
                for y in stride(from: pTop, to: pBottom, by: step) {
                    totalCol += 1
                    if pixelBuffer.pixel(atX: pLeft, y: y) < darkThreshold { darkCol += 1 }
                }
                if Double(darkCol) / Double(max(1, totalCol)) >= 0.35 {
                    pLeft += 1
                } else {
                    break
                }
            }

            var pRight = width - 1
            while pRight > 2 * width / 3 {
                var darkCol = 0
                var totalCol = 0
                for y in stride(from: pTop, to: pBottom, by: step) {
                    totalCol += 1
                    if pixelBuffer.pixel(atX: pRight, y: y) < darkThreshold { darkCol += 1 }
                }
                if Double(darkCol) / Double(max(1, totalCol)) >= 0.35 {
                    pRight -= 1
                } else {
                    break
                }
            }

            if pBottom > pTop + 50 && pRight > pLeft + 50 {
                searchRect = CGRect(x: pLeft, y: pTop, width: pRight - pLeft + 1, height: pBottom - pTop + 1)
            } else {
                searchRect = fullRect
            }
        } else {
            searchRect = fullRect
        }

        // Inside searchRect, compute projections to detect content ink bounds
        let horizProj = pixelBuffer.horizontalProjection(in: searchRect, threshold: threshold)
        let vertProj = pixelBuffer.verticalProjection(in: searchRect, threshold: threshold)

        let sWidth = Int(searchRect.width)
        let sHeight = Int(searchRect.height)
        let minRowInk = max(2, Int(Double(sWidth) * noiseToleranceRatio))
        let minColInk = max(2, Int(Double(sHeight) * noiseToleranceRatio))

        // Find top bound
        var top = 0
        for y in 0..<sHeight {
            if horizProj[y] >= minRowInk {
                top = y
                break
            }
        }

        // Find bottom bound
        var bottom = sHeight - 1
        for y in stride(from: sHeight - 1, through: 0, by: -1) {
            if horizProj[y] >= minRowInk {
                bottom = y
                break
            }
        }

        // Find left bound
        var left = 0
        for x in 0..<sWidth {
            if vertProj[x] >= minColInk {
                left = x
                break
            }
        }

        // Find right bound
        var right = sWidth - 1
        for x in stride(from: sWidth - 1, through: 0, by: -1) {
            if vertProj[x] >= minColInk {
                right = x
                break
            }
        }

        guard bottom > top, right > left else {
            return searchRect
        }

        // Add padding
        let padding = 6
        let finalLeft = max(0, Int(searchRect.minX) + left - padding)
        let finalTop = max(0, Int(searchRect.minY) + top - padding)
        let finalRight = min(width, Int(searchRect.minX) + right + padding)
        let finalBottom = min(height, Int(searchRect.minY) + bottom + padding)

        return CGRect(
            x: finalLeft,
            y: finalTop,
            width: max(10, finalRight - finalLeft),
            height: max(10, finalBottom - finalTop)
        )
    }
}
