import Foundation
import CoreGraphics
import PDFKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Identifies the underlying text source type of a PDFPage
public enum PDFTextSourceType: String, CaseIterable, Identifiable, Codable, Sendable {
    case nativeVectorText = "原生矢量文字"
    case ocrRecognizedText = "已识别文字版"
    case embeddedOCRLayer = "双层PDF文字层"
    case scannedImage = "纯图像扫描件"

    public var id: String { rawValue }

    public var badgeIcon: String {
        switch self {
        case .nativeVectorText: return "sparkles.rectangle.stack"
        case .ocrRecognizedText: return "character.textbox"
        case .embeddedOCRLayer: return "doc.text.Viewfinder"
        case .scannedImage: return "photo.artframe"
        }
    }
}

/// Controls how text paragraphs are rendered in ReflowPageView ("智能重排")
public enum TextReflowRenderMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "智能判定 (原生文字直提 / 扫描件切片)"
    case vectorText = "矢量文字重排 (零失真放大)"
    case imageSlices = "原版字形切片 (保留原书字形)"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .auto: return "智能自适应"
        case .vectorText: return "矢量文字重排"
        case .imageSlices: return "原版字形切片"
        }
    }
}

/// Result of analyzing a PDFPage's native text layer and PDF operator stream
public struct PDFTextLayerAnalysisResult: Sendable {
    public let sourceType: PDFTextSourceType
    public let visionAnalysis: VisionPageAnalysis?
    public let rawLineCount: Int
    public let totalCharacterCount: Int

    public init(
        sourceType: PDFTextSourceType,
        visionAnalysis: VisionPageAnalysis?,
        rawLineCount: Int = 0,
        totalCharacterCount: Int = 0
    ) {
        self.sourceType = sourceType
        self.visionAnalysis = visionAnalysis
        self.rawLineCount = rawLineCount
        self.totalCharacterCount = totalCharacterCount
    }
}

/// Inspects a PDFPage's CGPDFContentStream and PDFKit selection layer to determine
/// whether the page contains native vector text, an invisible OCR text layer, or a pure scanned image,
/// and directly extracts structured line geometry & text without OCR distortion.
public struct PDFTextLayerAnalyzer {

    private final class StreamInspectionState {
        var textRenderModes: Set<Int> = []
        var currentRenderMode: Int = 0
        var visibleTextShowOps: Int = 0
        var invisibleTextShowOps: Int = 0
        var imageDoOps: Int = 0
    }

    /// Analyzes a PDFPage and extracts its native text lines mapped to the target pixel space
    public static func analyze(
        page: PDFPage,
        pixelWidth: Int,
        pixelHeight: Int,
        cgImage: CGImage? = nil
    ) -> PDFTextLayerAnalysisResult {
        let cropBox = page.bounds(for: .cropBox)
        let rot = ((page.rotation % 360) + 360) % 360
        let isRotated = (rot == 90 || rot == 270)
        let logicalWidth = isRotated ? cropBox.height : cropBox.width
        let logicalHeight = isRotated ? cropBox.width : cropBox.height

        guard cropBox.width > 10, cropBox.height > 10,
              pixelWidth > 10, pixelHeight > 10 else {
            return PDFTextLayerAnalysisResult(sourceType: .scannedImage, visionAnalysis: nil)
        }

        // 1. Inspect low-level PDF operator stream via CGPDFScanner (< 0.5ms)
        let streamState = inspectContentStream(page: page)

        // 2. Check if PDFKit has selectable text on this page
        let rawPageString = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawPageString.count < 6 && streamState.visibleTextShowOps == 0 && streamState.invisibleTextShowOps == 0 {
            return PDFTextLayerAnalysisResult(sourceType: .scannedImage, visionAnalysis: nil)
        }

        guard let fullSelection = page.selection(for: cropBox) else {
            return PDFTextLayerAnalysisResult(sourceType: .scannedImage, visionAnalysis: nil)
        }

        let rawLineSelections = fullSelection.selectionsByLine()
        if rawLineSelections.isEmpty {
            return PDFTextLayerAnalysisResult(sourceType: .scannedImage, visionAnalysis: nil)
        }

        let scaleX = CGFloat(pixelWidth) / logicalWidth
        let scaleY = CGFloat(pixelHeight) / logicalHeight

        let resolvedCGImage = cgImage ?? ReflowEngine.renderPageToCGImage(page: page, dpi: CGFloat(pixelWidth) / logicalWidth * 72.0)
        let pixelBuffer = resolvedCGImage.flatMap { PixelBuffer(cgImage: $0) }

        // PDFKit's selectionsByLine() often merges two or three columns on the same horizontal baseline
        // into a single PDFSelection. Split any selection that crosses a vertical whitespace column gutter!
        var lineSelections: [PDFSelection] = []
        for rawSel in rawLineSelections {
            if let pb = pixelBuffer {
                lineSelections.append(contentsOf: splitSelectionByPixelGutters(
                    selection: rawSel,
                    on: page,
                    mediaBox: cropBox,
                    pixelBuffer: pb,
                    scaleX: scaleX,
                    scaleY: scaleY
                ))
            } else {
                lineSelections.append(rawSel)
            }
        }

        var extractedLines: [RecognizedTextLine] = []
        var totalChars = 0
        var spacedCjkLines = 0
        var cjkLines = 0
        var verticalLineCount = 0

        for sel in lineSelections {
            guard let rawStr = sel.string else { continue }
            let trimmed = rawStr
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let pdfBounds = sel.bounds(for: page)
            if pdfBounds.isNull || pdfBounds.isEmpty || pdfBounds.width <= 0.5 || pdfBounds.height <= 0.5 {
                continue
            }

            // Detect vertical lines vs rotated margin watermarks
            if pdfBounds.height > pdfBounds.width * 2.2 && trimmed.count >= 6 {
                verticalLineCount += 1
            }

            // Check for hidden OCR spacing artifacts in CJK text (e.g. "這 種 得 天 獨 厚" where 3+ consecutive single Han chars are separated by spaces)
            let hasCjk = trimmed.range(of: "\\p{Han}", options: .regularExpression) != nil
            if hasCjk {
                cjkLines += 1
                if trimmed.range(of: "[\\p{Han}]\\s+[\\p{Han}]\\s+[\\p{Han}]", options: .regularExpression) != nil {
                    spacedCjkLines += 1
                }
            }

            // Convert from PDF bottom-left coordinate space to top-left pixel coordinate space, respecting page rotation
            let pxMinX: CGFloat
            let pxMaxX: CGFloat
            let pxMinY: CGFloat
            let pxMaxY: CGFloat

            switch rot {
            case 90:
                pxMinX = max(0.0, (pdfBounds.minY - cropBox.minY) * scaleX)
                pxMaxX = min(CGFloat(pixelWidth), (pdfBounds.maxY - cropBox.minY) * scaleX)
                pxMinY = max(0.0, (pdfBounds.minX - cropBox.minX) * scaleY)
                pxMaxY = min(CGFloat(pixelHeight), (pdfBounds.maxX - cropBox.minX) * scaleY)
            case 180:
                pxMinX = max(0.0, (cropBox.maxX - pdfBounds.maxX) * scaleX)
                pxMaxX = min(CGFloat(pixelWidth), (cropBox.maxX - pdfBounds.minX) * scaleX)
                pxMinY = max(0.0, (pdfBounds.minY - cropBox.minY) * scaleY)
                pxMaxY = min(CGFloat(pixelHeight), (pdfBounds.maxY - cropBox.minY) * scaleY)
            case 270:
                pxMinX = max(0.0, (cropBox.maxY - pdfBounds.maxY) * scaleX)
                pxMaxX = min(CGFloat(pixelWidth), (cropBox.maxY - pdfBounds.minY) * scaleX)
                pxMinY = max(0.0, (cropBox.maxX - pdfBounds.maxX) * scaleY)
                pxMaxY = min(CGFloat(pixelHeight), (cropBox.maxX - pdfBounds.minX) * scaleY)
            default: // 0
                pxMinX = max(0.0, (pdfBounds.minX - cropBox.minX) * scaleX)
                pxMaxX = min(CGFloat(pixelWidth), (pdfBounds.maxX - cropBox.minX) * scaleX)
                pxMinY = max(0.0, (cropBox.maxY - pdfBounds.maxY) * scaleY)
                pxMaxY = min(CGFloat(pixelHeight), (cropBox.maxY - pdfBounds.minY) * scaleY)
            }

            let rect = CGRect(
                x: pxMinX,
                y: pxMinY,
                width: max(1.0, pxMaxX - pxMinX),
                height: max(1.0, pxMaxY - pxMinY)
            )

            extractedLines.append(RecognizedTextLine(
                text: trimmed,
                rect: rect,
                confidence: 1.0
            ))
            totalChars += trimmed.count
        }

        guard !extractedLines.isEmpty, totalChars >= 6 else {
            return PDFTextLayerAnalysisResult(sourceType: .scannedImage, visionAnalysis: nil)
        }

        // If the page is predominantly horizontal text, filter out 90°-rotated margin credit lines
        // (e.g. "Cover Illustration: ©Adam Stower..." running vertically along the left edge of a magazine page)
        let isPredominantlyHorizontal = Double(verticalLineCount) / Double(max(1, extractedLines.count)) < 0.25
        if isPredominantlyHorizontal {
            extractedLines = extractedLines.filter { line in
                !(line.rect.height > line.rect.width * 2.4 && line.text.count >= 8)
            }
        }

        // Merge fragmented PDF text selections that sit on the same horizontal baseline and belong to the same column
        let consolidatedLines = consolidateSameColumnFragments(
            lines: extractedLines,
            pageWidth: CGFloat(pixelWidth)
        )

        // 3. Determine whether this text layer is true Native Vector Text or an Embedded Hidden OCR Layer:
        // - A scanned PDF with a hidden OCR layer MUST contain at least one raster image (`imageDoOps > 0`)
        //   AND either uses PDF invisible text rendering mode (`3 Tr`) or has heavy character-by-character CJK spacing.
        let usesInvisibleTextMode = streamState.imageDoOps > 0 && (
            streamState.invisibleTextShowOps > streamState.visibleTextShowOps
            || (streamState.textRenderModes.contains(3) && streamState.visibleTextShowOps == 0)
        )
        let hasHeavySpacedCjkArtifact = streamState.imageDoOps > 0 && cjkLines >= 4 && (Double(spacedCjkLines) / Double(cjkLines) >= 0.30)

        let sourceType: PDFTextSourceType
        if usesInvisibleTextMode || hasHeavySpacedCjkArtifact {
            sourceType = .embeddedOCRLayer
        } else {
            sourceType = .nativeVectorText
        }

        let analysis = VisionPageAnalysis(lines: consolidatedLines)

        return PDFTextLayerAnalysisResult(
            sourceType: sourceType,
            visionAnalysis: analysis,
            rawLineCount: consolidatedLines.count,
            totalCharacterCount: totalChars
        )
    }

    /// Splits a PDFSelection that spans across two or more columns on the same baseline by detecting
    /// empty vertical whitespace gutters (`vertProj[x] == 0`) inside its rendered pixel bounding box.
    private static func splitSelectionByPixelGutters(
        selection: PDFSelection,
        on page: PDFPage,
        mediaBox: CGRect,
        pixelBuffer: PixelBuffer,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) -> [PDFSelection] {
        let pdfBounds = selection.bounds(for: page)
        guard !pdfBounds.isNull, !pdfBounds.isEmpty,
              pdfBounds.width >= mediaBox.width * 0.28,
              pdfBounds.height > 2.0 else {
            return [selection]
        }

        let pxMinX = max(0.0, (pdfBounds.minX - mediaBox.minX) * scaleX)
        let pxMaxX = min(CGFloat(pixelBuffer.width), (pdfBounds.maxX - mediaBox.minX) * scaleX)
        let pxMinY = max(0.0, (mediaBox.maxY - pdfBounds.maxY) * scaleY)
        let pxMaxY = min(CGFloat(pixelBuffer.height), (mediaBox.maxY - pdfBounds.minY) * scaleY)
        let rawPxH = max(1.0, pxMaxY - pxMinY)
        // Inset vertically by 15% when measuring vertical ink projection so ascenders/descenders from adjacent rows don't pollute the gutter
        let vInset = rawPxH * 0.15
        let pxRect = CGRect(
            x: pxMinX,
            y: pxMinY + vInset,
            width: max(1.0, pxMaxX - pxMinX),
            height: max(1.0, rawPxH - vInset * 2.0)
        )

        let vertProj = pixelBuffer.verticalProjection(in: pxRect, threshold: 210)
        let w = vertProj.count
        // A normal inter-word space is ~0.25-0.35x line height; a column gutter is >= 0.52x raw line height and >= 15px
        let minGutterPx = max(15, Int(rawPxH * 0.52))
        let edgeMargin = max(12, Int(Double(w) * 0.06))
        guard w > edgeMargin * 2 + minGutterPx else { return [selection] }

        var cutPointsPdfX: [CGFloat] = []
        var inZero = false
        var zeroStart = edgeMargin

        for x in edgeMargin..<(w - edgeMargin) {
            if vertProj[x] <= 1 {
                if !inZero {
                    inZero = true
                    zeroStart = x
                }
            } else {
                if inZero {
                    inZero = false
                    let gw = x - zeroStart
                    if gw >= minGutterPx {
                        let midPx = CGFloat(zeroStart + x) * 0.5
                        let pdfCutX = mediaBox.minX + (pxRect.minX + midPx) / scaleX
                        cutPointsPdfX.append(pdfCutX)
                    }
                }
            }
        }
        if inZero {
            let gw = (w - edgeMargin) - zeroStart
            if gw >= minGutterPx {
                let midPx = CGFloat(zeroStart + w - edgeMargin) * 0.5
                let pdfCutX = mediaBox.minX + (pxRect.minX + midPx) / scaleX
                cutPointsPdfX.append(pdfCutX)
            }
        }

        guard !cutPointsPdfX.isEmpty else { return [selection] }

        let rangeCount = selection.numberOfTextRanges(on: page)
        guard rangeCount > 0 else { return [selection] }

        let sortedCuts = cutPointsPdfX.sorted()
        var subRanges: [NSRange] = []

        for rIdx in 0..<rangeCount {
            let fullRange = selection.range(at: rIdx, on: page)
            guard fullRange.location != NSNotFound, fullRange.length > 0 else { continue }

            var segStart = fullRange.location
            let endIdx = fullRange.location + fullRange.length
            var activeCutIdx = 0

            for charIdx in fullRange.location..<endIdx {
                guard activeCutIdx < sortedCuts.count else { break }
                let cBounds = page.characterBounds(at: charIdx)
                if cBounds.isNull || cBounds.isEmpty || cBounds.width <= 0.05 || cBounds.height <= 0.05 {
                    continue
                }
                // Only split when a visible character's left/center crosses the detected pixel gutter cut X
                if cBounds.minX >= sortedCuts[activeCutIdx] - 1.5 {
                    let len = charIdx - segStart
                    if len > 0 {
                        subRanges.append(NSRange(location: segStart, length: len))
                    }
                    segStart = charIdx
                    while activeCutIdx < sortedCuts.count && cBounds.minX >= sortedCuts[activeCutIdx] - 1.5 {
                        activeCutIdx += 1
                    }
                }
            }

            if endIdx > segStart {
                subRanges.append(NSRange(location: segStart, length: endIdx - segStart))
            }
        }

        guard subRanges.count >= 2 else { return [selection] }

        var splitSelections: [PDFSelection] = []
        for r in subRanges {
            if let subSel = page.selection(for: r),
               let s = subSel.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty {
                splitSelections.append(subSel)
            }
        }

        return splitSelections.count >= 2 ? splitSelections : [selection]
    }

    /// Merges adjacent horizontal text fragments within the same column that PDFKit split on kerning/style runs,
    /// while strictly preserving column boundaries (`xGap < maxAllowedGap`).
    private static func consolidateSameColumnFragments(
        lines: [RecognizedTextLine],
        pageWidth: CGFloat
    ) -> [RecognizedTextLine] {
        guard lines.count > 1 else { return lines }

        // Sort top-to-bottom, then left-to-right
        let sorted = lines.sorted { a, b in
            if abs(a.rect.midY - b.rect.midY) > min(a.rect.height, b.rect.height) * 0.45 {
                return a.rect.minY < b.rect.minY
            }
            return a.rect.minX < b.rect.minX
        }

        var result: [RecognizedTextLine] = []
        for line in sorted {
            if let last = result.last {
                let sameRow = abs(last.rect.midY - line.rect.midY) <= min(last.rect.height, line.rect.height) * 0.45
                let similarHeight = abs(last.rect.height - line.rect.height) <= max(last.rect.height, line.rect.height) * 0.35
                let xGap = line.rect.minX - last.rect.maxX
                // Only merge if the horizontal gap is at most a single inline word space (<= 0.35x line height and <= 10px),
                // never across a multi-column gutter.
                let maxInlineGap = min(10.0, min(last.rect.height, line.rect.height) * 0.35)
                if sameRow && similarHeight && xGap >= -6.0 && xGap <= maxInlineGap {
                    let separator = shouldInsertSpace(between: last.text, and: line.text) ? " " : ""
                    let mergedText = last.text + separator + line.text
                    let mergedRect = last.rect.union(line.rect)
                    result[result.count - 1] = RecognizedTextLine(
                        text: mergedText,
                        rect: mergedRect,
                        confidence: 1.0
                    )
                    continue
                }
            }
            result.append(line)
        }

        return result
    }

    /// Determines whether a space should be inserted when joining two text segments
    public static func shouldInsertSpace(between left: String, and right: String) -> Bool {
        guard let lastChar = left.last, let firstChar = right.first else { return false }
        let leftIsAscii = lastChar.isASCII && (lastChar.isLetter || lastChar.isNumber || [",", ".", ";", ":", "?", "!", ")", "%", "\"", "'", "”", "’"].contains(lastChar))
        let rightIsAscii = firstChar.isASCII && (firstChar.isLetter || firstChar.isNumber || ["(", "$", "£", "€", "\"", "'", "“", "‘"].contains(firstChar))
        return leftIsAscii && rightIsAscii
    }

    /// Joins an array of line strings into a clean paragraph string, handling both CJK (no space)
    /// and English/Latin text (spaces between words, de-hyphenating line breaks).
    public static func joinLinesIntoParagraph(_ lines: [String]) -> String {
        var result = ""
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if result.isEmpty {
                result = line
                continue
            }

            // Check for English end-of-line hyphenation (e.g. "concen-" + "trate" or "record-" + "high")
            if (result.hasSuffix("-") || result.hasSuffix("‐")) && result.count >= 2 {
                let beforeHyphenIdx = result.index(result.endIndex, offsetBy: -2)
                let charBeforeHyphen = result[beforeHyphenIdx]
                if charBeforeHyphen.isASCII && charBeforeHyphen.isLetter,
                   let firstNext = line.first, firstNext.isASCII && firstNext.isLowercase {
                    // Remove soft line-break hyphen and join directly
                    result.removeLast()
                    result += line
                    continue
                }
            }

            if shouldInsertSpace(between: result, and: line) {
                result += " " + line
            } else {
                result += line
            }
        }
        return result
    }

    /// Scans the CGPDFPage operator stream to detect `Tr` (text rendering mode) and text-showing operators
    private static func inspectContentStream(page: PDFPage) -> StreamInspectionState {
        let state = StreamInspectionState()
        guard let cgPage = page.pageRef else { return state }

        guard let table = CGPDFOperatorTableCreate() else { return state }

        CGPDFOperatorTableSetCallback(table, "Tr") { scanner, userInfo in
            guard let userInfo = userInfo else { return }
            let s = Unmanaged<StreamInspectionState>.fromOpaque(userInfo).takeUnretainedValue()
            var mode: CGPDFInteger = 0
            if CGPDFScannerPopInteger(scanner, &mode) {
                let m = Int(mode)
                s.currentRenderMode = m
                s.textRenderModes.insert(m)
            }
        }

        let textOpCallback: CGPDFOperatorCallback = { _, userInfo in
            guard let userInfo = userInfo else { return }
            let s = Unmanaged<StreamInspectionState>.fromOpaque(userInfo).takeUnretainedValue()
            if s.currentRenderMode == 3 {
                s.invisibleTextShowOps += 1
            } else {
                s.visibleTextShowOps += 1
            }
        }

        CGPDFOperatorTableSetCallback(table, "Tj", textOpCallback)
        CGPDFOperatorTableSetCallback(table, "TJ", textOpCallback)
        CGPDFOperatorTableSetCallback(table, "'", textOpCallback)
        CGPDFOperatorTableSetCallback(table, "\"", textOpCallback)

        CGPDFOperatorTableSetCallback(table, "Do") { _, userInfo in
            guard let userInfo = userInfo else { return }
            let s = Unmanaged<StreamInspectionState>.fromOpaque(userInfo).takeUnretainedValue()
            s.imageDoOps += 1
        }

        let contentStream = CGPDFContentStreamCreateWithPage(cgPage)
        let ptr = Unmanaged.passUnretained(state).toOpaque()
        let scanner = CGPDFScannerCreate(contentStream, table, ptr)
        CGPDFScannerScan(scanner)

        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(contentStream)
        CGPDFOperatorTableRelease(table)

        return state
    }
}
