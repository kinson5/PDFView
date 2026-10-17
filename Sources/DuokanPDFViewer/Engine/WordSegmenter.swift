import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct WordSegmenter {
    /// Segments a text line slice into character/word slices
    public static func segmentWords(
        pixelBuffer: PixelBuffer,
        originalImage: CGImage,
        sliceRect: CGRect,
        threshold: UInt8,
        visualThreshold: UInt8? = nil,
        config: ReflowConfig
    ) -> [WordSlice] {
        let vertProj = pixelBuffer.verticalProjection(in: sliceRect, threshold: threshold)
        let width = vertProj.count
        guard width > 10 else { return [] }

        // Detect any ink column in this line (preserve thin 1-2px horizontal strokes in SongTi/FangSong like "下", "一", "—")
        let noiseLimit = max(0, Int(sliceRect.height * 0.015))

        // Find ink intervals (characters / glyphs)
        var rawIntervals: [(startX: Int, endX: Int)] = []
        var inInk = false
        var startX = 0

        for x in 0..<width {
            if vertProj[x] > noiseLimit {
                if !inInk {
                    inInk = true
                    startX = x
                }
            } else {
                if inInk {
                    inInk = false
                    rawIntervals.append((startX: startX, endX: x - 1))
                }
            }
        }
        if inInk {
            rawIntervals.append((startX: startX, endX: width - 1))
        }

        // Expand interval edges to include 1px thin stroke tips ("下", "一") and filter out isolated 1-2px dust specks
        let minSpeckInk = max(3, Int(sliceRect.height * 0.08))
        var intervals: [(startX: Int, endX: Int)] = []
        for (idx, iv) in rawIntervals.enumerated() {
            var sX = iv.startX
            var eX = iv.endX
            let leftBound = idx > 0 ? (rawIntervals[idx - 1].endX + 2) : 0
            let rightBound = (idx + 1 < rawIntervals.count) ? (rawIntervals[idx + 1].startX - 2) : (width - 1)
            while sX > leftBound && vertProj[sX - 1] >= 1 { sX -= 1 }
            while eX < rightBound && vertProj[eX + 1] >= 1 { eX += 1 }

            guard sX <= eX, sX >= 0, eX < vertProj.count else { continue }
            let spanW = eX - sX + 1
            let totalInk = (sX...eX).reduce(0) { $0 + vertProj[$1] }
            if spanW <= 2 && totalInk < minSpeckInk {
                continue
            }
            intervals.append((startX: sX, endX: eX))
        }

        if intervals.isEmpty { return [] }

        // Merge components that belong to the same glyph (e.g. left-right radicals in Chinese, like "仁", "体", "明", "州", or double quotes “ ”)
        var merged: [(startX: Int, endX: Int)] = []
        var current = intervals[0]

        // Dynamic radical gap tolerance based on line height (typical scanned text 2-8 pixels)
        // Chinese characters typically have radicals separated by up to 0.16 * line height,
        // and standard CJK glyphs have an overall width up to 1.15 * line height.
        let maxRadicalGap = max(4, Int(sliceRect.height * 0.16))
        let maxDoubleQuoteGap = max(5, Int(sliceRect.height * 0.18))
        let maxGlyphWidth = Int(sliceRect.height * 1.25)

        for i in 1..<intervals.count {
            let next = intervals[i]
            let gap = next.startX - current.endX
            let curWidth = current.endX - current.startX + 1
            let nextWidth = next.endX - next.startX + 1
            let combinedWidth = curWidth + gap + nextWidth

            // Merge if gap is small and combined width is within a standard glyph width,
            // or if the next/current component is narrow (like a radical "亻", "氵", "日", "月", or double quote ticks “ ”),
            // or if two sub-components form a standard CJK character width (e.g. "州" with multiple vertical strokes)
            let isNarrowRadical = nextWidth <= max(4, Int(sliceRect.height * 0.35))
            let isCurrentNarrow = curWidth <= max(4, Int(sliceRect.height * 0.35))
            let isDoubleQuotePair = isCurrentNarrow && isNarrowRadical &&
                gap <= maxDoubleQuoteGap &&
                combinedWidth <= Int(sliceRect.height * 0.52)
            let isCjkComponentPair = (isNarrowRadical || isCurrentNarrow) &&
                gap <= maxRadicalGap &&
                combinedWidth <= maxGlyphWidth

            if (gap <= maxRadicalGap && combinedWidth <= maxGlyphWidth) ||
               isCjkComponentPair ||
               isDoubleQuotePair {
                current = (startX: current.startX, endX: next.endX)
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)

        var words: [WordSlice] = []

        for (idx, interval) in merged.enumerated() {
            let glyphWidth = interval.endX - interval.startX + 1
            if glyphWidth < 2 { continue }

            // Preserve natural leading/trailing whitespace for fullwidth Chinese punctuation (，。、：；“”（）)
            // while keeping tight ASCII punctuation (e.g. decimal point in "60.92%") compact
            var cropStartX = CGFloat(interval.startX)
            var cropEndX = CGFloat(interval.endX + 1)
            let isNarrowPunct = glyphWidth <= max(4, Int(sliceRect.height * 0.38))
            if isNarrowPunct {
                let leadingGap = idx > 0 ? (interval.startX - merged[idx - 1].endX - 1) : 0
                let trailingGap = (idx + 1 < merged.count) ? (merged[idx + 1].startX - interval.endX - 1) : Int(sliceRect.height * 0.28)
                let fullwidthGapThreshold = max(4, Int(sliceRect.height * 0.18))

                if trailingGap >= fullwidthGapThreshold {
                    let extraRight = min(CGFloat(trailingGap) * 0.60, sliceRect.height * 0.26)
                    cropEndX = min(CGFloat(width), cropEndX + extraRight)
                } else if leadingGap >= fullwidthGapThreshold {
                    let extraLeft = min(CGFloat(leadingGap) * 0.60, sliceRect.height * 0.26)
                    cropStartX = max(0, cropStartX - extraLeft)
                }
            }

            // Always preserve the full horizontal line height (sliceRect.minY .. sliceRect.maxY)
            // so bottom-baseline punctuation (，。、.) stays at the bottom and top quotes (“”) stay at the top!
            let charRect = CGRect(
                x: sliceRect.minX + cropStartX,
                y: sliceRect.minY,
                width: max(2.0, cropEndX - cropStartX),
                height: sliceRect.height
            )

            guard let cropped = ImageEnhancer.crop(image: originalImage, to: charRect) else {
                continue
            }

            let enhanced = ImageEnhancer.enhance(
                image: cropped,
                mode: config.binarizationMode,
                threshold: visualThreshold ?? threshold,
                config: config,
                isGraphic: false
            )

            let nsImage = NSImage(
                cgImage: enhanced,
                size: NSSize(width: charRect.width, height: charRect.height)
            )

            words.append(WordSlice(originalRect: charRect, image: nsImage))
        }

        return words
    }

    /// Clusters lines of a column into semantic paragraphs for fluid reflowing
    /// Eliminates unnecessary line breaks and preserves full paragraph continuity,
    /// enhanced with Apple Vision neural text semantic analysis
    public static func clusterIntoParagraphs(
        slices: [PageSlice],
        columnIndex: Int,
        columnRect: CGRect,
        visionAnalysis: VisionPageAnalysis? = nil,
        config: ReflowConfig = ReflowConfig(),
        zoneType: PageZoneType = .body,
        globalBodyHeight: CGFloat? = nil,
        pageHeight: CGFloat? = nil
    ) -> [ParagraphBlock] {
        if slices.isEmpty { return [] }

        // 0. Compute baseline body margins and median line gap for this column
        let textSlices = slices.filter { !$0.isFigure && !$0.isTable && !$0.isSideBySide && !$0.words.isEmpty }

        // Find median line height of text slices (use global page body height when provided for cross-column consistency)
        let sliceHeights = textSlices.map { $0.originalRect.height }.sorted()
        let localMedianHeight: CGFloat = !sliceHeights.isEmpty ? sliceHeights[sliceHeights.count / 2] : 30.0
        let medianRawBodyHeight: CGFloat = globalBodyHeight ?? localMedianHeight
        let effectivePageHeight: CGFloat = pageHeight ?? columnRect.maxY

        // Find baseline left margin: collect minX of first word across all text slices
        let leftPositions = textSlices.compactMap { $0.words.first?.originalRect.minX }.sorted()
        let baselineLeft: CGFloat
        if !leftPositions.isEmpty {
            let p15Index = max(0, min(leftPositions.count - 1, Int(Double(leftPositions.count) * 0.15)))
            baselineLeft = leftPositions[p15Index]
        } else {
            baselineLeft = columnRect.minX
        }

        // Find baseline right margin: collect maxX of last word across all text slices
        let rightPositions = textSlices.compactMap { $0.words.last?.originalRect.maxX }.sorted()
        let baselineRight: CGFloat
        if !rightPositions.isEmpty {
            let p85Index = max(0, min(rightPositions.count - 1, Int(Double(rightPositions.count) * 0.85)))
            baselineRight = rightPositions[p85Index]
        } else {
            baselineRight = columnRect.maxX
        }

        let fullLineWidth = max(100.0, baselineRight - baselineLeft)

        // Find median line spacing (vertical distance between consecutive slices)
        var lineGaps: [CGFloat] = []
        if slices.count >= 2 {
            for j in 0..<(slices.count - 1) {
                let g = slices[j + 1].originalRect.minY - slices[j].originalRect.maxY
                if g >= 0 && g < 150 {
                    lineGaps.append(g)
                }
            }
        }
        lineGaps.sort()
        let medianGap = lineGaps.isEmpty ? 20.0 : lineGaps[lineGaps.count / 2]

        var paragraphs: [ParagraphBlock] = []
        var i = 0

        while i < slices.count {
            let slice = slices[i]

            // 1. Table Block: Preserved 100% intact as a whole table
            if slice.isTable {
                paragraphs.append(ParagraphBlock(
                    paragraphIndex: paragraphs.count,
                    columnIndex: columnIndex,
                    isFigure: true,
                    isTable: true,
                    figureSlice: slice,
                    baseLineHeight: slice.originalRect.height
                ))
                i += 1
                continue
            }

            // 2. Side-by-Side Coexistence (Text and Image in the same horizontal band)
            if slice.isSideBySide {
                var sideSlices: [PageSlice] = []
                while i < slices.count && slices[i].isSideBySide {
                    sideSlices.append(slices[i])
                    i += 1
                }

                let figSlice = sideSlices.first { $0.isFigure }
                let textSlices = sideSlices.filter { !$0.isFigure }
                let textWords = textSlices.flatMap { $0.words }
                let rawBaseH = textSlices.first?.originalRect.height ?? 30.0
                let sideText = textSlices.compactMap { $0.recognizedText }.joined(separator: " ")
                let normalizedSideH: CGFloat = config.standardBodyLineHeight > 0 ? config.standardBodyLineHeight : rawBaseH

                let figureOnRight: Bool
                if let fig = figSlice, let txt = textSlices.first {
                    figureOnRight = fig.originalRect.minX > txt.originalRect.minX
                } else {
                    figureOnRight = true
                }

                paragraphs.append(ParagraphBlock(
                    paragraphIndex: paragraphs.count,
                    columnIndex: columnIndex,
                    hasIndent: false,
                    isFigure: false,
                    isTable: false,
                    isSideBySide: true,
                    figureOnRight: figureOnRight,
                    figureSlice: nil,
                    sideFigure: figSlice,
                    words: textWords,
                    baseLineHeight: normalizedSideH,
                    recognizedText: sideText.isEmpty ? nil : sideText
                ))
                continue
            }

            // 3. Standalone Figure / Diagram: Preserved 100% intact
            if slice.isFigure {
                paragraphs.append(ParagraphBlock(
                    paragraphIndex: paragraphs.count,
                    columnIndex: columnIndex,
                    isFigure: true,
                    isTable: false,
                    figureSlice: slice,
                    baseLineHeight: slice.originalRect.height
                ))
                i += 1
                continue
            }

            // 4. Regular Text Paragraph: Merge consecutive lines into a unified paragraph stream
            var currentWords: [WordSlice] = []
            var currentHeights: [CGFloat] = []
            var currentTexts: [String] = []
            let baseH = slice.originalRect.height

            // Detect paragraph first-line indent relative to baseline body left margin
            let firstWordMinX = slice.words.first?.originalRect.minX ?? slice.originalRect.minX
            let firstLineIndent = firstWordMinX - baselineLeft
            let currentHasIndent = firstLineIndent >= (baseH * 1.1)

            // Detect if this line has large font (Title/Heading) relative to document body height
            let titleHeightThreshold = max(38.0, medianRawBodyHeight * 1.28)
            let isLargeTitle = slice.originalRect.height >= titleHeightThreshold

            while i < slices.count && !slices[i].isFigure && !slices[i].isTable && !slices[i].isSideBySide {
                let curSlice = slices[i]
                currentWords.append(contentsOf: curSlice.words)
                currentHeights.append(curSlice.originalRect.height)
                if let t = curSlice.recognizedText, !t.isEmpty {
                    currentTexts.append(t)
                }

                let nextIndex = i + 1
                var isEndOfParagraph = false

                if nextIndex >= slices.count {
                    // Reached end of column
                    isEndOfParagraph = true
                } else {
                    let nextSlice = slices[nextIndex]
                    if nextSlice.isFigure || nextSlice.isTable || nextSlice.isSideBySide {
                        // Next element is a visual graphic block
                        isEndOfParagraph = true
                    } else if isLargeTitle && nextSlice.originalRect.height >= titleHeightThreshold {
                        // Multi-line title: consecutive large-font lines belong to the same title
                        isEndOfParagraph = false
                    } else if isLargeTitle && nextSlice.originalRect.height < titleHeightThreshold {
                        // Transition from title to body/deck text: title ends here
                        isEndOfParagraph = true
                    } else if !isLargeTitle && nextSlice.originalRect.height >= titleHeightThreshold {
                        // Next line is a large title: current paragraph ends here
                        isEndOfParagraph = true
                    } else {
                        // Semantic Punctuation & Heading Analysis via Apple Vision / Native PDF Text Layer
                        let curText = curSlice.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let nextText = nextSlice.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let hasVision = !curText.isEmpty && !nextText.isEmpty

                        if hasVision {
                            let curStartsHeading = RecognizedTextLine.isHeadingPrefix(curText)
                            let nextStartsHeading = RecognizedTextLine.isHeadingPrefix(nextText)

                            // Check magazine bylines ("文/周浩", "编辑/...")
                            let isCurByline = curText.count <= 28 && (curText.hasPrefix("文/") || curText.hasPrefix("文｜") || curText.hasPrefix("本刊记者") || curText.hasPrefix("编辑/"))
                            let isNextByline = nextText.count <= 28 && (nextText.hasPrefix("文/") || nextText.hasPrefix("文｜") || nextText.hasPrefix("本刊记者") || nextText.hasPrefix("编辑/"))

                            // Check sentence termination (CJK + English)
                            let endsWithEnglishPeriod: Bool = {
                                if curText.hasSuffix(".”") || curText.hasSuffix(".\"") || curText.hasSuffix(".’") || curText.hasSuffix(".'") {
                                    return true
                                }
                                guard curText.hasSuffix(".") else { return false }
                                let withoutDot = curText.dropLast()
                                if let lastChar = withoutDot.last, lastChar.isUppercase {
                                    return false
                                }
                                return true
                            }()
                            let curEndsTerminator = (curText.last.map { ["。", "！", "？", "!", "?", "；", ";", "”", "」", "》"].contains($0) } ?? false) || endsWithEnglishPeriod
                            let curEndsColon = curText.hasSuffix("：") || curText.hasSuffix(":")
                            let curEndsContinuation = curText.last.map { ["，", ",", "、", "—", "-", "~"].contains($0) } ?? false

                            // Check footnote markers
                            let curStartsFootnote = isFootnoteMarker(curText)
                            let nextStartsFootnote = isFootnoteMarker(nextText)

                            let rightGap = baselineRight - (curSlice.words.last?.originalRect.maxX ?? curSlice.originalRect.maxX)
                            let isShortLine = rightGap >= max(65.0, fullLineWidth * 0.16)
                            let vGap = nextSlice.originalRect.minY - curSlice.originalRect.maxY
                            let isHugeVerticalGap = vGap >= max(medianGap * 1.75, 42.0)

                            // Check if current line is an unindented standalone subheading (e.g. "港交所下一步：打造多元资产生态圈", "外部：最紧阶段过去")
                            let curFirstMinX = curSlice.words.first?.originalRect.minX ?? curSlice.originalRect.minX
                            let curIsUnindented = (curFirstMinX - baselineLeft) < (curSlice.originalRect.height * 0.85)
                            let nextFirstMinX = nextSlice.words.first?.originalRect.minX ?? nextSlice.originalRect.minX
                            let isCjkLine = curText.range(of: "\\p{Han}", options: .regularExpression) != nil
                            let indentRatio: CGFloat = isCjkLine ? 0.90 : 0.65
                            let nextHasIndent = (nextFirstMinX - baselineLeft) >= max(10.0, nextSlice.originalRect.height * indentRatio)
                            let isStandaloneSubheading = currentHeights.count == 1
                                && curIsUnindented
                                && (isShortLine || nextHasIndent)
                                && curText.count >= 4 && curText.count <= 22
                                && !curEndsTerminator && !curEndsContinuation
                                && !curText.hasPrefix("图/") && !curText.hasPrefix("资料来源")

                            if nextStartsFootnote || isCurByline || isNextByline || isStandaloneSubheading {
                                isEndOfParagraph = true
                            } else if curStartsFootnote && (curEndsTerminator || isShortLine) {
                                isEndOfParagraph = true
                            } else if curStartsHeading && (isShortLine || curEndsColon || curEndsTerminator) {
                                isEndOfParagraph = true
                            } else if curEndsColon {
                                isEndOfParagraph = true
                            } else if nextStartsHeading && (curEndsTerminator || isShortLine || vGap >= medianGap * 1.25) {
                                // Only break for a new heading if the current line isn't in the middle of an unpunctuated sentence
                                isEndOfParagraph = true
                            } else if isHugeVerticalGap {
                                isEndOfParagraph = true
                            } else if curEndsContinuation {
                                isEndOfParagraph = false
                            } else if curEndsTerminator {
                                let hasParagraphGap = vGap >= max(medianGap * 1.45, medianGap + 14.0)

                                if nextHasIndent || hasParagraphGap || isShortLine {
                                    isEndOfParagraph = true
                                }
                            } else {
                                // Check if next line has a strong first-line indent AND a paragraph vertical gap
                                let nextIndent = nextFirstMinX - baselineLeft
                                let nextHasStrongIndent = nextIndent >= (nextSlice.originalRect.height * 1.45)
                                if nextHasStrongIndent && (isShortLine || vGap >= medianGap * 1.35) {
                                    isEndOfParagraph = true
                                } else {
                                    isEndOfParagraph = false
                                }
                            }
                        } else {
                            // Fallback to geometric cues when Vision OCR text is unavailable
                            let nextFirstMinX = nextSlice.words.first?.originalRect.minX ?? nextSlice.originalRect.minX
                            let nextIndent = nextFirstMinX - baselineLeft
                            let nextHasIndent = nextIndent >= (nextSlice.originalRect.height * 1.1)

                            let vGap = nextSlice.originalRect.minY - curSlice.originalRect.maxY
                            let hasParagraphGap = vGap >= max(medianGap * 1.6, medianGap + 20.0)

                            let lastWordMaxX = curSlice.words.last?.originalRect.maxX ?? curSlice.originalRect.maxX
                            let rightGap = baselineRight - lastWordMaxX
                            let isShortLine = rightGap >= max(80.0, fullLineWidth * 0.20)

                            if nextHasIndent || hasParagraphGap || isShortLine {
                                isEndOfParagraph = true
                            }
                        }
                    }
                }

                i += 1
                if isEndOfParagraph {
                    break
                }
            }

            if !currentWords.isEmpty {
                let avgH = currentHeights.reduce(0, +) / CGFloat(max(1, currentHeights.count))
                let assembledText = PDFTextLayerAnalyzer.joinLinesIntoParagraph(currentTexts)

                let pMinX = currentWords.map { $0.originalRect.minX }.min() ?? columnRect.minX
                let pMaxX = currentWords.map { $0.originalRect.maxX }.max() ?? columnRect.maxX
                let pMinY = currentWords.map { $0.originalRect.minY }.min() ?? columnRect.minY
                let pMaxY = currentWords.map { $0.originalRect.maxY }.max() ?? columnRect.maxY
                let paraRect = CGRect(x: pMinX, y: pMinY, width: max(1.0, pMaxX - pMinX), height: max(1.0, pMaxY - pMinY))

                // Check if this short paragraph sits immediately below a standalone photo/figure (Magazine photo caption)
                let followsPhoto = (paragraphs.last?.isFigure == true && paragraphs.last?.isTable == false)
                let isPhotoCaptionAfterFigure = followsPhoto &&
                    currentHeights.count <= 3 &&
                    assembledText.count <= 95 &&
                    (!currentHasIndent || assembledText.contains("图/") || assembledText.contains("摄/") || assembledText.hasPrefix("202"))

                // Check if this is an unindented standalone magazine section subheading
                let endsWithBodyPunct = assembledText.last.map { ["。", "，", "、", "；", "！", "”", "）", ")", "%", "％"].contains($0) } ?? false
                let isUnindentedSubheading = currentHeights.count == 1
                    && !currentHasIndent
                    && paraRect.width <= fullLineWidth * 0.96
                    && assembledText.count >= 4 && assembledText.count <= 22
                    && !endsWithBodyPunct
                    && !assembledText.hasPrefix("图/") && !assembledText.hasPrefix("资料来源") && !assembledText.hasPrefix("数据来源")

                // Semantic Level Classification
                let semanticLevel: SemanticLevel
                switch zoneType {
                case .header:
                    semanticLevel = .header
                case .footer:
                    semanticLevel = .footer
                case .footnote:
                    let trimmed = assembledText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.range(of: "^(注\\s*释|脚\\s*注|附\\s*注|Notes?|Footnotes?)$", options: .regularExpression) != nil {
                        semanticLevel = .subHeader
                    } else {
                        semanticLevel = .caption
                    }
                case .body, .figure, .table:
                    if isPhotoCaptionAfterFigure {
                        semanticLevel = .caption
                    } else if config.enableSemanticScaling {
                        if let vision = visionAnalysis {
                            let baseLevel = vision.classifySemanticLevel(
                                text: assembledText,
                                lineHeight: avgH,
                                medianBodyHeight: medianRawBodyHeight,
                                isEarlyInDoc: paragraphs.count <= 3,
                                rect: paraRect,
                                pageHeight: effectivePageHeight
                            )
                            if baseLevel == .body && isUnindentedSubheading {
                                semanticLevel = .sectionHeader
                            } else {
                                semanticLevel = baseLevel
                            }
                        } else {
                            let isPageNumber = assembledText.range(of: "^([—\\-~–]?\\s*[0-9一二三四五六七八九十]+\\s*[—\\-~–]?|第\\s*[0-9]+\\s*页(\\s*[/共]\\s*[0-9]+\\s*页)?|\\s*[0-9]+\\s*)$", options: .regularExpression) != nil
                            if isPageNumber || (paraRect.minY >= effectivePageHeight * 0.925 && assembledText.count <= 12) {
                                semanticLevel = .footer
                            } else if paraRect.maxY <= columnRect.minY + (columnRect.height * 0.12) && assembledText.count <= 35 && avgH <= medianRawBodyHeight * 1.15 {
                                semanticLevel = .header
                            } else if isFootnoteMarker(assembledText) || assembledText.hasPrefix("注：") || assembledText.hasPrefix("注:") || assembledText.hasPrefix("说明：") || assembledText.hasPrefix("*") {
                                semanticLevel = .caption
                            } else if (isLargeTitle || avgH >= titleHeightThreshold) && assembledText.count <= 42 {
                                semanticLevel = .title
                            } else if assembledText.count <= 42 && assembledText.range(of: "^([一二三四五六七八九十]+[、.．]|第[0-9一二三四五六七八九十]+[章节篇]|【)", options: .regularExpression) != nil {
                                semanticLevel = .sectionHeader
                            } else if RecognizedTextLine.isHeadingPrefix(assembledText) || isUnindentedSubheading {
                                semanticLevel = .subHeader
                            } else if (assembledText.hasSuffix("：") || assembledText.hasSuffix(":")) && assembledText.count <= 18 {
                                semanticLevel = .salutation
                            } else {
                                semanticLevel = .body
                            }
                        }
                    } else {
                        semanticLevel = ((isLargeTitle || avgH >= titleHeightThreshold) && assembledText.count <= 42) ? .title : .body
                    }
                }

                let isTitleBlock = (semanticLevel == .title)

                // Standardize Body Text & Heading Typography across all columns and zones of the page:
                // Every body paragraph renders at exactly `config.standardBodyLineHeight` (26.0 pt),
                // and every title/heading scales deterministically by `semanticLevel.scaleRatio`.
                let normalizedLineHeight: CGFloat
                if config.standardBodyLineHeight > 0 {
                    let standardBase = config.standardBodyLineHeight
                    if config.enableSemanticScaling {
                        normalizedLineHeight = standardBase * semanticLevel.scaleRatio
                    } else {
                        normalizedLineHeight = isTitleBlock ? (standardBase * SemanticLevel.title.scaleRatio) : standardBase
                    }
                } else {
                    normalizedLineHeight = avgH
                }

                let noIndentLevels: [SemanticLevel] = [.title, .sectionHeader, .subHeader, .salutation, .header, .footer, .caption]
                let shouldIndent = noIndentLevels.contains(semanticLevel) ? false : currentHasIndent

                paragraphs.append(ParagraphBlock(
                    paragraphIndex: paragraphs.count,
                    columnIndex: columnIndex,
                    hasIndent: shouldIndent,
                    isTitle: isTitleBlock,
                    semanticLevel: semanticLevel,
                    words: currentWords,
                    baseLineHeight: normalizedLineHeight,
                    recognizedText: assembledText.isEmpty ? nil : assembledText
                ))
            }
        }

        return paragraphs
    }

    /// Checks if a string starts with a footnote marker (e.g. ①-⑳, [1], (1), 注：, etc.)
    public static func isFootnoteMarker(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("注：") || trimmed.hasPrefix("注:") || trimmed.hasPrefix("说明：") || trimmed.hasPrefix("说明:") || trimmed.hasPrefix("*") || trimmed.hasPrefix("※") {
            return true
        }
        if let first = trimmed.first {
            let s = String(first)
            if (s >= "\u{2460}" && s <= "\u{2473}") || (s >= "\u{3251}" && s <= "\u{32BF}") {
                return true
            }
        }
        let footnotePattern = "^([①-⑳㉑-㉟]|[(（\\[【][0-9]+[)）\\]】][.．、]?|\\*+)"
        return trimmed.range(of: footnotePattern, options: .regularExpression) != nil
    }
}
