import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct DetectedMacroZones: Sendable {
    public let allZones: [PageZone]
    public let headerZone: PageZone?
    public let bodyZones: [PageZone]
    public let footnoteZone: PageZone?
    public let footerZone: PageZone?

    public init(
        allZones: [PageZone],
        headerZone: PageZone?,
        bodyZones: [PageZone],
        footnoteZone: PageZone?,
        footerZone: PageZone?
    ) {
        self.allZones = allZones
        self.headerZone = headerZone
        self.bodyZones = bodyZones
        self.footnoteZone = footnoteZone
        self.footerZone = footerZone
    }
}

public struct PageZoneDetector {
    /// Partitions the auto-cropped page content into macro structural zones using Whitespace Stream analysis
    public static func detectZones(
        pixelBuffer: PixelBuffer,
        contentBounds: CGRect,
        layoutThreshold: UInt8,
        visionAnalysis: VisionPageAnalysis?,
        resolvedProfile: LayoutProfile,
        detectedColumns: [CGRect]
    ) -> DetectedMacroZones {
        let width = contentBounds.width
        let height = contentBounds.height
        guard width > 30, height > 30 else {
            let single = PageZone(type: .body, rect: contentBounds)
            return DetectedMacroZones(allZones: [single], headerZone: nil, bodyZones: [single], footnoteZone: nil, footerZone: nil)
        }

        // 1. Compute Horizontal Ink Projection
        let horizProj = pixelBuffer.horizontalProjection(in: contentBounds, threshold: layoutThreshold)
        let noiseFloor = max(3, Int(width * 0.005))

        // 2. Locate distinct continuous ink intervals
        var intervals: [(startY: Int, endY: Int)] = []
        var inInk = false
        var startY = 0

        for y in 0..<horizProj.count {
            if horizProj[y] > noiseFloor {
                if !inInk {
                    inInk = true
                    startY = y
                }
            } else {
                if inInk {
                    inInk = false
                    intervals.append((startY: startY, endY: y - 1))
                }
            }
        }
        if inInk {
            intervals.append((startY: startY, endY: horizProj.count - 1))
        }

        guard !intervals.isEmpty else {
            let single = PageZone(type: .body, rect: contentBounds)
            return DetectedMacroZones(allZones: [single], headerZone: nil, bodyZones: [single], footnoteZone: nil, footerZone: nil)
        }

        // 3. Merge adjacent lines into Macro Horizontal Bands when vertical gap is small (normal line gap)
        // A macro gap separating Header, Body, Footnote or Footer is typically >= 24 pt
        let macroGapThreshold = 24

        var macroBands: [(startY: Int, endY: Int)] = []
        var currentBand = intervals[0]

        for i in 1..<intervals.count {
            let next = intervals[i]
            let gap = next.startY - currentBand.endY

            // Check if this gap is a macro whitespace separation
            if gap >= macroGapThreshold {
                macroBands.append(currentBand)
                currentBand = next
            } else {
                // Merge into current band
                currentBand = (startY: currentBand.startY, endY: next.endY)
            }
        }
        macroBands.append(currentBand)

        var headerZone: PageZone? = nil
        var footerZone: PageZone? = nil
        var footnoteZone: PageZone? = nil
        var remainingBands: [(startY: Int, endY: Int)] = macroBands

        // 4. Identify Header Zone (顶部页眉区)
        if let first = remainingBands.first {
            let firstRect = CGRect(
                x: contentBounds.minX,
                y: contentBounds.minY + CGFloat(first.startY),
                width: width,
                height: CGFloat(first.endY - first.startY + 1)
            )
            let isNearTop = firstRect.minY <= contentBounds.minY + (height * 0.12)
            let isShort = firstRect.height <= 55.0
            let ocrLines = visionAnalysis?.lines.filter { firstRect.intersects($0.rect) } ?? []
            let ocrText = ocrLines.map { $0.text }.joined(separator: " ")
            let hasTitleKeywords = ocrText.contains("关于") || ocrText.contains("通报") || ocrText.contains("通知") || ocrText.contains("决定")

            // If near top, short, and not a massive document title
            if isNearTop && isShort && !hasTitleKeywords && (ocrText.count <= 35 || ocrLines.isEmpty) && remainingBands.count > 1 {
                headerZone = PageZone(type: .header, rect: firstRect)
                remainingBands.removeFirst()
            }
        }

        // 5. Identify Footer Zone (底部页码区)
        if let last = remainingBands.last {
            let lastRect = CGRect(
                x: contentBounds.minX,
                y: contentBounds.minY + CGFloat(last.startY),
                width: width,
                height: CGFloat(last.endY - last.startY + 1)
            )
            let isNearBottom = lastRect.maxY >= contentBounds.maxY - (height * 0.12)
            let isShort = lastRect.height <= 60.0
            let ocrLines = visionAnalysis?.lines.filter { lastRect.intersects($0.rect) } ?? []
            let ocrText = ocrLines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
            let isPageNum = ocrText.range(of: "^([—\\-~–]?\\s*[0-9一二三四五六七八九十]+\\s*[—\\-~–]?|第\\s*[0-9]+\\s*页(\\s*[/共]\\s*[0-9]+\\s*页)?|\\s*[0-9]+\\s*)$", options: .regularExpression) != nil
            let isMagFooter = ocrText.count <= 28 && (ocrText.contains("财经") || ocrText.contains("財经") || ocrText.range(of: "[0-9]{4}\\.[0-9]{1,2}", options: .regularExpression) != nil)

            if isNearBottom && isShort && (isPageNum || isMagFooter || ocrText.count <= 10) && remainingBands.count > 1 {
                footerZone = PageZone(type: .footer, rect: lastRect)
                remainingBands.removeLast()
            }
        }

        // 6. Identify Footnote Zone (底部注脚区)
        // In books and monographs (not official docs), locate footnote band
        if resolvedProfile != .officialDoc && resolvedProfile != .magazine {
            if let candidateFootnote = remainingBands.last, remainingBands.count > 1 {
                let footnoteRect = CGRect(
                    x: contentBounds.minX,
                    y: contentBounds.minY + CGFloat(candidateFootnote.startY),
                    width: width,
                    height: CGFloat(candidateFootnote.endY - candidateFootnote.startY + 1)
                )
                let isNearBottomZone = footnoteRect.maxY >= contentBounds.maxY - (height * 0.38)
                let ocrLines = visionAnalysis?.lines.filter { footnoteRect.intersects($0.rect) } ?? []

                let hasFootnoteMarker = ocrLines.contains { line in
                    WordSegmenter.isFootnoteMarker(line.text) ||
                    line.text.trimmingCharacters(in: .whitespaces).range(of: "^(注\\s*释|脚\\s*注|附\\s*注|Notes?|Footnotes?)$", options: .regularExpression) != nil
                }

                if isNearBottomZone && hasFootnoteMarker {
                    footnoteZone = PageZone(type: .footnote, rect: footnoteRect)
                    remainingBands.removeLast()
                }
            } else if let lastBand = remainingBands.last, let vision = visionAnalysis {
                // Footnote was merged with body because the line gap was small or separated by a heading / rule
                let bandRect = CGRect(
                    x: contentBounds.minX,
                    y: contentBounds.minY + CGFloat(lastBand.startY),
                    width: width,
                    height: CGFloat(lastBand.endY - lastBand.startY + 1)
                )
                let candidateLines = vision.lines.filter { line in
                    bandRect.intersects(line.rect) && line.rect.minY >= contentBounds.minY + (height * 0.38)
                }.sorted { $0.rect.minY < $1.rect.minY }

                // Find footnote start line: either a footnote heading ("注 释", "注释", "Notes") or a footnote marker line
                if let fnIndex = candidateLines.firstIndex(where: { line in
                    let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                    let isHeading = trimmed.range(of: "^(注\\s*释|脚\\s*注|附\\s*注|Notes?|Footnotes?)$", options: .regularExpression) != nil
                    let isMarker = WordSegmenter.isFootnoteMarker(trimmed)
                    return isHeading || isMarker
                }) {
                    let fnStartLine = candidateLines[fnIndex]
                    let splitY = Int(fnStartLine.rect.minY - contentBounds.minY) - 4
                    if splitY > lastBand.startY + 40 {
                        let fnBand = (startY: splitY, endY: lastBand.endY)
                        let bodyBand = (startY: lastBand.startY, endY: splitY - 1)
                        remainingBands[remainingBands.count - 1] = bodyBand

                        let fnRect = CGRect(
                            x: contentBounds.minX,
                            y: contentBounds.minY + CGFloat(fnBand.startY),
                            width: width,
                            height: CGFloat(fnBand.endY - fnBand.startY + 1)
                        )
                        footnoteZone = PageZone(type: .footnote, rect: fnRect)
                    }
                }
            }
        }

        // 7. Formulate Main Body Zones using Recursive XY-Cut for Multi-Column & Magazine Layouts
        var bodyZones: [PageZone] = []

        if !remainingBands.isEmpty {
            let minY = CGFloat(remainingBands.first!.startY) + contentBounds.minY
            let maxY = CGFloat(remainingBands.last!.endY) + contentBounds.minY
            let bodyRect = CGRect(x: contentBounds.minX, y: minY, width: width, height: max(1.0, maxY - minY + 1))

            let isMultiColumnProfile = (resolvedProfile == .academic || resolvedProfile == .magazine)

            if isMultiColumnProfile {
                let decomposedRects = decomposeBodyRect(
                    rect: bodyRect,
                    fullPageWidth: width,
                    pixelBuffer: pixelBuffer,
                    threshold: layoutThreshold,
                    visionAnalysis: visionAnalysis,
                    depth: 0
                )
                for (idx, r) in decomposedRects.enumerated() {
                    bodyZones.append(PageZone(type: .body, rect: r, columnIndex: idx))
                }
            } else {
                bodyZones.append(PageZone(type: .body, rect: bodyRect, columnIndex: 0))
            }
        } else {
            bodyZones.append(PageZone(type: .body, rect: contentBounds, columnIndex: 0))
        }

        // 8. Assemble all zones in reading topology order: Header -> Body -> Footnote -> Footer
        var allZones: [PageZone] = []
        if let h = headerZone { allZones.append(h) }
        allZones.append(contentsOf: bodyZones)
        if let fn = footnoteZone { allZones.append(fn) }
        if let ft = footerZone { allZones.append(ft) }

        return DetectedMacroZones(
            allZones: allZones,
            headerZone: headerZone,
            bodyZones: bodyZones,
            footnoteZone: footnoteZone,
            footerZone: footerZone
        )
    }

    /// Recursively decomposes a magazine or multi-column body rect into structural zones (Recursive XY-Cut).
    /// Preserves spanning titles, spanning lead-ins, and 2-column/3-column photos & charts intact
    /// while cleanly splitting multi-column text regions into individual columns in reading order.
    private static func decomposeBodyRect(
        rect: CGRect,
        fullPageWidth: CGFloat,
        pixelBuffer: PixelBuffer,
        threshold: UInt8,
        visionAnalysis: VisionPageAnalysis?,
        depth: Int
    ) -> [CGRect] {
        // Base case: stop recursion if narrow (already 1 single column) or too short or max depth reached
        if depth >= 6 || rect.width < fullPageWidth * 0.46 || rect.height < 110 {
            return [rect]
        }

        // 1. Check valid full-height vertical column splits in `rect` (filtering out cuts that slice through spanning blocks)
        let validFullCols = detectNonSpanningColumns(
            in: rect,
            fullPageWidth: fullPageWidth,
            pixelBuffer: pixelBuffer,
            threshold: threshold,
            visionAnalysis: visionAnalysis
        )

        // If `rect` cleanly splits into 2+ vertical columns without cutting any spanning block:
        // Recurse into each column (e.g., if one of the columns is a 2-column-wide sub-block like Col 1+2 on Page 21/29/71!)
        if validFullCols.count >= 2 {
            var results: [CGRect] = []
            for colRect in validFullCols {
                let subZones = decomposeBodyRect(
                    rect: colRect,
                    fullPageWidth: fullPageWidth,
                    pixelBuffer: pixelBuffer,
                    threshold: threshold,
                    visionAnalysis: visionAnalysis,
                    depth: depth + 1
                )
                results.append(contentsOf: subZones)
            }
            return results
        }

        // 2. `rect` could not be split vertically over its full height because a spanning title, deck, photo,
        // or table/chart blocks the vertical gutter(s) over part of `rect`.
        // Search for a horizontal split `splitY` that separates the spanning band from the multi-column band!
        if let splitY = findBestHorizontalSplitY(
            in: rect,
            fullPageWidth: fullPageWidth,
            pixelBuffer: pixelBuffer,
            threshold: threshold,
            visionAnalysis: visionAnalysis
        ) {
            let topRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: splitY - rect.minY)
            let botRect = CGRect(x: rect.minX, y: splitY, width: rect.width, height: rect.maxY - splitY)

            var results: [CGRect] = []
            results.append(contentsOf: decomposeBodyRect(
                rect: topRect,
                fullPageWidth: fullPageWidth,
                pixelBuffer: pixelBuffer,
                threshold: threshold,
                visionAnalysis: visionAnalysis,
                depth: depth + 1
            ))
            results.append(contentsOf: decomposeBodyRect(
                rect: botRect,
                fullPageWidth: fullPageWidth,
                pixelBuffer: pixelBuffer,
                threshold: threshold,
                visionAnalysis: visionAnalysis,
                depth: depth + 1
            ))
            return results
        }

        return [rect]
    }

    /// Detects vertical column rects in `rect`, rejecting any cut point that would slice through
    /// a spanning OCR text line or a continuous spanning graphic/photo/table block.
    private static func detectNonSpanningColumns(
        in rect: CGRect,
        fullPageWidth: CGFloat,
        pixelBuffer: PixelBuffer,
        threshold: UInt8,
        visionAnalysis: VisionPageAnalysis?
    ) -> [CGRect] {
        var rawCols = ColumnDetector.detectColumns(
            pixelBuffer: pixelBuffer,
            contentBounds: rect,
            threshold: threshold
        )
        if rawCols.count < 2, let vision = visionAnalysis {
            rawCols = detectColumnsFromVisionLines(in: rect, vision: vision)
        }
        guard rawCols.count >= 2 else { return [rect] }

        let minAllowedColWidth = max(80.0, fullPageWidth * 0.22)

        // Extract internal vertical cut X coordinates
        var validCuts: [CGFloat] = []
        for i in 0..<(rawCols.count - 1) {
            let cutX = rawCols[i].maxX
            if !isCutBlockedBySpanningContent(
                cutX: cutX,
                in: rect,
                pixelBuffer: pixelBuffer,
                threshold: threshold,
                visionAnalysis: visionAnalysis
            ) {
                validCuts.append(cutX)
            }
        }

        guard !validCuts.isEmpty else { return [rect] }

        var cols: [CGRect] = []
        var prevX = rect.minX
        for cutX in validCuts {
            let w = cutX - prevX
            if w >= minAllowedColWidth {
                cols.append(CGRect(x: prevX, y: rect.minY, width: w, height: rect.height))
                prevX = cutX
            }
        }
        let lastW = rect.maxX - prevX
        if lastW >= minAllowedColWidth {
            cols.append(CGRect(x: prevX, y: rect.minY, width: lastW, height: rect.height))
        } else if !cols.isEmpty {
            let lastCol = cols.removeLast()
            cols.append(CGRect(x: lastCol.minX, y: rect.minY, width: rect.maxX - lastCol.minX, height: rect.height))
        }

        return cols.count >= 2 ? cols : [rect]
    }

    /// Detects vertical column rects inside `rect` by projecting the horizontal intervals of Vision / Native PDF text lines
    private static func detectColumnsFromVisionLines(
        in rect: CGRect,
        vision: VisionPageAnalysis
    ) -> [CGRect] {
        let w = Int(rect.width)
        guard w >= 240, rect.height >= 100 else { return [rect] }

        let linesInRect = vision.lines.filter { l in
            l.rect.midY >= rect.minY + 8 &&
            l.rect.midY <= rect.maxY - 8 &&
            l.rect.minX >= rect.minX - 15 &&
            l.rect.maxX <= rect.maxX + 15 &&
            l.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
        }
        guard linesInRect.count >= 6 else { return [rect] }

        // If any line inside `rect` spans > 55% of `rect.width`, it is a spanning headline/lead-in
        if linesInRect.contains(where: { $0.rect.width > rect.width * 0.55 }) {
            return [rect]
        }

        var coverage = [Int](repeating: 0, count: w)
        for l in linesInRect {
            let startX = max(0, min(w - 1, Int(floor(l.rect.minX - rect.minX))))
            let endX = max(startX, min(w - 1, Int(ceil(l.rect.maxX - rect.minX))))
            for x in startX...endX {
                coverage[x] += 1
            }
        }

        let marginX = Int(Double(w) * 0.18)
        let minGutterW = max(14, Int(Double(w) * 0.015))
        guard w > marginX * 2 + minGutterW else { return [rect] }

        var gutters: [(start: Int, end: Int, width: Int)] = []
        var inZero = false
        var gStart = marginX

        for x in marginX..<(w - marginX) {
            if coverage[x] == 0 {
                if !inZero {
                    inZero = true
                    gStart = x
                }
            } else {
                if inZero {
                    inZero = false
                    let gw = x - gStart
                    if gw >= minGutterW {
                        gutters.append((start: gStart, end: x, width: gw))
                    }
                }
            }
        }
        if inZero {
            let gw = (w - marginX) - gStart
            if gw >= minGutterW {
                gutters.append((start: gStart, end: w - marginX, width: gw))
            }
        }

        guard !gutters.isEmpty else { return [rect] }

        let minColW = Int(Double(w) * 0.22)
        var cutOffsets: [Int] = []
        for g in gutters.sorted(by: { $0.width > $1.width }) {
            let center = (g.start + g.end) / 2
            let absCutX = rect.minX + CGFloat(center)
            let leftLineCount = linesInRect.filter { $0.rect.maxX <= absCutX + 4 }.count
            let rightLineCount = linesInRect.filter { $0.rect.minX >= absCutX - 4 }.count
            guard leftLineCount >= 3, rightLineCount >= 3 else { continue }

            if center >= minColW && (w - center) >= minColW {
                if !cutOffsets.contains(where: { abs($0 - center) < minColW }) {
                    cutOffsets.append(center)
                }
            }
            if cutOffsets.count >= 2 { break }
        }

        guard !cutOffsets.isEmpty else { return [rect] }
        cutOffsets.sort()

        var cols: [CGRect] = []
        var prevX = 0
        for cut in cutOffsets {
            let cw = cut - prevX
            if cw > 20 {
                cols.append(CGRect(x: rect.minX + CGFloat(prevX), y: rect.minY, width: CGFloat(cw), height: rect.height))
            }
            prevX = cut
        }
        let remW = w - prevX
        if remW > 20 {
            cols.append(CGRect(x: rect.minX + CGFloat(prevX), y: rect.minY, width: CGFloat(remW), height: rect.height))
        }
        return cols.count >= 2 ? cols : [rect]
    }

    /// Checks whether a vertical column cut at `cutX` slices through a spanning title/deck line or a spanning image/table
    private static func isCutBlockedBySpanningContent(
        cutX: CGFloat,
        in rect: CGRect,
        pixelBuffer: PixelBuffer,
        threshold: UInt8,
        visionAnalysis: VisionPageAnalysis?
    ) -> Bool {
        // 1. Check if any significant OCR line inside `rect` bridges across `cutX`
        if let vision = visionAnalysis {
            let margin: CGFloat = 32.0
            let bridgingLines = vision.lines.filter { line in
                line.rect.midY >= rect.minY + 10 &&
                line.rect.midY <= rect.maxY - 10 &&
                line.rect.minX < cutX - margin &&
                line.rect.maxX > cutX + margin &&
                line.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
            }
            if !bridgingLines.isEmpty {
                return true
            }
        }

        // 2. Check if a solid graphic/photo/chart block bridges across `cutX` in pixel space
        // Use a photo-aware threshold so mid-tone/bright areas of color photographs are not mistaken for white paper gutters
        let photoThreshold = UInt8(min(228, Int(threshold) + (255 - Int(threshold)) * 3 / 4))
        let stripHalfW: CGFloat = 6.0
        let stripRect = CGRect(
            x: max(rect.minX, cutX - stripHalfW),
            y: rect.minY,
            width: stripHalfW * 2.0,
            height: rect.height
        )
        let stripProj = pixelBuffer.horizontalProjection(in: stripRect, threshold: photoThreshold)
        guard stripProj.count > 60 else { return false }

        // Slide a 110px window along the gutter strip; if >= 70% of rows in any 110px window have non-paper pixels,
        // a spanning photo/figure/chart crosses `cutX`.
        let winSize = min(110, stripProj.count / 2)
        guard winSize >= 45 else { return false }
        var inkRowsInWin = 0
        for y in 0..<winSize {
            if stripProj[y] >= 3 { inkRowsInWin += 1 }
        }
        if Double(inkRowsInWin) / Double(winSize) >= 0.70 { return true }

        for y in winSize..<stripProj.count {
            if stripProj[y] >= 3 { inkRowsInWin += 1 }
            if stripProj[y - winSize] >= 3 { inkRowsInWin -= 1 }
            if Double(inkRowsInWin) / Double(winSize) >= 0.70 {
                return true
            }
        }

        return false
    }

    /// Finds the optimal horizontal split coordinate `splitY` inside `rect` that separates a spanning block
    /// (title banner, full-width photo, 2-column chart/table) from a multi-column text region.
    private static func findBestHorizontalSplitY(
        in rect: CGRect,
        fullPageWidth: CGFloat,
        pixelBuffer: PixelBuffer,
        threshold: UInt8,
        visionAnalysis: VisionPageAnalysis?
    ) -> CGFloat? {
        // Inset horizontally by 4% when measuring horizontal whitespace gaps so vertical divider rules
        // or adjacent sidebar box borders along the left/right gutter edges do not mask horizontal gaps.
        let hInset = min(48.0, rect.width * 0.045)
        let innerHRect = CGRect(
            x: rect.minX + hInset,
            y: rect.minY,
            width: max(20.0, rect.width - hInset * 2.0),
            height: rect.height
        )
        let horizProj = pixelBuffer.horizontalProjection(in: innerHRect, threshold: threshold)
        let h = horizProj.count
        let minEdgeDist = max(45, Int(Double(pixelBuffer.height) * 0.022))
        let minGapH = max(4, Int(Double(pixelBuffer.height) * 0.0018))
        guard h >= minEdgeDist * 2 + 40 else { return nil }

        let noiseLimit = max(4, Int(innerHRect.width * 0.008))

        // Find candidate macro horizontal whitespace gaps scaled proportionally to page height
        var gaps: [(startY: Int, endY: Int, height: Int, midY: Int)] = []
        var inGap = false
        var gapStart = minEdgeDist

        for y in minEdgeDist..<(h - minEdgeDist) {
            if horizProj[y] <= noiseLimit {
                if !inGap {
                    inGap = true
                    gapStart = y
                }
            } else {
                if inGap {
                    inGap = false
                    let gh = y - gapStart
                    if gh >= minGapH {
                        gaps.append((startY: gapStart, endY: y - 1, height: gh, midY: (gapStart + y - 1) / 2))
                    }
                }
            }
        }
        if inGap {
            let gh = (h - minEdgeDist) - gapStart
            if gh >= minGapH {
                gaps.append((startY: gapStart, endY: h - minEdgeDist - 1, height: gh, midY: (gapStart + h - minEdgeDist - 1) / 2))
            }
        }

        // Sort candidate gaps by gap height descending, and spatially deduplicate (at least 16px apart)
        // so whitespace bands inside a chart don't wipe out an adjacent boundary gap just outside the chart.
        var sortedGaps: [(startY: Int, endY: Int, height: Int, midY: Int)] = []
        for g in gaps.sorted(by: { $0.height > $1.height }) {
            let tooClose = sortedGaps.contains { abs($0.midY - g.midY) < 16 }
            if !tooClose {
                sortedGaps.append(g)
                if sortedGaps.count >= 26 { break }
            }
        }

        // Also inject high-priority transition Y coordinates from visionAnalysis where narrow multi-column
        // text lines (width < 48% of rect.width) start or end inside `rect`.
        if let vision = visionAnalysis {
            let narrowLines = vision.lines.filter { l in
                l.rect.minX >= rect.minX - 10 &&
                l.rect.maxX <= rect.maxX + 10 &&
                l.rect.minY >= rect.minY + 10 &&
                l.rect.maxY <= rect.maxY - 10 &&
                l.rect.width >= rect.width * 0.20 &&
                l.rect.width <= rect.width * 0.48 &&
                l.text.count >= 15
            }.sorted { $0.rect.minY < $1.rect.minY }

            if narrowLines.count >= 4 {
                // Group narrow prose lines into contiguous vertical bands (gap < 24px)
                var bands: [(minY: CGFloat, maxY: CGFloat, count: Int)] = []
                for l in narrowLines {
                    if let last = bands.last, l.rect.minY - last.maxY < 24.0 {
                        bands[bands.count - 1] = (minY: min(last.minY, l.rect.minY), maxY: max(last.maxY, l.rect.maxY), count: last.count + 1)
                    } else {
                        bands.append((minY: l.rect.minY, maxY: l.rect.maxY, count: 1))
                    }
                }
                for b in bands where b.count >= 4 {
                    let candidatesY = [
                        Int(round((b.minY - 4.0) - rect.minY)),
                        Int(round((b.minY + 26.0) - rect.minY)),
                        Int(round((b.maxY - 26.0) - rect.minY)),
                        Int(round((b.maxY + 4.0) - rect.minY))
                    ]
                    for relY in candidatesY {
                        if relY >= minEdgeDist && relY <= h - minEdgeDist {
                            if !sortedGaps.contains(where: { abs($0.midY - relY) < 10 }) {
                                sortedGaps.insert((startY: relY - 2, endY: relY + 2, height: 10, midY: relY), at: 0)
                            }
                        }
                    }
                }
            }
        }

        for gap in sortedGaps {
            let splitY = rect.minY + CGFloat(gap.midY)
            let topRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: splitY - rect.minY)
            let botRect = CGRect(x: rect.minX, y: splitY, width: rect.width, height: rect.maxY - splitY)
            guard topRect.height >= CGFloat(minEdgeDist), botRect.height >= CGFloat(minEdgeDist) else { continue }

            let topCols = detectNonSpanningColumns(
                in: topRect,
                fullPageWidth: fullPageWidth,
                pixelBuffer: pixelBuffer,
                threshold: threshold,
                visionAnalysis: visionAnalysis
            )
            let botCols = detectNonSpanningColumns(
                in: botRect,
                fullPageWidth: fullPageWidth,
                pixelBuffer: pixelBuffer,
                threshold: threshold,
                visionAnalysis: visionAnalysis
            )

            // If splitting at `splitY` unlocks multi-column structure on either side, return `splitY`!
            if topCols.count >= 2 || botCols.count >= 2 {
                return splitY
            }
        }

        // 2-step lookahead: Handle pages where a multi-column text band is sandwiched between a top spanning
        // headline/deck and a middle/bottom spanning photo or chart (between gap1 and gap2).
        let orderedByY = sortedGaps.sorted { $0.midY < $1.midY }
        if orderedByY.count >= 2 {
            for i in 0..<(orderedByY.count - 1) {
                for j in (i + 1)..<orderedByY.count {
                    let y1 = rect.minY + CGFloat(orderedByY[i].midY)
                    let y2 = rect.minY + CGFloat(orderedByY[j].midY)
                    guard y2 - y1 >= CGFloat(minEdgeDist) else { continue }
                    let midRect = CGRect(x: rect.minX, y: y1, width: rect.width, height: y2 - y1)
                    let midCols = detectNonSpanningColumns(
                        in: midRect,
                        fullPageWidth: fullPageWidth,
                        pixelBuffer: pixelBuffer,
                        threshold: threshold,
                        visionAnalysis: visionAnalysis
                    )
                    if midCols.count >= 2 {
                        return y1
                    }
                }
            }
        }

        return nil
    }
}
