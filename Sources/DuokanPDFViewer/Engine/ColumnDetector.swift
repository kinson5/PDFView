import Foundation
import CoreGraphics

public struct ColumnDetector {
    /// Detects columns in the content bounds. Returns array of column rects in reading order.
    public static func detectColumns(
        pixelBuffer: PixelBuffer,
        contentBounds: CGRect,
        threshold: UInt8,
        minGapRatio: CGFloat = 0.014
    ) -> [CGRect] {
        let width = contentBounds.width
        let height = contentBounds.height

        // If content is too narrow or short, treat as single column
        if width < 200 || height < 100 {
            return [contentBounds]
        }

        let vertProj = pixelBuffer.verticalProjection(in: contentBounds, threshold: threshold)
        let minGapPixels = max(8, Int(width * minGapRatio))

        // Calculate average ink to establish an adaptive valley threshold
        // Text columns have high cumulative ink; gutters (even with headers/dividers) have much lower ink
        let avgInk = vertProj.isEmpty ? 0.0 : (Double(vertProj.reduce(0, +)) / Double(vertProj.count))
        let noiseInkLimit = max(4, min(Int(Double(height) * 0.08), Int(avgInk * 0.28)))

        // Identify candidate gutter intervals
        var gutters: [(start: Int, end: Int, width: Int)] = []
        var inGutter = false
        var gutterStart = 0

        // Search gutters only within the central 15% to 85% width (avoid page margins)
        let marginX = Int(width * 0.15)
        let searchStart = marginX
        let searchEnd = Int(width) - marginX

        for x in searchStart..<searchEnd {
            let ink = vertProj[x]
            if ink <= noiseInkLimit {
                if !inGutter {
                    inGutter = true
                    gutterStart = x
                }
            } else {
                if inGutter {
                    inGutter = false
                    let gWidth = x - gutterStart
                    if gWidth >= minGapPixels {
                        gutters.append((start: gutterStart, end: x, width: gWidth))
                    }
                }
            }
        }

        if inGutter {
            let gWidth = searchEnd - gutterStart
            if gWidth >= minGapPixels {
                gutters.append((start: gutterStart, end: searchEnd, width: gWidth))
            }
        }

        // If no significant gutter found, return single column
        if gutters.isEmpty {
            return [contentBounds]
        }

        // Filter gutters: for standard 2-column or 3-column layout, select the most prominent gutter(s)
        // Sort gutters by width descending and take up to 2
        let sortedGutters = gutters.sorted { $0.width > $1.width }
        // We ensure minimum column width on either side
        let minColWidth = Int(width * 0.20)

        var selectedCutPoints: [Int] = []
        for g in sortedGutters {
            let center = (g.start + g.end) / 2
            if center >= minColWidth && (Int(width) - center) >= minColWidth {
                // Ensure not too close to another cut point
                let tooClose = selectedCutPoints.contains { abs($0 - center) < minColWidth }
                if !tooClose {
                    selectedCutPoints.append(center)
                }
            }
            if selectedCutPoints.count >= 2 { break }
        }

        if selectedCutPoints.isEmpty {
            return [contentBounds]
        }

        selectedCutPoints.sort()

        // Build column rects
        var columns: [CGRect] = []
        var prevX = 0
        for cut in selectedCutPoints {
            let colWidth = cut - prevX
            if colWidth > 10 {
                columns.append(CGRect(
                    x: contentBounds.minX + CGFloat(prevX),
                    y: contentBounds.minY,
                    width: CGFloat(colWidth),
                    height: contentBounds.height
                ))
            }
            prevX = cut
        }

        // Last column
        let remainingWidth = Int(width) - prevX
        if remainingWidth > 10 {
            columns.append(CGRect(
                x: contentBounds.minX + CGFloat(prevX),
                y: contentBounds.minY,
                width: CGFloat(remainingWidth),
                height: contentBounds.height
            ))
        }

        return columns.isEmpty ? [contentBounds] : columns
    }
}
