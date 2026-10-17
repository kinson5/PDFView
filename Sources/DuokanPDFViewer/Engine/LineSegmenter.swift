import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct LineSegmenter {
    public static func segmentLines(
        pixelBuffer: PixelBuffer,
        originalImage: CGImage,
        columnRect: CGRect,
        threshold: UInt8,
        visualThreshold: UInt8? = nil,
        pageIndex: Int,
        columnIndex: Int,
        config: ReflowConfig,
        visionAnalysis: VisionPageAnalysis? = nil
    ) -> [PageSlice] {
        // 1. Initial quick estimate of line height
        let estimatedLineHeight = estimateMedianLineHeight(
            pixelBuffer: pixelBuffer,
            columnRect: columnRect,
            threshold: threshold,
            minLineHeight: config.minLineHeight
        )

        // 2. Intelligent Visual Region Detection (Tables, Standalone Figures, Side-by-Side Graphic Blocks, Pure Text)
        let visualRegions = VisualBlockDetector.detectVisualRegions(
            pixelBuffer: pixelBuffer,
            columnRect: columnRect,
            threshold: threshold,
            expectedLineHeight: estimatedLineHeight,
            visionAnalysis: visionAnalysis
        )

        var allSlices: [PageSlice] = []

        for region in visualRegions {
            switch region.type {
            case .table:
                // Preserve Table 100% intact as a single block (never chopped into fragments)
                if let tableSlice = makeGraphicSlice(
                    originalImage: originalImage,
                    rect: region.rect,
                    columnWidth: columnRect.width,
                    pageIndex: pageIndex,
                    columnIndex: columnIndex,
                    sliceIndex: allSlices.count,
                    isFigure: true,
                    isTable: true,
                    isSideBySide: false,
                    config: config,
                    threshold: threshold,
                    visualThreshold: visualThreshold
                ) {
                    allSlices.append(tableSlice)
                }

            case .standaloneFigure:
                // Preserve Standalone Figure/Photo/Diagram 100% intact as a single block
                if let figureSlice = makeGraphicSlice(
                    originalImage: originalImage,
                    rect: region.rect,
                    columnWidth: columnRect.width,
                    pageIndex: pageIndex,
                    columnIndex: columnIndex,
                    sliceIndex: allSlices.count,
                    isFigure: true,
                    isTable: false,
                    isSideBySide: false,
                    config: config,
                    threshold: threshold,
                    visualThreshold: visualThreshold
                ) {
                    allSlices.append(figureSlice)
                }

            case .sideBySide(let figureRect, let textRect, let figureOnRight):
                // Intelligent handling when text and image/chart are in the same row!
                // 1) The figure is preserved as an intact graphic slice
                let figSlice = makeGraphicSlice(
                    originalImage: originalImage,
                    rect: figureRect,
                    columnWidth: columnRect.width,
                    pageIndex: pageIndex,
                    columnIndex: columnIndex,
                    sliceIndex: allSlices.count,
                    isFigure: true,
                    isTable: false,
                    isSideBySide: true,
                    config: config,
                    threshold: threshold,
                    visualThreshold: visualThreshold
                )

                // 2) The adjacent text region is sliced into regular text lines
                let textSlices = segmentTextLinesInRegion(
                    pixelBuffer: pixelBuffer,
                    originalImage: originalImage,
                    regionRect: textRect,
                    columnWidth: columnRect.width,
                    threshold: threshold,
                    visualThreshold: visualThreshold,
                    pageIndex: pageIndex,
                    columnIndex: columnIndex,
                    startIndex: allSlices.count + (figSlice != nil ? 1 : 0),
                    isSideBySide: true,
                    config: config,
                    expectedLineHeight: estimatedLineHeight,
                    visionAnalysis: visionAnalysis
                )

                if figureOnRight {
                    // Left Text, Right Figure
                    allSlices.append(contentsOf: textSlices)
                    if let fig = figSlice { allSlices.append(fig) }
                } else {
                    // Left Figure, Right Text
                    if let fig = figSlice { allSlices.append(fig) }
                    allSlices.append(contentsOf: textSlices)
                }

            case .pureText:
                // Pure text region: segment into lines with valley detection
                let textSlices = segmentTextLinesInRegion(
                    pixelBuffer: pixelBuffer,
                    originalImage: originalImage,
                    regionRect: region.rect,
                    columnWidth: columnRect.width,
                    threshold: threshold,
                    visualThreshold: visualThreshold,
                    pageIndex: pageIndex,
                    columnIndex: columnIndex,
                    startIndex: allSlices.count,
                    isSideBySide: false,
                    config: config,
                    expectedLineHeight: estimatedLineHeight,
                    visionAnalysis: visionAnalysis
                )
                allSlices.append(contentsOf: textSlices)
            }
        }

        return allSlices
    }

    private static func makeGraphicSlice(
        originalImage: CGImage,
        rect: CGRect,
        columnWidth: CGFloat,
        pageIndex: Int,
        columnIndex: Int,
        sliceIndex: Int,
        isFigure: Bool,
        isTable: Bool,
        isSideBySide: Bool,
        config: ReflowConfig,
        threshold: UInt8,
        visualThreshold: UInt8?
    ) -> PageSlice? {
        guard let cropped = ImageEnhancer.crop(image: originalImage, to: rect) else {
            return nil
        }

        let enhanced = ImageEnhancer.enhance(
            image: cropped,
            mode: config.binarizationMode == .contrastEnhanced ? .original : config.binarizationMode,
            threshold: visualThreshold ?? threshold,
            config: config,
            isGraphic: isFigure || isTable
        )

        let nsImage = NSImage(cgImage: enhanced, size: NSSize(width: rect.width, height: rect.height))

        return PageSlice(
            pageIndex: pageIndex,
            columnIndex: columnIndex,
            sliceIndex: sliceIndex,
            originalRect: rect,
            columnWidth: columnWidth,
            image: nsImage,
            isFigure: isFigure,
            isTable: isTable,
            isSideBySide: isSideBySide,
            words: []
        )
    }

    private static func segmentTextLinesInRegion(
        pixelBuffer: PixelBuffer,
        originalImage: CGImage,
        regionRect: CGRect,
        columnWidth: CGFloat,
        threshold: UInt8,
        visualThreshold: UInt8?,
        pageIndex: Int,
        columnIndex: Int,
        startIndex: Int,
        isSideBySide: Bool,
        config: ReflowConfig,
        expectedLineHeight: Int,
        visionAnalysis: VisionPageAnalysis? = nil
    ) -> [PageSlice] {
        let rawProj = pixelBuffer.horizontalProjection(in: regionRect, threshold: threshold)
        let rowCount = rawProj.count
        guard rowCount > 10 else { return [] }

        // Moving average smoothing (radius = 2)
        var smoothed = [Double](repeating: 0, count: rowCount)
        for y in 0..<rowCount {
            var sum = 0.0
            var count = 0
            for dy in -2...2 {
                let ny = y + dy
                if ny >= 0 && ny < rowCount {
                    sum += Double(rawProj[ny])
                    count += 1
                }
            }
            smoothed[y] = sum / Double(max(1, count))
        }

        let noiseFloor = max(3.0, Double(regionRect.width) * 0.006)

        // Find initial intervals
        var intervals: [(startY: Int, endY: Int)] = []
        var inBlock = false
        var blockStart = 0

        for y in 0..<rowCount {
            if smoothed[y] > noiseFloor {
                if !inBlock {
                    inBlock = true
                    blockStart = y
                }
            } else {
                if inBlock {
                    inBlock = false
                    intervals.append((startY: blockStart, endY: y - 1))
                }
            }
        }
        if inBlock {
            intervals.append((startY: blockStart, endY: rowCount - 1))
        }

        // Split multi-line blocks with valley detection (unless visionAnalysis confirms it is a single tall title line)
        var prelimIntervals: [(startY: Int, endY: Int)] = []
        for interval in intervals {
            let h = interval.endY - interval.startY + 1
            if h < config.minLineHeight { continue }

            if Double(h) > Double(expectedLineHeight) * 1.45 {
                var isSingleTallTitleLine = false
                if let vision = visionAnalysis {
                    let absTop = regionRect.minY + CGFloat(interval.startY)
                    let absBottom = regionRect.minY + CGFloat(interval.endY)
                    let overlapping = vision.lines.filter { line in
                        let hOverlap = min(regionRect.maxX, line.rect.maxX) - max(regionRect.minX, line.rect.minX)
                        let vOverlap = min(absBottom, line.rect.maxY) - max(absTop, line.rect.minY)
                        return hOverlap >= max(8.0, min(regionRect.width, line.rect.width) * 0.25)
                            && vOverlap >= max(6.0, min(CGFloat(h), line.rect.height) * 0.35)
                    }
                    if !overlapping.isEmpty {
                        let maxLineH = overlapping.map { $0.rect.height }.max() ?? 0
                        // Check how many vertically distinct rows exist in overlapping
                        let sortedByY = overlapping.sorted { $0.rect.midY < $1.rect.midY }
                        var rowCountInInterval = 0
                        var lastMidY: CGFloat = -10000
                        for l in sortedByY {
                            if l.rect.midY - lastMidY >= max(10.0, l.rect.height * 0.50) {
                                rowCountInInterval += 1
                                lastMidY = l.rect.midY
                            }
                        }
                        if rowCountInInterval == 1 && maxLineH >= CGFloat(h) * 0.58 {
                            isSingleTallTitleLine = true
                        }
                    }
                }

                if isSingleTallTitleLine {
                    prelimIntervals.append(interval)
                } else {
                    let subSlices = splitMultiLineBlock(
                        interval: interval,
                        smoothed: smoothed,
                        expectedLineHeight: expectedLineHeight,
                        noiseFloor: noiseFloor
                    )
                    prelimIntervals.append(contentsOf: subSlices)
                }
            } else {
                prelimIntervals.append(interval)
            }
        }

        // Refine any remaining tall intervals using Vision / Native PDF text line vertical boundaries
        var splitIntervals: [(startY: Int, endY: Int)] = []
        if let vision = visionAnalysis {
            for interval in prelimIntervals {
                let h = interval.endY - interval.startY + 1
                if Double(h) > Double(expectedLineHeight) * 1.55 {
                    let absTop = regionRect.minY + CGFloat(interval.startY)
                    let absBottom = regionRect.minY + CGFloat(interval.endY)
                    let candidateLines = vision.lines.filter { line in
                        let hOverlap = min(regionRect.maxX, line.rect.maxX) - max(regionRect.minX, line.rect.minX)
                        return hOverlap >= min(12.0, line.rect.width * 0.35)
                            && line.rect.midY >= absTop && line.rect.midY <= absBottom
                            && line.rect.height <= CGFloat(expectedLineHeight) * 1.65
                    }.sorted { $0.rect.midY < $1.rect.midY }

                    // Deduplicate lines on the same horizontal row
                    var distinctRows: [RecognizedTextLine] = []
                    for line in candidateLines {
                        if let last = distinctRows.last {
                            if line.rect.midY - last.rect.midY >= max(10.0, min(last.rect.height, line.rect.height) * 0.55) {
                                distinctRows.append(line)
                            }
                        } else {
                            distinctRows.append(line)
                        }
                    }

                    if distinctRows.count >= 2 {
                        var curStart = interval.startY
                        for rIdx in 0..<(distinctRows.count - 1) {
                            let midAbsY = (distinctRows[rIdx].rect.maxY + distinctRows[rIdx + 1].rect.minY) * 0.5
                            let rawSplitY = Int(round(midAbsY - regionRect.minY))
                            let splitY = max(curStart + config.minLineHeight, min(interval.endY - config.minLineHeight, rawSplitY))
                            if splitY > curStart {
                                splitIntervals.append((startY: curStart, endY: splitY))
                                curStart = splitY + 1
                            }
                        }
                        if interval.endY >= curStart {
                            splitIntervals.append((startY: curStart, endY: interval.endY))
                        }
                        continue
                    }
                }
                splitIntervals.append(interval)
            }
        } else {
            splitIntervals = prelimIntervals
        }

        var slices: [PageSlice] = []

        for (idx, interval) in splitIntervals.enumerated() {
            // Trim leading and trailing low-ink valley rows so each line slice tightly wraps its actual glyph ink
            var tightStart = interval.startY
            var tightEnd = interval.endY
            let inkFloor = max(2, Int(noiseFloor))
            while tightStart < tightEnd && rawProj[tightStart] <= inkFloor {
                tightStart += 1
            }
            while tightEnd > tightStart && rawProj[tightEnd] <= inkFloor {
                tightEnd -= 1
            }

            let rawY = Int(regionRect.minY) + tightStart
            let rawHeight = tightEnd - tightStart + 1
            if rawHeight < config.minLineHeight { continue }

            // Generous vertical breathing padding so top dots/accents and bottom baseline strokes
            // (e.g. bottom lines of "园", "司", "泉", "裳", "土", descenders) are never shaved off!
            let vPad = max(4, Int(Double(rawHeight) * 0.08))
            let paddedY = max(Int(regionRect.minY), rawY - vPad)
            let paddedBottom = min(Int(regionRect.maxY), rawY + rawHeight + vPad)
            let finalHeight = paddedBottom - paddedY
            guard finalHeight > 0 else { continue }

            let sliceSubRect = CGRect(
                x: regionRect.minX,
                y: CGFloat(paddedY),
                width: regionRect.width,
                height: CGFloat(finalHeight)
            )

            // Right-edge tightening
            let sliceVertProj = pixelBuffer.verticalProjection(in: sliceSubRect, threshold: threshold)
            var sliceRight = sliceVertProj.count - 1
            for x in stride(from: sliceVertProj.count - 1, through: 0, by: -1) {
                if sliceVertProj[x] > 1 {
                    sliceRight = x
                    break
                }
            }

            let tightenedWidth: CGFloat
            if sliceRight > 10 {
                let rightWithPadding = min(regionRect.width, CGFloat(sliceRight) + 12.0)
                tightenedWidth = max(30.0, rightWithPadding)
            } else {
                tightenedWidth = regionRect.width
            }

            let sliceRect = CGRect(
                x: regionRect.minX,
                y: CGFloat(paddedY),
                width: tightenedWidth,
                height: CGFloat(finalHeight)
            )

            guard let croppedCG = ImageEnhancer.crop(image: originalImage, to: sliceRect) else {
                continue
            }

            let enhancedCG = ImageEnhancer.enhance(
                image: croppedCG,
                mode: config.binarizationMode,
                threshold: visualThreshold ?? threshold,
                config: config,
                isGraphic: false
            )

            let nsImage = NSImage(
                cgImage: enhancedCG,
                size: NSSize(width: sliceRect.width, height: sliceRect.height)
            )

            let words = WordSegmenter.segmentWords(
                pixelBuffer: pixelBuffer,
                originalImage: originalImage,
                sliceRect: sliceRect,
                threshold: threshold,
                visualThreshold: visualThreshold,
                config: config
            )

            // Associate Apple Vision OCR recognized text for this slice
            let matchedText = visionAnalysis?.findMatchingLine(for: sliceRect)?.text

            let slice = PageSlice(
                pageIndex: pageIndex,
                columnIndex: columnIndex,
                sliceIndex: startIndex + idx,
                originalRect: sliceRect,
                columnWidth: columnWidth,
                image: nsImage,
                isFigure: false,
                isTable: false,
                isSideBySide: isSideBySide,
                words: words,
                recognizedText: matchedText
            )
            slices.append(slice)
        }

        return slices
    }

    private static func estimateMedianLineHeight(
        pixelBuffer: PixelBuffer,
        columnRect: CGRect,
        threshold: UInt8,
        minLineHeight: Int
    ) -> Int {
        let rawProj = pixelBuffer.horizontalProjection(in: columnRect, threshold: threshold)
        guard rawProj.count > 15 else { return 28 }

        let noiseFloor = max(3, Int(columnRect.width * 0.006))
        var intervals: [Int] = []
        var inBlock = false
        var startY = 0

        for y in 0..<rawProj.count {
            if rawProj[y] > noiseFloor {
                if !inBlock {
                    inBlock = true
                    startY = y
                }
            } else {
                if inBlock {
                    inBlock = false
                    let h = y - startY
                    if h >= minLineHeight && h <= 120 {
                        intervals.append(h)
                    }
                }
            }
        }

        if intervals.isEmpty { return 28 }
        intervals.sort()
        return intervals[intervals.count / 2]
    }

    private static func splitMultiLineBlock(
        interval: (startY: Int, endY: Int),
        smoothed: [Double],
        expectedLineHeight: Int,
        noiseFloor: Double
    ) -> [(startY: Int, endY: Int)] {
        let totalH = interval.endY - interval.startY + 1
        if Double(totalH) <= Double(expectedLineHeight) * 1.45 {
            return [interval]
        }

        let searchMin = interval.startY + Int(Double(expectedLineHeight) * 0.65)
        let searchMax = min(interval.endY - Int(Double(expectedLineHeight) * 0.65), interval.startY + Int(Double(expectedLineHeight) * 1.40))

        guard searchMax > searchMin else {
            return [interval]
        }

        var bestValley = searchMin
        var minVal = Double.infinity

        for y in searchMin...searchMax {
            if smoothed[y] < minVal {
                minVal = smoothed[y]
                bestValley = y
            }
        }

        // Calculate peak ink within this interval
        var peakInInterval = 1.0
        for y in interval.startY...interval.endY {
            if smoothed[y] > peakInInterval {
                peakInInterval = smoothed[y]
            }
        }

        // Only split if the valley is sufficiently deep (not cutting through solid graphics/ink)
        let valleyThreshold = max(noiseFloor * 2.5, peakInInterval * 0.15)
        if minVal > valleyThreshold {
            return [interval]
        }

        let line1 = (startY: interval.startY, endY: bestValley)
        let remainder = (startY: bestValley + 1, endY: interval.endY)

        var result: [(startY: Int, endY: Int)] = [line1]
        let subResults = splitMultiLineBlock(
            interval: remainder,
            smoothed: smoothed,
            expectedLineHeight: expectedLineHeight,
            noiseFloor: noiseFloor
        )
        result.append(contentsOf: subResults)
        return result
    }
}
