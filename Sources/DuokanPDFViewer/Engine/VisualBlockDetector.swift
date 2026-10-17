import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum VisualRegionType: Sendable {
    case pureText
    case standaloneFigure
    case table
    case sideBySide(figureRect: CGRect, textRect: CGRect, figureOnRight: Bool)
}

public struct VisualRegion: Sendable {
    public let rect: CGRect
    public let type: VisualRegionType

    public init(rect: CGRect, type: VisualRegionType) {
        self.rect = rect
        self.type = type
    }
}

public struct VisualBlockDetector {
    /// Detects tables, standalone figures, side-by-side figure/text, and pure text in a column
    public static func detectVisualRegions(
        pixelBuffer: PixelBuffer,
        columnRect: CGRect,
        threshold: UInt8,
        expectedLineHeight: Int,
        visionAnalysis: VisionPageAnalysis? = nil
    ) -> [VisualRegion] {
        let width = Int(columnRect.width)
        let height = Int(columnRect.height)
        guard width > 30, height > 30 else {
            return [VisualRegion(rect: columnRect, type: .pureText)]
        }

        // 1. Detect Tables via Ruling Lines (Grid detection) reinforced and validated by Apple Vision OCR
        var tableRects = detectTables(
            pixelBuffer: pixelBuffer,
            columnRect: columnRect,
            threshold: threshold,
            expectedLineHeight: expectedLineHeight,
            visionAnalysis: visionAnalysis
        )

        // Reinforce table detection with Vision OCR multi-column alignment strictly within this columnRect
        if let vision = visionAnalysis {
            let ocrTables = vision.detectTableZones(in: columnRect, expectedLineHeight: expectedLineHeight)
            for ocrT in ocrTables {
                let clipped = ocrT.intersection(columnRect)
                if !clipped.isNull && clipped.height >= CGFloat(expectedLineHeight) * 1.5 {
                    let alreadyCovered = tableRects.contains { $0.intersects(clipped) }
                    if !alreadyCovered {
                        tableRects.append(clipped)
                    }
                }
            }
        }

        // 2. Identify candidate vertical bands in columnRect, excluding table regions
        var regions: [VisualRegion] = []
        var currentY = Int(columnRect.minY)
        let maxY = Int(columnRect.maxY)

        // Sort table rects by minY
        let sortedTables = tableRects.sorted { $0.minY < $1.minY }

        for tableRect in sortedTables {
            // Process area above this table
            let aboveHeight = Int(tableRect.minY) - currentY
            if aboveHeight > 10 {
                let aboveRect = CGRect(
                    x: columnRect.minX,
                    y: CGFloat(currentY),
                    width: columnRect.width,
                    height: CGFloat(aboveHeight)
                )
                let subRegions = analyzeNonTableBand(
                    pixelBuffer: pixelBuffer,
                    bandRect: aboveRect,
                    threshold: threshold,
                    expectedLineHeight: expectedLineHeight,
                    visionAnalysis: visionAnalysis
                )
                regions.append(contentsOf: subRegions)
            }

            // Add the table region intact
            regions.append(VisualRegion(rect: tableRect, type: .table))
            currentY = max(currentY, Int(tableRect.maxY))
        }

        // Process area below the last table
        if currentY < maxY - 10 {
            let remainingRect = CGRect(
                x: columnRect.minX,
                y: CGFloat(currentY),
                width: columnRect.width,
                height: CGFloat(maxY - currentY)
            )
            let subRegions = analyzeNonTableBand(
                pixelBuffer: pixelBuffer,
                bandRect: remainingRect,
                threshold: threshold,
                expectedLineHeight: expectedLineHeight,
                visionAnalysis: visionAnalysis
            )
            regions.append(contentsOf: subRegions)
        }

        let consolidated = consolidateVisualRegions(
            regions: regions,
            columnRect: columnRect,
            expectedLineHeight: expectedLineHeight,
            visionAnalysis: visionAnalysis
        )

        return consolidated.isEmpty ? [VisualRegion(rect: columnRect, type: .pureText)] : consolidated
    }

    /// Merges touching or adjacent figure/table blocks and absorbs non-prose chart label bands sandwiched
    /// between figure blocks so magazine photos, charts, and diagrams remain 100% intact.
    private static func consolidateVisualRegions(
        regions: [VisualRegion],
        columnRect: CGRect,
        expectedLineHeight: Int,
        visionAnalysis: VisionPageAnalysis?
    ) -> [VisualRegion] {
        guard regions.count >= 2 else { return regions }

        func isGraphic(_ type: VisualRegionType) -> Bool {
            switch type {
            case .standaloneFigure, .table: return true
            default: return false
            }
        }

        func isChartInternalBand(_ region: VisualRegion) -> Bool {
            guard case .pureText = region.type else { return false }
            guard region.rect.height <= CGFloat(expectedLineHeight) * 12.0 else { return false }
            guard let vision = visionAnalysis else {
                return region.rect.height <= CGFloat(expectedLineHeight) * 2.2
            }
            let lines = vision.lines.filter { line in
                let inter = line.rect.intersection(region.rect)
                return !inter.isNull && inter.height > 4.0 && inter.width > 8.0
            }
            if lines.isEmpty { return true }
            // If any line in this band is a long prose sentence ending with '。' or spanning >= 75% of column width, it's real body text
            let hasLongProse = lines.contains { line in
                let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return (t.count >= 22 && (t.contains("，") || t.contains("。"))) || line.rect.width >= columnRect.width * 0.78
            }
            return !hasLongProse
        }

        var merged: [VisualRegion] = []
        var i = 0
        let maxDirectMergeGap = CGFloat(expectedLineHeight) * 2.0
        let maxSandwichGap = CGFloat(expectedLineHeight) * 3.0

        while i < regions.count {
            var current = regions[i]

            if isGraphic(current.type) {
                var j = i + 1
                while j < regions.count {
                    let next = regions[j]
                    let gap = next.rect.minY - current.rect.maxY

                    if isGraphic(next.type) && gap <= maxDirectMergeGap {
                        let unionRect = current.rect.union(next.rect)
                        let combinedType: VisualRegionType
                        if case .table = current.type, case .table = next.type {
                            combinedType = .table
                        } else {
                            combinedType = .standaloneFigure
                        }
                        current = VisualRegion(rect: unionRect, type: combinedType)
                        j += 1
                    } else if isChartInternalBand(next),
                              (j + 1) < regions.count,
                              isGraphic(regions[j + 1].type),
                              gap <= maxSandwichGap,
                              (regions[j + 1].rect.minY - next.rect.maxY) <= maxSandwichGap {
                        // Sandwiched chart labels between two graphic blocks -> absorb into a single intact figure!
                        let unionRect = current.rect.union(next.rect).union(regions[j + 1].rect)
                        current = VisualRegion(rect: unionRect, type: .standaloneFigure)
                        j += 2
                    } else {
                        break
                    }
                }
                merged.append(current)
                i = j
            } else {
                merged.append(current)
                i += 1
            }
        }

        return merged
    }

    /// Detects tables by locating distinct thin horizontal ruling lines
    private static func detectTables(
        pixelBuffer: PixelBuffer,
        columnRect: CGRect,
        threshold: UInt8,
        expectedLineHeight: Int,
        visionAnalysis: VisionPageAnalysis? = nil
    ) -> [CGRect] {
        let minX = Int(columnRect.minX)
        let maxX = Int(columnRect.maxX)
        let minY = Int(columnRect.minY)
        let maxY = Int(columnRect.maxY)
        let colW = maxX - minX

        // Horizontal ruling line threshold: continuous run >= 45% of column width
        let minHRun = max(50, Int(Double(colW) * 0.45))

        var hLineYCoordinates: [Int] = []
        for y in minY..<maxY {
            var maxRun = 0
            var currentRun = 0
            var gapCount = 0

            // Gap-tolerant horizontal run scanner (tolerates up to 3 white pixel scan noise / binarization breaks)
            for x in minX..<maxX {
                if pixelBuffer.isInk(x: x, y: y, threshold: threshold) {
                    currentRun += (1 + gapCount)
                    gapCount = 0
                    if currentRun > maxRun { maxRun = currentRun }
                } else {
                    if currentRun > 0 && gapCount < 3 {
                        gapCount += 1
                    } else {
                        currentRun = 0
                        gapCount = 0
                    }
                }
            }
            if maxRun >= minHRun {
                hLineYCoordinates.append(y)
            }
        }

        if hLineYCoordinates.count < 3 {
            return []
        }

        // Group contiguous Y coordinates into distinct horizontal lines, filtering out thick dark photo bands (> 14 px)
        var distinctRulingLines: [Int] = []
        var lineStart = hLineYCoordinates[0]
        var lineEnd = hLineYCoordinates[0]

        for i in 1..<hLineYCoordinates.count {
            let y = hLineYCoordinates[i]
            if y - lineEnd <= 4 {
                lineEnd = y
            } else {
                if (lineEnd - lineStart + 1) <= 14 {
                    distinctRulingLines.append((lineStart + lineEnd) / 2)
                }
                lineStart = y
                lineEnd = y
            }
        }
        if (lineEnd - lineStart + 1) <= 14 {
            distinctRulingLines.append((lineStart + lineEnd) / 2)
        }

        // A genuine table requires at least 3 distinct horizontal ruling lines (top, header-divider, bottom)
        guard distinctRulingLines.count >= 3 else {
            return []
        }

        // Cluster ruling lines that are close to form table boundaries (e.g. three-line tables or grid tables)
        var tables: [CGRect] = []
        var clusterStart = distinctRulingLines[0]
        var clusterEnd = distinctRulingLines[0]
        var linesInCluster = 1

        // Maximum span between consecutive ruling lines in the same table: up to 5x expected line height
        let maxLineSpan = expectedLineHeight * 5

        for i in 1..<distinctRulingLines.count {
            let y = distinctRulingLines[i]
            let gap = y - clusterEnd
            if gap <= maxLineSpan {
                clusterEnd = y
                linesInCluster += 1
            } else {
                if linesInCluster >= 3 && (clusterEnd - clusterStart) >= Int(Double(expectedLineHeight) * 1.2) {
                    let tableBounds = computeTightTableBounds(
                        pixelBuffer: pixelBuffer,
                        columnRect: columnRect,
                        topY: clusterStart,
                        bottomY: clusterEnd,
                        threshold: threshold
                    )
                    let clusterRulingLines = distinctRulingLines.filter { $0 >= clusterStart && $0 <= clusterEnd }
                    if isValidTableCandidate(
                        tableBounds: tableBounds,
                        rulingYCoords: clusterRulingLines,
                        columnRect: columnRect,
                        expectedLineHeight: expectedLineHeight,
                        visionAnalysis: visionAnalysis
                    ) {
                        if tableBounds.height <= columnRect.height * 0.72 || linesInCluster >= 4 {
                            tables.append(tableBounds)
                        }
                    }
                }
                clusterStart = y
                clusterEnd = y
                linesInCluster = 1
            }
        }

        if linesInCluster >= 3 && (clusterEnd - clusterStart) >= Int(Double(expectedLineHeight) * 1.2) {
            let tableBounds = computeTightTableBounds(
                pixelBuffer: pixelBuffer,
                columnRect: columnRect,
                topY: clusterStart,
                bottomY: clusterEnd,
                threshold: threshold
            )
            let clusterRulingLines = distinctRulingLines.filter { $0 >= clusterStart && $0 <= clusterEnd }
            if isValidTableCandidate(
                tableBounds: tableBounds,
                rulingYCoords: clusterRulingLines,
                columnRect: columnRect,
                expectedLineHeight: expectedLineHeight,
                visionAnalysis: visionAnalysis
            ) {
                if tableBounds.height <= columnRect.height * 0.72 || linesInCluster >= 4 {
                    tables.append(tableBounds)
                }
            }
        }

        return tables
    }

    /// Validates that a detected ruling-line cluster is a genuine table rather than text paragraphs with underlines,
    /// hyperlinks, or footnote citations.
    private static func isValidTableCandidate(
        tableBounds: CGRect,
        rulingYCoords: [Int],
        columnRect: CGRect,
        expectedLineHeight: Int,
        visionAnalysis: VisionPageAnalysis?
    ) -> Bool {
        guard let vision = visionAnalysis else {
            return true
        }

        let linesInTable = vision.lines.filter { line in
            tableBounds.intersects(line.rect)
        }

        // 1. If candidate block contains footnote markers or footnote headings, it is a footnote section, NOT a table!
        let containsFootnotes = linesInTable.contains { line in
            WordSegmenter.isFootnoteMarker(line.text) ||
            line.text.trimmingCharacters(in: .whitespaces).range(of: "^(注\\s*释|脚\\s*注|附\\s*注|Notes?|Footnotes?)$", options: .regularExpression) != nil
        }
        if containsFootnotes {
            return false
        }

        // 2. Check if the ruling lines are simply underlines beneath text lines (e.g. hyperlinks or underlined citations)
        if !rulingYCoords.isEmpty && !linesInTable.isEmpty {
            var underlineMatchCount = 0
            for rY in rulingYCoords {
                let isUnderline = linesInTable.contains { line in
                    let gap = CGFloat(rY) - line.rect.maxY
                    return gap >= -5.0 && gap <= 10.0
                }
                if isUnderline {
                    underlineMatchCount += 1
                }
            }
            let underlineRatio = Double(underlineMatchCount) / Double(rulingYCoords.count)
            if underlineRatio >= 0.38 {
                // Ruling lines align directly with the bottom baselines of text lines -> Underlined text, NOT a table!
                return false
            }
        }

        // 3. Single-column continuous prose check:
        // Real multi-row tables have cells divided horizontally, or multiple items per row.
        // If every line is full-width prose with sentence punctuation, reject.
        let proseLines = linesInTable.filter { line in
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t.count >= 20 && (t.contains("，") || t.contains("。") || t.contains("、") || t.contains("；"))) ||
                   line.rect.width >= columnRect.width * 0.72
        }
        if proseLines.count >= 3 && proseLines.count >= (linesInTable.count * 2 / 3) {
            let ocrTableZones = vision.detectTableZones(in: tableBounds, expectedLineHeight: expectedLineHeight)
            if ocrTableZones.isEmpty {
                return false
            }
        }

        return true
    }

    private static func computeTightTableBounds(
        pixelBuffer: PixelBuffer,
        columnRect: CGRect,
        topY: Int,
        bottomY: Int,
        threshold: UInt8
    ) -> CGRect {
        let vPad = 6
        let safeTop = max(Int(columnRect.minY), topY - vPad)
        let safeBottom = min(Int(columnRect.maxY), bottomY + vPad)
        return CGRect(
            x: columnRect.minX,
            y: CGFloat(safeTop),
            width: columnRect.width,
            height: CGFloat(safeBottom - safeTop)
        )
    }

    /// Analyzes a non-table band to separate text from standalone figures or side-by-side figure/text
    private static func analyzeNonTableBand(
        pixelBuffer: PixelBuffer,
        bandRect: CGRect,
        threshold: UInt8,
        expectedLineHeight: Int,
        visionAnalysis: VisionPageAnalysis? = nil
    ) -> [VisualRegion] {
        let horizProj = pixelBuffer.horizontalProjection(in: bandRect, threshold: threshold)
        guard horizProj.count > 10 else { return [] }

        // Find candidate continuous ink intervals
        let noiseFloor = max(3, Int(bandRect.width * 0.005))
        var intervals: [(startY: Int, endY: Int)] = []
        var inBlock = false
        var blockStart = 0

        for y in 0..<horizProj.count {
            if horizProj[y] > noiseFloor {
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
            intervals.append((startY: blockStart, endY: horizProj.count - 1))
        }

        var results: [VisualRegion] = []

        for interval in intervals {
            let h = interval.endY - interval.startY + 1
            if h < 8 { continue }

            let subRect = CGRect(
                x: bandRect.minX,
                y: bandRect.minY + CGFloat(interval.startY),
                width: bandRect.width,
                height: CGFloat(h)
            )

            // If height is small (single text line), it's pure text
            if Double(h) < Double(expectedLineHeight) * 1.5 {
                results.append(VisualRegion(rect: subRect, type: .pureText))
                continue
            }

            // Height is substantial (>= 1.5x expectedLineHeight): analyze for Side-by-Side or Figure
            let regionType = classifyMultiLineRegion(
                pixelBuffer: pixelBuffer,
                rect: subRect,
                threshold: threshold,
                expectedLineHeight: expectedLineHeight,
                visionAnalysis: visionAnalysis
            )

            results.append(VisualRegion(rect: subRect, type: regionType))
        }

        return results
    }

    /// Classifies whether a multi-line vertical region is pureText, standaloneFigure, or sideBySide
    /// Adopts Duokan's core philosophy: "图表宁整勿碎" (Never shred diagrams/illustrations into fragments)
    private static func classifyMultiLineRegion(
        pixelBuffer: PixelBuffer,
        rect: CGRect,
        threshold: UInt8,
        expectedLineHeight: Int,
        visionAnalysis: VisionPageAnalysis? = nil
    ) -> VisualRegionType {
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard width > 40, height > 20 else { return .pureText }

        // 1. Check for Side-by-Side coexistence (Figure on one side, Text on the other)
        if let sideBySide = detectSideBySide(
            pixelBuffer: pixelBuffer,
            rect: rect,
            threshold: threshold,
            expectedLineHeight: expectedLineHeight
        ) {
            return sideBySide
        }

        // 2. Compute Horizontal Ink Projection & Valley Periodicity FIRST:
        // A solid photo, framed box, or chart with vertical axes/bars has NO deep horizontal whitespace valleys
        // across its width, even if Vision OCR detects embedded text labels inside it!
        let horizProj = pixelBuffer.horizontalProjection(in: rect, threshold: threshold)
        let peakInk = horizProj.max() ?? 1
        guard peakInk > 0 else { return .pureText }

        var valleyIndices: [Int] = []
        for y in 1..<(height - 1) {
            if horizProj[y] <= horizProj[y - 1] && horizProj[y] <= horizProj[y + 1] {
                if Double(horizProj[y]) <= Double(peakInk) * 0.15 {
                    valleyIndices.append(y)
                }
            }
        }

        var distinctValleys: [Int] = []
        for v in valleyIndices {
            if let last = distinctValleys.last {
                if v - last > 5 {
                    distinctValleys.append(v)
                }
            } else {
                distinctValleys.append(v)
            }
        }

        let expectedLines = Int(round(Double(height) / Double(expectedLineHeight)))

        // 3. OCR-assisted Evidence Check:
        if let vision = visionAnalysis {
            let ocrLinesInRect = vision.lines.filter { line in
                let overlap = line.rect.intersection(rect)
                return !overlap.isNull && overlap.height > 4.0 && overlap.width > 8.0
            }
            let totalOcrChars = ocrLinesInRect.reduce(0) { $0 + $1.text.count }

            // Check if any recognized text explicitly identifies this as a figure / diagram / flowchart
            let hasDiagramMarker = ocrLinesInRect.contains { line in
                let t = line.text
                return t.contains("【图") || t.contains("示意图") || t.contains("流程图") || t.contains("结构图")
                    || t.range(of: "[┌└│─▼▲►◄├┤┬┴┼═║╔╗╚╝]|(图|Figure|Fig\\.)\\s*[0-9一二三四]", options: .regularExpression) != nil
            }
            if hasDiagramMarker {
                return .standaloneFigure
            }

            // Check if this is a large-font article title / headline (1-3 lines of tall characters, e.g. 189px high)
            // which naturally has height >= 2.2x expectedLineHeight and 0 valleys!
            let maxOcrLineH = ocrLinesInRect.map { $0.rect.height }.max() ?? 0
            if !ocrLinesInRect.isEmpty && ocrLinesInRect.count <= 3
                && maxOcrLineH >= CGFloat(expectedLineHeight) * 1.38
                && height <= Int(Double(expectedLineHeight) * 6.0)
                && totalOcrChars >= 4 && totalOcrChars <= 60 {
                return .pureText
            }

            // If height is large (>= 2.2x expectedLineHeight) and there are almost no horizontal valleys,
            // it is physically an inseparable 2D graphic/photo/chart (slicing it horizontally would cut through ink!).
            if height >= Int(Double(expectedLineHeight) * 2.2) && distinctValleys.count < max(1, expectedLines - 2) {
                return .standaloneFigure
            }

            // Distinguish real prose text from scattered chart labels (e.g. bar chart labels, data points, photo credits):
            let hasProseLine = ocrLinesInRect.contains { line in
                let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return (t.count >= 15 && (t.contains("，") || t.contains("。"))) || line.rect.width >= rect.width * 0.65
            }
            let isContinuousProse = ocrLinesInRect.count >= 2 && hasProseLine && (totalOcrChars >= 28)
            if isContinuousProse && distinctValleys.count >= max(1, expectedLines - 2) {
                return .pureText
            }

            // Conversely, if region is tall with ink but has <= 1 sparse text lines and few characters (< 8),
            // it is strongly indicative of a diagram, photo, chart, or formula.
            if height >= Int(Double(expectedLineHeight) * 1.8) && ocrLinesInRect.count <= 1 && totalOcrChars < 8 {
                return .standaloneFigure
            }
        }

        // 4. Periodicity & Uniformity Check:
        if distinctValleys.count >= 2 {
            var intervals: [Double] = []
            for i in 1..<distinctValleys.count {
                intervals.append(Double(distinctValleys[i] - distinctValleys[i - 1]))
            }

            let meanInterval = intervals.reduce(0.0, +) / Double(intervals.count)
            let variance = intervals.reduce(0.0) { $0 + pow($1 - meanInterval, 2) } / Double(intervals.count)
            let stdDev = sqrt(variance)
            let coefficientOfVariation = meanInterval > 0 ? (stdDev / meanInterval) : 1.0

            let lineRatio = meanInterval / Double(expectedLineHeight)
            if coefficientOfVariation > 0.32 || lineRatio < 0.65 || lineRatio > 1.65 {
                return .standaloneFigure
            }

            for v in distinctValleys {
                if Double(horizProj[v]) > Double(peakInk) * 0.10 {
                    return .standaloneFigure
                }
            }

            return .pureText
        }

        if Double(height) >= Double(expectedLineHeight) * 1.8 {
            return .standaloneFigure
        }

        return .pureText
    }

    /// Detects if text and an image/chart coexist horizontally in the same band (Side-by-Side)
    private static func detectSideBySide(
        pixelBuffer: PixelBuffer,
        rect: CGRect,
        threshold: UInt8,
        expectedLineHeight: Int
    ) -> VisualRegionType? {
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard width > 100, height > Int(Double(expectedLineHeight) * 1.6) else {
            return nil
        }

        // Analyze vertical projection of this band to find a vertical split gutter
        let vertProj = pixelBuffer.verticalProjection(in: rect, threshold: threshold)

        // Search for a vertical gutter between 25% and 75% width
        let minSplit = Int(Double(width) * 0.25)
        let maxSplit = Int(Double(width) * 0.75)
        let gutterNoise = max(2, Int(Double(height) * 0.04))

        var bestSplitX: Int? = nil
        var widestGutter = 0
        var gutterStart = 0
        guard minSplit <= maxSplit, maxSplit < vertProj.count else { return nil }
        var inGutter = false

        for x in minSplit...maxSplit {
            if vertProj[x] <= gutterNoise {
                if !inGutter {
                    inGutter = true
                    gutterStart = x
                }
            } else {
                if inGutter {
                    inGutter = false
                    let gWidth = x - gutterStart
                    if gWidth >= 8 && gWidth > widestGutter {
                        widestGutter = gWidth
                        bestSplitX = (gutterStart + x) / 2
                    }
                }
            }
        }

        guard let splitX = bestSplitX else { return nil }

        // Left sub-rect and Right sub-rect
        let leftRect = CGRect(x: rect.minX, y: rect.minY, width: CGFloat(splitX), height: rect.height)
        let rightRect = CGRect(x: rect.minX + CGFloat(splitX), y: rect.minY, width: rect.width - CGFloat(splitX), height: rect.height)

        // Analyze which side is Figure and which side is Text
        let leftProj = pixelBuffer.horizontalProjection(in: leftRect, threshold: threshold)
        let rightProj = pixelBuffer.horizontalProjection(in: rightRect, threshold: threshold)

        let leftValleys = countDeepValleys(proj: leftProj)
        let rightValleys = countDeepValleys(proj: rightProj)

        // Case 1: Left is Text (has line valleys), Right is Figure (no valleys / solid)
        if leftValleys >= 2 && rightValleys <= 1 {
            return .sideBySide(figureRect: rightRect, textRect: leftRect, figureOnRight: true)
        }

        // Case 2: Left is Figure, Right is Text
        if rightValleys >= 2 && leftValleys <= 1 {
            return .sideBySide(figureRect: leftRect, textRect: rightRect, figureOnRight: false)
        }

        return nil
    }

    private static func countDeepValleys(proj: [Int]) -> Int {
        guard proj.count > 4 else { return 0 }
        let peak = proj.max() ?? 1
        var count = 0
        for y in 1..<(proj.count - 1) {
            if proj[y] <= proj[y - 1] && proj[y] <= proj[y + 1] && Double(proj[y]) < Double(peak) * 0.12 {
                count += 1
            }
        }
        return count
    }
}
