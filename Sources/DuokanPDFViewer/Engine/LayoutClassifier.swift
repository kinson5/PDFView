import Foundation
import CoreGraphics

public struct LayoutClassifier {
    /// Detects whether the page layout is a vertical book (古籍/港台竖排书籍)
    /// based on physical pixel projection and native text layers BEFORE running any OCR.
    public static func detectVerticalBook(
        pixelBuffer: PixelBuffer,
        contentBounds: CGRect,
        preExtractedTextLayer: PDFTextLayerAnalysisResult? = nil,
        hasDocumentAffinity: Bool = false
    ) -> Bool {
        // 1. Native Vector Text Layer Check
        if let nativeLines = preExtractedTextLayer?.visionAnalysis?.lines, !nativeLines.isEmpty {
            let verticalLines = nativeLines.filter { $0.rect.height > $0.rect.width * 1.5 }
            let horizontalLines = nativeLines.filter { $0.rect.width > $0.rect.height * 1.2 }
            if verticalLines.count >= 2 && Double(verticalLines.count) / Double(nativeLines.count) >= 0.30 {
                return true
            }
            // If the native text is predominantly horizontal (e.g. magazines, papers, books), it is NOT a vertical book
            if horizontalLines.count >= 3 && Double(horizontalLines.count) / Double(nativeLines.count) >= 0.50 {
                return false
            }
            if hasDocumentAffinity && !verticalLines.isEmpty {
                return true
            }
        }

        // 2. Physical Pixel Projection Analysis (O(W+H) in < 2ms)
        guard contentBounds.width >= 40, contentBounds.height >= 40 else { return false }
        let vertProj = pixelBuffer.verticalProjection(in: contentBounds, threshold: 140)
        let avgInk = vertProj.isEmpty ? 0 : (vertProj.reduce(0, +) / vertProj.count)
        let noiseLimit = max(4, Int(Double(avgInk) * 0.15))

        var vColCount = 0
        var inCol = false
        var startX = 0
        var colW = 0
        var allWidths: [Int] = []
        var substantialCols = 0

        for x in 0..<vertProj.count {
            if vertProj[x] > noiseLimit {
                if !inCol {
                    inCol = true
                    startX = x
                    colW = 1
                } else {
                    colW += 1
                }
            } else {
                if inCol {
                    inCol = false
                    if colW >= 6 {
                        vColCount += 1
                        allWidths.append(colW)
                        let colRect = CGRect(
                            x: contentBounds.minX + CGFloat(startX),
                            y: contentBounds.minY,
                            width: CGFloat(colW),
                            height: contentBounds.height
                        )
                        let horizProj = pixelBuffer.horizontalProjection(in: colRect, threshold: 140)
                        let inkRows = horizProj.filter { $0 > 0 }.count
                        if CGFloat(inkRows) >= contentBounds.height * 0.25 {
                            substantialCols += 1
                        }
                    }
                }
            }
        }
        if inCol && colW >= 6 {
            vColCount += 1
            allWidths.append(colW)
            let colRect = CGRect(
                x: contentBounds.minX + CGFloat(startX),
                y: contentBounds.minY,
                width: CGFloat(colW),
                height: contentBounds.height
            )
            let horizProj = pixelBuffer.horizontalProjection(in: colRect, threshold: 140)
            let inkRows = horizProj.filter { $0 > 0 }.count
            if CGFloat(inkRows) >= contentBounds.height * 0.25 {
                substantialCols += 1
            }
        }

        guard !allWidths.isEmpty else { return false }
        let sortedW = allWidths.sorted()
        let medianW = sortedW[sortedW.count / 2]
        let refWidth = max(contentBounds.width, CGFloat(pixelBuffer.width) * 0.65)
        let colWidthRatio = Double(medianW) / Double(refWidth)

        // In vertical books, individual columns are single-character wide and span across the page:
        // A typical vertical book page has 8 to 24 columns, each with colWidthRatio <= 8.5%.
        if substantialCols >= 7 && colWidthRatio <= 0.085 {
            return true
        }

        // With document-level affinity (e.g. title page, sparse chapter-end page of a vertical book):
        if hasDocumentAffinity && substantialCols >= 1 && colWidthRatio <= 0.095 {
            return true
        }

        return false
    }

    /// Classifies the macro layout profile of a page based on column geometry, OCR semantics, and visual elements
    public static func classify(
        detectedColumns: [CGRect],
        contentBounds: CGRect,
        visionAnalysis: VisionPageAnalysis?,
        pixelBuffer: PixelBuffer,
        hasDocumentAffinity: Bool = false
    ) -> LayoutProfile {
        // 0. Vertical Book: 竖排排版已改为独立显式选项，避免智能识别误将横排文字误判为竖排

        // 1. Magazine / Periodical Detection (现代杂志/画报):
        // Check for 3+ columns, magazine running markers ("财经｜", "Cover Story", "文/", "图/", "本刊记者"),
        // or partial-height multi-column layouts where a spanning photo/title covers top/bottom half.
        if detectedColumns.count >= 3 {
            return .magazine
        }

        if let vision = visionAnalysis, !vision.lines.isEmpty {
            let allTexts = vision.lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            let magazineKeywords = ["财经｜", "財经｜", "Cover Story", "er Story", "本刊记者", "文/", "图/视觉中国", "图/受访者", "图/IC"]
            let hasMagazineMarker = allTexts.contains { line in
                magazineKeywords.contains { line.contains($0) }
            }
            if hasMagazineMarker {
                return .magazine
            }

            // Check if OCR lines show a 3-column magazine layout (left, middle, and right columns)
            // even when whole-page detectedColumns returned 1 due to a spanning photo/title
            let narrowLines = vision.lines.filter { $0.rect.width >= contentBounds.width * 0.18 && $0.rect.width <= contentBounds.width * 0.36 && $0.text.count >= 8 }
            if narrowLines.count >= 6 {
                let leftColLines = narrowLines.filter { $0.rect.maxX <= contentBounds.minX + contentBounds.width * 0.37 }
                let midColLines = narrowLines.filter { $0.rect.minX >= contentBounds.minX + contentBounds.width * 0.31 && $0.rect.maxX <= contentBounds.minX + contentBounds.width * 0.69 }
                let rightColLines = narrowLines.filter { $0.rect.minX >= contentBounds.minX + contentBounds.width * 0.63 }
                if leftColLines.count >= 2 && midColLines.count >= 2 && rightColLines.count >= 2 {
                    return .magazine
                }
            }
        }

        // Check partial-height 2-column or 3-column split (e.g. top half is spanning title/photo)
        if detectedColumns.count <= 1 && contentBounds.height > 400 {
            let bottomHalf = CGRect(
                x: contentBounds.minX,
                y: contentBounds.minY + contentBounds.height * 0.35,
                width: contentBounds.width,
                height: contentBounds.height * 0.60
            )
            let topHalf = CGRect(
                x: contentBounds.minX,
                y: contentBounds.minY + contentBounds.height * 0.06,
                width: contentBounds.width,
                height: contentBounds.height * 0.46
            )
            let bottomCols = ColumnDetector.detectColumns(pixelBuffer: pixelBuffer, contentBounds: bottomHalf, threshold: 140)
            let topCols = ColumnDetector.detectColumns(pixelBuffer: pixelBuffer, contentBounds: topHalf, threshold: 140)
            if bottomCols.count >= 3 || topCols.count >= 3 {
                return .magazine
            } else if bottomCols.count >= 2 || topCols.count >= 2 {
                return .academic
            }
        }

        // 2. Double-Column layout without magazine markers: Academic / Literature
        if detectedColumns.count >= 2 {
            return .academic
        }

        if let vision = visionAnalysis, !vision.lines.isEmpty {
            let leftLines = vision.lines.filter { $0.rect.maxX <= contentBounds.minX + contentBounds.width * 0.52 && $0.rect.width <= contentBounds.width * 0.48 }
            let rightLines = vision.lines.filter { $0.rect.minX >= contentBounds.minX + contentBounds.width * 0.48 && $0.rect.width <= contentBounds.width * 0.48 }
            if leftLines.count >= 3 && rightLines.count >= 3 {
                return .academic
            }
        }

        // 3. Official Document / Notice (公文通报/报告):
        // Characteristics: prominent title with official keywords, salutation ending with colon,
        // numbered section headers ("一、", "二是"), single-column, absence of academic footnotes.
        if let vision = visionAnalysis, !vision.lines.isEmpty {
            let topLines = vision.lines.prefix(5).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            let allTexts = vision.lines.map { $0.text }

            let officialTitleKeywords = ["关于", "通报", "通知", "决定", "意见", "方案", "通告", "纪要", "函", "报告", "办法", "批复"]
            let hasOfficialTitle = topLines.contains { line in
                officialTitleKeywords.contains { line.contains($0) }
            }

            let hasSalutation = topLines.contains { line in
                (line.hasSuffix("：") || line.hasSuffix(":")) && line.count <= 25
            }

            let hasOfficialSectionMarkers = allTexts.contains { line in
                line.range(of: "^([一二三四五六七八九十]+、|第[0-9一二三四五六七八九十]+条|[一二三四五]是[部分各])", options: .regularExpression) != nil
            }

            // Check if there are academic footnote markers (①-⑳)
            let hasFootnoteMarkers = allTexts.contains { line in
                WordSegmenter.isFootnoteMarker(line)
            }

            if (hasOfficialTitle || (hasSalutation && hasOfficialSectionMarkers)) && !hasFootnoteMarkers {
                return .officialDoc
            }

            if hasFootnoteMarkers {
                return .book
            }
        }

        // 4. Fallback default for single-column books and reading materials
        return .book
    }
}
