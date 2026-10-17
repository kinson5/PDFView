import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Vision

public struct VerticalTextSegmenter {
    /// Segments a vertical page (古籍/港台竖排书籍) into columns from right to left,
    /// slices glyphs from top to bottom, clusters them into continuous paragraphs,
    /// and formats them for fluid modern horizontal reflow and OCR reading.
    public static func segmentVerticalPage(
        pixelBuffer: PixelBuffer,
        originalImage: CGImage,
        contentBounds: CGRect,
        threshold: UInt8,
        visualThreshold: UInt8? = nil,
        pageIndex: Int,
        config: ReflowConfig,
        visionAnalysis: VisionPageAnalysis?
    ) -> (slices: [PageSlice], paragraphs: [ParagraphBlock], columns: [ColumnRegion]) {
        let width = contentBounds.width
        let height = contentBounds.height
        guard width > 30, height > 30 else {
            return ([], [], [])
        }

        // 1. Vertical Projection to detect text columns (V-Cut)
        let vertProj = pixelBuffer.verticalProjection(in: contentBounds, threshold: threshold)
        let avgInk = vertProj.isEmpty ? 0.0 : (Double(vertProj.reduce(0, +)) / Double(vertProj.count))
        let noiseLimit = max(4, min(Int(height * 0.035), Int(avgInk * 0.16)))

        var colIntervals: [(startX: Int, endX: Int)] = []
        var inInk = false
        var startX = 0

        for x in 0..<vertProj.count {
            if vertProj[x] > noiseLimit {
                if !inInk {
                    inInk = true
                    startX = x
                }
            } else {
                if inInk {
                    inInk = false
                    colIntervals.append((startX: startX, endX: x - 1))
                }
            }
        }
        if inInk {
            colIntervals.append((startX: startX, endX: vertProj.count - 1))
        }

        // Filter out dust noise (width < 6 pt)
        colIntervals = colIntervals.filter { ($0.endX - $0.startX + 1) >= 6 }

        // Merge adjacent intervals broken by tiny valleys (gap <= 4px and combined width <= maxColWidth)
        let maxMergedColW = max(55, Int(width * 0.08))
        var mergedIntervals: [(startX: Int, endX: Int)] = []
        for interval in colIntervals {
            if let last = mergedIntervals.last, interval.startX - last.endX <= 4 {
                let combinedWidth = interval.endX - last.startX + 1
                if combinedWidth <= maxMergedColW {
                    mergedIntervals.removeLast()
                    mergedIntervals.append((startX: last.startX, endX: interval.endX))
                    continue
                }
            }
            mergedIntervals.append(interval)
        }
        colIntervals = mergedIntervals

        if colIntervals.isEmpty {
            colIntervals = [(startX: 0, endX: Int(width) - 1)]
        }

        // 2. Sort columns in reading order: RIGHT TO LEFT!
        colIntervals.sort { $0.startX > $1.startX }

        // Initial estimation of character column width
        let colWidths = colIntervals.map { CGFloat($0.endX - $0.startX + 1) }.sorted()
        let initialColWidth = colWidths[colWidths.count / 2]

        // 3. Scan and extract glyph intervals in each column candidate
        struct CandidateColumn {
            let index: Int
            let rect: CGRect
            let glyphs: [(startY: Int, endY: Int)]
            let firstY: CGFloat
            let lastY: CGFloat
        }

        var candidateColumns: [CandidateColumn] = []

        for (colIdx, colInt) in colIntervals.enumerated() {
            let colRect = CGRect(
                x: contentBounds.minX + CGFloat(colInt.startX),
                y: contentBounds.minY,
                width: CGFloat(colInt.endX - colInt.startX + 1),
                height: height
            )

            // Horizontal Projection inside this vertical column (H-Cut) to find glyphs
            let horizProj = pixelBuffer.horizontalProjection(in: colRect, threshold: threshold)
            // In vertical columns, any row with >= 1 black pixel belongs to a character stroke.
            // Using glyphNoise > 0 severely mutilates thin stems and top dots (工, 王, 中, 力, 方, 英, 在, 有).
            let glyphNoise = 0

            var glyphIntervals: [(startY: Int, endY: Int)] = []
            var inGlyph = false
            var startY = 0

            for y in 0..<horizProj.count {
                if horizProj[y] > glyphNoise {
                    if !inGlyph {
                        inGlyph = true
                        startY = y
                    }
                } else {
                    if inGlyph {
                        inGlyph = false
                        glyphIntervals.append((startY: startY, endY: y - 1))
                    }
                }
            }
            if inGlyph {
                glyphIntervals.append((startY: startY, endY: horizProj.count - 1))
            }

            // Filter out 1-pixel sensor dust; preserve punctuation marks (>= 2 px)
            glyphIntervals = glyphIntervals.filter { ($0.endY - $0.startY + 1) >= 2 }
            guard !glyphIntervals.isEmpty else { continue }

            // Filter out continuous vertical ruling lines (边框线/乌丝栏分割线)
            if glyphIntervals.count <= 1 && ((glyphIntervals.first?.endY ?? 0) - (glyphIntervals.first?.startY ?? 0)) > Int(height * 0.35) {
                continue
            }

            // Merge top-bottom radicals within the same Chinese character cell
            var mergedGlyphs: [(startY: Int, endY: Int)] = []
            var curGlyph = glyphIntervals[0]
            let maxCharH = Int(initialColWidth * 1.15)
            let stdRadicalGap = max(4, Int(initialColWidth * 0.28))
            let wideStrokeGap = max(4, Int(initialColWidth * 0.38))

            for i in 1..<glyphIntervals.count {
                let next = glyphIntervals[i]
                let gap = next.startY - curGlyph.endY
                let totalH = next.endY - curGlyph.startY + 1
                let curH = curGlyph.endY - curGlyph.startY + 1
                let nextH = next.endY - next.startY + 1

                let curRect = CGRect(x: colRect.minX, y: CGFloat(curGlyph.startY), width: colRect.width, height: CGFloat(curH))
                let nextRect = CGRect(x: colRect.minX, y: CGFloat(next.startY), width: colRect.width, height: CGFloat(nextH))
                let curKind = classifyVerticalGlyph(pixelBuffer: pixelBuffer, charRect: curRect, colRect: colRect, expectedCharHeight: initialColWidth, threshold: threshold)
                let nextKind = classifyVerticalGlyph(pixelBuffer: pixelBuffer, charRect: nextRect, colRect: colRect, expectedCharHeight: initialColWidth, threshold: threshold)

                let isPunct = (curKind != .upright && curKind != .sidewaysLatin) ||
                              (nextKind != .upright && nextKind != .sidewaysLatin)

                let canMergeClose = (!isPunct && gap <= stdRadicalGap && totalH <= maxCharH)
                let canMergeStroke = (!isPunct && gap <= wideStrokeGap && totalH <= Int(initialColWidth * 0.95) && (curH <= Int(initialColWidth * 0.35) || nextH <= Int(initialColWidth * 0.35)))

                if canMergeClose || canMergeStroke {
                    curGlyph = (startY: curGlyph.startY, endY: next.endY)
                } else {
                    mergedGlyphs.append(curGlyph)
                    curGlyph = next
                }
            }
            mergedGlyphs.append(curGlyph)

            // Strip thin horizontal border ruling lines at top edge (e.g. vintage frame ruling lines)
            while mergedGlyphs.count > 1 {
                let first = mergedGlyphs.first!
                let firstH = first.endY - first.startY + 1
                let gap = mergedGlyphs[1].startY - first.endY
                if firstH <= 3 && gap >= 6 && first.startY <= Int(initialColWidth * 4.0) {
                    mergedGlyphs.removeFirst()
                } else {
                    break
                }
            }

            // Strip thin horizontal border ruling lines at bottom edge
            while mergedGlyphs.count > 1 {
                let last = mergedGlyphs.last!
                let lastH = last.endY - last.startY + 1
                let prev = mergedGlyphs[mergedGlyphs.count - 2]
                let gap = last.startY - prev.endY
                if lastH <= 3 && gap >= 6 && last.endY >= Int(height) - Int(initialColWidth * 4.0) {
                    mergedGlyphs.removeLast()
                } else {
                    break
                }
            }

            // Strip isolated running headers at top edge separated by large whitespace (>= 1.5 * initialColWidth)
            if mergedGlyphs.count > 1 {
                var topCutIdx = 0
                for i in 0..<(mergedGlyphs.count - 1) {
                    let g = mergedGlyphs[i]
                    let next = mergedGlyphs[i + 1]
                    let gap = next.startY - g.endY
                    if gap >= Int(initialColWidth * 1.5) && g.endY <= Int(initialColWidth * 5.0) {
                        topCutIdx = i + 1
                        break
                    }
                }
                if topCutIdx > 0 {
                    mergedGlyphs.removeFirst(topCutIdx)
                }
            }

            // Strip isolated running footers or page numbers at bottom edge separated by large whitespace
            if mergedGlyphs.count > 1 {
                var bottomCutCount = 0
                for i in stride(from: mergedGlyphs.count - 1, through: 1, by: -1) {
                    let g = mergedGlyphs[i]
                    let prev = mergedGlyphs[i - 1]
                    let gap = g.startY - prev.endY
                    if gap >= Int(initialColWidth * 1.5) && g.startY >= Int(height) - Int(initialColWidth * 5.0) {
                        bottomCutCount = mergedGlyphs.count - i
                        break
                    }
                }
                if bottomCutCount > 0 {
                    mergedGlyphs.removeLast(bottomCutCount)
                }
            }

            guard !mergedGlyphs.isEmpty else { continue }

            let firstY = CGFloat(mergedGlyphs.first!.startY)
            let lastY = CGFloat(mergedGlyphs.last!.endY)

            candidateColumns.append(CandidateColumn(
                index: colIdx,
                rect: colRect,
                glyphs: mergedGlyphs,
                firstY: firstY,
                lastY: lastY
            ))
        }

        // Filter out noise/dust columns where no glyph has meaningful character size (>= 0.35 * initialColWidth)
        candidateColumns = candidateColumns.filter { col in
            col.glyphs.contains { ($0.endY - $0.startY + 1) >= Int(initialColWidth * 0.35) }
        }

        guard !candidateColumns.isEmpty else {
            return ([], [], [])
        }

        // 4. Filter Marginalia, Running Headers & Footers:
        // Main text columns have substantial height and character counts.
        let allColHeights = candidateColumns.map { $0.lastY - $0.firstY + 1 }.sorted()
        let medianColHeight = allColHeights[allColHeights.count / 2]

        let validColumns: [CandidateColumn]
        if candidateColumns.count > 3 {
            let substantialColumns = candidateColumns.filter { col in
                let colH = col.lastY - col.firstY + 1
                return colH >= (medianColHeight * 0.35) && col.glyphs.count >= 6
            }
            let minBodyX = substantialColumns.map { $0.rect.minX }.min() ?? 0
            let maxBodyX = substantialColumns.map { $0.rect.maxX }.max() ?? width

            validColumns = candidateColumns.filter { col in
                let colH = col.lastY - col.firstY + 1
                // 1. Substantial column
                if colH >= (medianColHeight * 0.35) && col.glyphs.count >= 6 {
                    return true
                }
                // 2. Short paragraph-end or title column located within the body text block
                if col.glyphs.count >= 2 && colH >= initialColWidth * 1.5 {
                    let isInsideBodyX = col.rect.midX >= (minBodyX - initialColWidth * 0.5) &&
                                        col.rect.midX <= (maxBodyX + initialColWidth * 0.5)
                    return isInsideBodyX
                }
                return false
            }
        } else {
            validColumns = candidateColumns
        }

        guard !validColumns.isEmpty else {
            return ([], [], [])
        }

        // 5. Macro Page Geometry Statistics for Accurate Indentation & Paragraph Bounds
        let allFirstYs = validColumns.map { $0.firstY }.sorted()
        // Top baseline represents unindented body columns. Taking 25th percentile prevents single speckle bias.
        let topBaselineY = allFirstYs.count >= 4 ? allFirstYs[min(1, allFirstYs.count / 4)] : (allFirstYs.first ?? 0)

        let allLastYs = validColumns.map { $0.lastY }.sorted()
        let medianBottomY = allLastYs[allLastYs.count / 2]

        let expectedCharHeight = initialColWidth

        var allSlices: [PageSlice] = []
        var allParagraphs: [ParagraphBlock] = []
        var columnRegions: [ColumnRegion] = []

        // Temporary accumulator for currently building horizontal paragraph
        var currentWords: [WordSlice] = []
        var currentParagraphText: [String] = []
        var currentHasIndent: Bool = false

        func flushCurrentParagraph(isTitle: Bool = false) {
            guard !currentWords.isEmpty else { return }
            let assembledText = currentParagraphText.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            allParagraphs.append(ParagraphBlock(
                paragraphIndex: allParagraphs.count,
                columnIndex: 0,
                hasIndent: isTitle ? false : currentHasIndent,
                isTitle: isTitle,
                semanticLevel: isTitle ? .title : .body,
                words: currentWords,
                baseLineHeight: config.standardBodyLineHeight,
                recognizedText: assembledText.isEmpty ? nil : assembledText
            ))
            currentWords = []
            currentParagraphText = []
            currentHasIndent = false
        }

        // 6. Crop each glyph with precise horizontal ink boundaries for each column
        var allColumnsWords: [[WordSlice]] = []
        for col in validColumns {
            struct RawGlyphCandidate {
                var rect: CGRect
                var kind: VerticalGlyphKind
            }

            var rawCandidates: [RawGlyphCandidate] = []
            for g in col.glyphs {
                let rawY = col.rect.minY + CGFloat(g.startY)
                let rawH = CGFloat(g.endY - g.startY + 1)

                // Measure horizontal ink extent within this glyph to crop tightly (punctuation vs full ideograms)
                let glyphBox = CGRect(x: col.rect.minX, y: rawY, width: col.rect.width, height: rawH)
                let hProj = pixelBuffer.verticalProjection(in: glyphBox, threshold: threshold)
                var inkStartX = 0
                var inkEndX = hProj.count - 1
                while inkStartX < hProj.count && hProj[inkStartX] == 0 { inkStartX += 1 }
                while inkEndX > inkStartX && hProj[inkEndX] == 0 { inkEndX -= 1 }

                let cropX: CGFloat
                let cropW: CGFloat
                if inkStartX <= inkEndX && (inkEndX - inkStartX + 1) >= 2 {
                    cropX = max(0, col.rect.minX + CGFloat(inkStartX) - 1.5)
                    cropW = min(width, CGFloat(inkEndX - inkStartX + 1) + 3.0)
                } else {
                    cropX = col.rect.minX
                    cropW = col.rect.width
                }

                let charRect = CGRect(x: cropX, y: rawY, width: cropW, height: rawH)
                let kind = classifyVerticalGlyph(
                    pixelBuffer: pixelBuffer,
                    charRect: charRect,
                    colRect: col.rect,
                    expectedCharHeight: expectedCharHeight,
                    threshold: threshold
                )
                rawCandidates.append(RawGlyphCandidate(rect: charRect, kind: kind))
            }

            // Helper to crop, enhance, and rotate glyphs/word slices
            func makeSlice(rect: CGRect, rotateCCW: Bool) -> WordSlice? {
                guard let cropped = ImageEnhancer.crop(image: originalImage, to: rect) else {
                    return nil
                }
                let enhanced = ImageEnhancer.enhance(
                    image: cropped,
                    mode: config.binarizationMode,
                    threshold: visualThreshold ?? threshold,
                    config: config,
                    isGraphic: false
                )
                let finalCG: CGImage
                let finalRect: CGRect
                if rotateCCW, let rotated = rotate90CounterClockwise(enhanced) {
                    finalCG = rotated
                    finalRect = CGRect(
                        x: rect.minX,
                        y: rect.minY,
                        width: rect.height,
                        height: rect.width
                    )
                } else {
                    finalCG = enhanced
                    finalRect = rect
                }
                let nsImage = NSImage(cgImage: finalCG, size: finalRect.size)
                return WordSlice(originalRect: finalRect, image: nsImage)
            }

            // Helper to process a sideways Latin run: splits by word spaces (gap >= wordBreakGap),
            // and rotates each word 90° CCW into a natural horizontal WordSlice.
            func processLatinRun(from start: Int, to end: Int) -> [WordSlice] {
                guard start <= end else { return [] }
                let wordBreakGap = max(7.0, expectedCharHeight * 0.22)
                var words: [WordSlice] = []
                var wStart = start

                for k in start...end {
                    let isLast = (k == end)
                    let nextGap = !isLast ? (rawCandidates[k + 1].rect.minY - rawCandidates[k].rect.maxY) : 0
                    if isLast || nextGap >= wordBreakGap {
                        let wMinX = rawCandidates[wStart...k].map { $0.rect.minX }.min() ?? col.rect.minX
                        let wMaxX = rawCandidates[wStart...k].map { $0.rect.maxX }.max() ?? col.rect.maxX
                        let wMinY = rawCandidates[wStart].rect.minY
                        let wMaxY = rawCandidates[k].rect.maxY
                        let wRect = CGRect(
                            x: wMinX,
                            y: wMinY,
                            width: max(col.rect.width * 0.75, wMaxX - wMinX),
                            height: max(1.0, wMaxY - wMinY)
                        )
                        if let slice = makeSlice(rect: wRect, rotateCCW: true) {
                            words.append(slice)
                        }
                        wStart = k + 1
                    }
                }
                return words
            }

            var colWords: [WordSlice] = []
            var idx = 0
            while idx < rawCandidates.count {
                // 1. Bracketed Latin runs: `（` ... `）`
                if rawCandidates[idx].kind == .openingArchOrChevron {
                    // Look ahead for the matching closing bracket (allowing up to 60 candidates)
                    let searchLimit = min(rawCandidates.count - 1, idx + 60)
                    var matchedCloseIdx: Int?
                    if idx + 2 <= searchLimit {
                        for cIdx in (idx + 2)...searchLimit {
                            if rawCandidates[cIdx].kind == .closingArchOrChevron {
                                matchedCloseIdx = cIdx
                                break
                            }
                        }
                    }

                    if let closeIdx = matchedCloseIdx {
                        let innerSlice = rawCandidates[(idx + 1)..<closeIdx]
                        let narrowOrShortCount = innerSlice.filter {
                            $0.rect.width <= expectedCharHeight * 0.85 || $0.rect.height <= expectedCharHeight * 0.75
                        }.count
                        let isLatin = (innerSlice.count >= 2 && Double(narrowOrShortCount) / Double(innerSlice.count) >= 0.65)

                        if isLatin {
                            // Rotate opening parenthesis to horizontal `（`
                            if let openSlice = makeSlice(rect: rawCandidates[idx].rect, rotateCCW: true) {
                                colWords.append(openSlice)
                            }
                            // Convert Latin run into horizontal words
                            colWords.append(contentsOf: processLatinRun(from: idx + 1, to: closeIdx - 1))
                            // Rotate closing parenthesis to horizontal `）`
                            if let closeSlice = makeSlice(rect: rawCandidates[closeIdx].rect, rotateCCW: true) {
                                colWords.append(closeSlice)
                            }
                            idx = closeIdx + 1
                            continue
                        }
                    }
                }

                // 2. Unbracketed sideways Latin runs (e.g. `buzuq`, `na-Musulman`, `ISBN 978...`)
                if rawCandidates[idx].kind == .upright && rawCandidates[idx].rect.height <= expectedCharHeight * 0.78 {
                    var runEnd = idx
                    while runEnd + 1 < rawCandidates.count {
                        let nextCand = rawCandidates[runEnd + 1]
                        let gap = nextCand.rect.minY - rawCandidates[runEnd].rect.maxY
                        if nextCand.kind == .upright &&
                           nextCand.rect.height <= expectedCharHeight * 0.78 &&
                           gap <= expectedCharHeight * 0.38 {
                            runEnd += 1
                        } else {
                            break
                        }
                    }

                    let runCount = runEnd - idx + 1
                    let runSpan = rawCandidates[runEnd].rect.maxY - rawCandidates[idx].rect.minY
                    if runCount >= 2 && runSpan >= expectedCharHeight * 0.85 {
                        colWords.append(contentsOf: processLatinRun(from: idx, to: runEnd))
                        idx = runEnd + 1
                        continue
                    }
                }

                // 3. Regular Chinese character or vertical punctuation
                let cand = rawCandidates[idx]
                let shouldRotate = (cand.kind != .upright)
                if let slice = makeSlice(rect: cand.rect, rotateCCW: shouldRotate) {
                    colWords.append(slice)
                }
                idx += 1
            }

            allColumnsWords.append(colWords)
        }

        // 7. Single-pass Neural OCR for all columns of this page simultaneously
        let allColumnsTexts = batchRecognizeColumns(columnsWords: allColumnsWords, expectedCharHeight: expectedCharHeight)

        // 8. Assemble PageSlices, ColumnRegions, and Horizontal Paragraphs
        for (idx, col) in validColumns.enumerated() {
            let colWords = allColumnsWords[idx]
            guard !colWords.isEmpty else { continue }
            let colText = allColumnsTexts.indices.contains(idx) ? allColumnsTexts[idx] : ""

            // Create Column PageSlice for debugging and zone visualization
            let colCrop = ImageEnhancer.crop(image: originalImage, to: col.rect)
            let colImg = colCrop.flatMap { NSImage(cgImage: $0, size: col.rect.size) } ?? NSImage(size: col.rect.size)

            let colSlice = PageSlice(
                pageIndex: pageIndex,
                columnIndex: idx,
                sliceIndex: allSlices.count,
                originalRect: col.rect,
                columnWidth: col.rect.width,
                image: colImg,
                isFigure: false,
                words: colWords,
                recognizedText: colText.isEmpty ? nil : colText
            )
            allSlices.append(colSlice)
            columnRegions.append(ColumnRegion(index: idx, rect: col.rect, slices: [colSlice]))

            // Paragraph and Heading Identification:
            // Check top indentation relative to top baseline of body columns
            let isTopIndented = (col.firstY - topBaselineY) >= (expectedCharHeight * 0.75)
            // Check bottom early termination (at least 4 character spaces from bottom baseline)
            let isBottomShort = (medianBottomY - col.lastY) >= (expectedCharHeight * 4.0)

            // Heading / Title check: Short column (<= 6 chars) with significant top space
            let isTitleColumn = (colWords.count <= 6) &&
                                (isTopIndented || (col.firstY - topBaselineY) >= (expectedCharHeight * 1.5)) &&
                                isBottomShort

            if isTitleColumn {
                flushCurrentParagraph()
                currentWords = colWords
                if !colText.isEmpty {
                    currentParagraphText = [colText]
                }
                flushCurrentParagraph(isTitle: true)
                continue
            }

            // Body Column Flow:
            if isTopIndented {
                flushCurrentParagraph()
                currentHasIndent = true
            }

            currentWords.append(contentsOf: colWords)
            if !colText.isEmpty {
                currentParagraphText.append(colText)
            }

            if isBottomShort {
                flushCurrentParagraph()
            }
        }

        flushCurrentParagraph()

        return (slices: allSlices, paragraphs: allParagraphs, columns: columnRegions)
    }

    private enum VerticalGlyphKind {
        case upright
        case verticalDash
        case openingArchOrChevron
        case closingArchOrChevron
        case cornerQuote
        case sidewaysLatin
    }

    /// Classifies whether a vertical column glyph is a directional vertical punctuation mark
    /// (`︽`, `︾`, `︵`, `︶`, `﹁`, `﹂`, `﹃`, `﹄`, `︱`) that is rotated 90° CW in vertical typesetting
    /// and therefore needs a 90° CCW rotation when reflowed into horizontal lines.
    private static func classifyVerticalGlyph(
        pixelBuffer: PixelBuffer,
        charRect: CGRect,
        colRect: CGRect,
        expectedCharHeight: CGFloat,
        threshold: UInt8
    ) -> VerticalGlyphKind {
        let cropW = charRect.width
        let rawH = charRect.height
        guard cropW >= 4, rawH >= 4, expectedCharHeight > 10 else { return .upright }

        // 1. Vertical dash `︱` -> `—`
        if cropW <= expectedCharHeight * 0.22 &&
           rawH >= expectedCharHeight * 0.35 &&
           rawH >= cropW * 2.5 &&
           abs(charRect.midX - colRect.midX) <= colRect.width * 0.25 {
            return .verticalDash
        }

        let startX = max(0, Int(charRect.minX))
        let endX = min(pixelBuffer.width - 1, Int(charRect.maxX) - 1)
        let startY = max(0, Int(charRect.minY))
        let endY = min(pixelBuffer.height - 1, Int(charRect.maxY) - 1)
        let spanX = endX - startX + 1
        let spanY = endY - startY + 1
        guard spanX >= 5, spanY >= 5 else { return .upright }

        // 2. Vertical arches/chevrons: `︵`, `︶`, `︽`, `︾`
        // Distinguishes curved/chevron brackets from straight horizontal strokes ("一", "二", "三").
        if cropW >= expectedCharHeight * 0.68 &&
           rawH >= expectedCharHeight * 0.18 &&
           rawH <= expectedCharHeight * 0.56 &&
           abs(charRect.midX - colRect.midX) <= colRect.width * 0.22 {
            let thirdX = max(1, spanX / 3)
            var sumYLeft = 0.0, countLeft = 0
            var sumYMid = 0.0, countMid = 0
            var sumYRight = 0.0, countRight = 0
            var midColsWithInk = 0
            var topMidInk = 0
            var botMidInk = 0

            for x in startX...endX {
                let relX = x - startX
                var colHasInk = false
                for y in startY...endY {
                    if pixelBuffer.isInk(x: x, y: y, threshold: threshold) {
                        let relY = Double(y - startY)
                        colHasInk = true
                        if relX < thirdX {
                            sumYLeft += relY
                            countLeft += 1
                        } else if relX < thirdX * 2 {
                            sumYMid += relY
                            countMid += 1
                            if relY < Double(spanY) * 0.35 {
                                topMidInk += 1
                            }
                            if relY > Double(spanY) * 0.65 {
                                botMidInk += 1
                            }
                        } else {
                            sumYRight += relY
                            countRight += 1
                        }
                    }
                }
                if relX >= thirdX && relX < thirdX * 2 && colHasInk {
                    midColsWithInk += 1
                }
            }

            let midSpan = max(1, thirdX)
            let midCoverage = Double(midColsWithInk) / Double(midSpan)
            if countLeft >= 3 && countMid >= 3 && countRight >= 3 && midCoverage >= 0.75 {
                let yLeft = sumYLeft / Double(countLeft)
                let yMid = sumYMid / Double(countMid)
                let yRight = sumYRight / Double(countRight)
                let wingAvg = 0.5 * (yLeft + yRight)
                let archDelta = wingAvg - yMid // > 0 if apex is at top (︵, ︽); < 0 if apex is at bottom (︶, ︾)

                if yMid < yLeft && yMid < yRight && archDelta >= Double(spanY) * 0.14 && botMidInk <= max(1, midSpan / 5) {
                    return .openingArchOrChevron
                }
                if yMid > yLeft && yMid > yRight && (-archDelta) >= Double(spanY) * 0.14 && topMidInk <= max(1, midSpan / 5) {
                    return .closingArchOrChevron
                }
            }
        }

        // 3. Vertical corner quotes: `﹁`, `﹂`, `﹃`, `﹄`
        if cropW >= expectedCharHeight * 0.24 &&
           cropW <= expectedCharHeight * 1.08 &&
           rawH >= expectedCharHeight * 0.18 &&
           rawH <= expectedCharHeight * 0.65 &&
           max(cropW, rawH) >= expectedCharHeight * 0.30 {
            let splitX = max(1, Int(Double(spanX) * 0.45))
            let splitY = max(1, Int(Double(spanY) * 0.45))
            var inkTL = 0, inkTR = 0, inkBL = 0, inkBR = 0
            var totalInk = 0

            for y in startY...endY {
                let relY = y - startY
                for x in startX...endX {
                    if pixelBuffer.isInk(x: x, y: y, threshold: threshold) {
                        totalInk += 1
                        let relX = x - startX
                        let isLeft = relX < splitX
                        let isRight = relX >= (spanX - splitX)
                        let isTop = relY < splitY
                        let isBottom = relY >= (spanY - splitY)
                        if isTop && isLeft { inkTL += 1 }
                        if isTop && isRight { inkTR += 1 }
                        if isBottom && isLeft { inkBL += 1 }
                        if isBottom && isRight { inkBR += 1 }
                    }
                }
            }

            if totalInk >= 10 {
                // Opening corner quote `﹁` / `﹃`: top-right corner has ink in TL, TR, BR, and empty BL
                if inkBL <= max(1, totalInk / 35) &&
                   inkTR >= totalInk / 8 &&
                   inkTL >= totalInk / 12 &&
                   inkBR >= totalInk / 12 {
                    return .cornerQuote
                }
                // Closing corner quote `﹂` / `﹄`: bottom-left corner has ink in TL, BL, BR, and empty TR
                if inkTR <= max(1, totalInk / 35) &&
                   inkBL >= totalInk / 8 &&
                   inkTL >= totalInk / 12 &&
                   inkBR >= totalInk / 12 {
                    return .cornerQuote
                }
            }
        }

        return .upright
    }

    /// Rotates a CGImage 90° counter-clockwise so vertical punctuation (`︽`, `︾`, `︵`, `︶`, `﹁`, `﹂`)
    /// and sideways Latin runs become upright horizontal glyphs (`《`, `》`, `（`, `）`, `「`, `」`).
    private static func rotate90CounterClockwise(_ image: CGImage) -> CGImage? {
        let origW = CGFloat(image.width)
        let origH = CGFloat(image.height)
        let newW = Int(origH)
        let newH = Int(origW)
        guard newW > 0, newH > 0,
              let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: newW,
                height: newH,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        ctx.translateBy(x: CGFloat(newW) / 2.0, y: CGFloat(newH) / 2.0)
        ctx.rotate(by: .pi / 2.0)
        ctx.draw(image, in: CGRect(x: -origW / 2.0, y: -origH / 2.0, width: origW, height: origH))
        return ctx.makeImage()
    }

    /// Neural OCR on Vertical Books: Batches all vertical columns into a single synthetic multi-line
    /// image where each column is laid out as a distinct horizontal line. Apple Vision reads the entire page
    /// in ONE single-pass request, achieving >10x speedup and avoiding GPU/Neural Engine lockups.
    private static func batchRecognizeColumns(columnsWords: [[WordSlice]], expectedCharHeight: CGFloat) -> [String] {
        let n = columnsWords.count
        guard n > 0 else { return [] }

        let targetCharH: CGFloat = 32.0
        let charSpacing: CGFloat = 4.0
        let lineGap: CGFloat = 20.0
        let rowH = targetCharH + lineGap
        let uniformScale = targetCharH / max(14.0, expectedCharHeight)

        // Measure proportional widths and heights for all rows
        var maxRowW: CGFloat = 100.0
        var allRowScaledSizes: [[CGSize]] = []

        for words in columnsWords {
            let sample = Array(words.prefix(85))
            var scaledSizes: [CGSize] = []
            for w in sample {
                let sw = max(4.0, min(targetCharH * 25.0, w.originalRect.width * uniformScale))
                let sh = max(3.0, min(targetCharH * 1.15, w.originalRect.height * uniformScale))
                scaledSizes.append(CGSize(width: sw, height: sh))
            }
            let rowW = scaledSizes.reduce(0) { $0 + $1.width } + CGFloat(sample.count + 1) * charSpacing + 30.0
            maxRowW = max(maxRowW, rowW)
            allRowScaledSizes.append(scaledSizes)
        }

        let totalW = max(100.0, maxRowW)
        let totalH = CGFloat(n) * rowH + 20.0

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: Int(totalW),
                height: Int(totalH),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return [String](repeating: "", count: n)
        }

        // Fill background white
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: totalW, height: totalH))

        // Draw each column as a horizontal line from top to bottom
        for rowIdx in 0..<n {
            let words = Array(columnsWords[rowIdx].prefix(85))
            let scaledSizes = allRowScaledSizes[rowIdx]
            let drawY = totalH - CGFloat(rowIdx + 1) * rowH + (lineGap / 2.0)

            var currX: CGFloat = 15.0
            for (i, w) in words.enumerated() {
                let sz = scaledSizes[i]
                if let cg = w.image.platformCGImage {
                    let yOffset = (targetCharH - sz.height) / 2.0
                    let drawRect = CGRect(x: currX, y: drawY + yOffset, width: sz.width, height: sz.height)
                    ctx.draw(cg, in: drawRect)
                    currX += sz.width + charSpacing
                }
            }
        }

        guard let stitchedImg = ctx.makeImage() else {
            return [String](repeating: "", count: n)
        }

        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
        req.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: stitchedImg, options: [:])
        do {
            try handler.perform([req])
        } catch {
            return [String](repeating: "", count: n)
        }

        var rowTextPieces = [[(x: CGFloat, text: String)]](repeating: [], count: n)
        let obs = req.results ?? []

        for o in obs {
            guard let topCand = o.topCandidates(1).first?.string, !topCand.isEmpty else { continue }
            // Vision bounding box is normalized (0.0 to 1.0) with origin at bottom-left
            let midYPixel = o.boundingBox.midY * totalH
            let distFromTop = totalH - midYPixel
            let estimatedRow = Int(distFromTop / rowH)
            let clampedRow = max(0, min(n - 1, estimatedRow))
            rowTextPieces[clampedRow].append((x: o.boundingBox.minX, text: topCand))
        }

        var results: [String] = []
        for rowIdx in 0..<n {
            let sortedPieces = rowTextPieces[rowIdx].sorted { $0.x < $1.x }
            let joinedText = sortedPieces.map { $0.text }.joined()
            results.append(joinedText)
        }

        return results
    }
}
