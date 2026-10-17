import Foundation
import CoreGraphics
import Vision

public struct RecognizedTextLine: Sendable {
    public let text: String
    public let rect: CGRect // In image pixel coordinates (origin top-left)
    public let confidence: Float

    public init(text: String, rect: CGRect, confidence: Float) {
        self.text = text
        self.rect = rect
        self.confidence = confidence
    }

    /// Checks if the text ends with a sentence terminator (。, ！, ？, ；, ：)
    public var endsWithSentenceTerminator: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastChar = trimmed.last else { return false }
        return ["。", "！", "？", "!", "?", "…", "；", ";", "：", ":"].contains(lastChar)
    }

    /// Checks if the text ends with a continuation punctuation (comma, pause, hyphen)
    public var endsWithContinuationMarker: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastChar = trimmed.last else { return false }
        return ["，", ",", "、", "—", "-", "~"].contains(lastChar)
    }

    /// Checks if the text starts with a structural heading or numbered list (e.g. "一、", "1.", "（一）")
    /// Excludes decimal numbers (e.g. "85.77%", "13.3亿美元") and dates ("2026.6.22").
    public var startsWithHeadingMarker: Bool {
        return Self.isHeadingPrefix(text)
    }

    public static func isHeadingPrefix(_ rawText: String) -> Bool {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 42 else { return false }

        // 1. Chinese numerals or parenthesized markers: "一、", "（一）", "(1)", "●", "【", "第一章"
        let chineseOrParenPattern = "^([一二三四五六七八九十百]+[、.．]|[(（][一二三四五六七八九十0-9]{1,2}[)）]|●|■|◆|▲|【|第[0-9一二三四五六七八九十百]+[章节条篇部分])"
        if trimmed.range(of: chineseOrParenPattern, options: .regularExpression) != nil {
            return true
        }

        // 2. Arabic numeral list/heading: "1、", "1. ", "2.标题"
        // Must NOT be followed by a digit (which indicates a decimal like 85.77% or date 2026.6)
        // and must NOT be followed by numeric units (亿, 万, 元, %, 倍, 年, 月, 日).
        let arabicHeadingPattern = "^([1-9][0-9]?[、]|[1-9][0-9]?[.．](?![0-9%％亿万元美元港元日元倍成个年月日]))"
        if let range = trimmed.range(of: arabicHeadingPattern, options: .regularExpression) {
            let afterMarker = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            // Must have meaningful title text after "1." (not just a bare number or symbol)
            if afterMarker.count >= 2 && !afterMarker.hasPrefix("%") {
                return true
            }
        }

        return false
    }
}

public enum SemanticLevel: String, Sendable, CaseIterable {
    case header = "页眉"
    case title = "大标题"
    case sectionHeader = "一级标题"
    case subHeader = "二级标题"
    case salutation = "称谓/导语"
    case body = "正文"
    case caption = "题注/注脚"
    case footer = "页脚/页码"

    public var scaleRatio: CGFloat {
        switch self {
        case .header: return 0.82
        case .title: return 1.45
        case .sectionHeader: return 1.25
        case .subHeader: return 1.12
        case .salutation: return 1.05
        case .body: return 1.0
        case .caption: return 0.88
        case .footer: return 0.80
        }
    }
}

public struct VisionPageAnalysis: Sendable {
    public let lines: [RecognizedTextLine]

    public init(lines: [RecognizedTextLine]) {
        self.lines = lines
    }

    /// Finds the recognized text line(s) that overlap both vertically AND horizontally with sliceRect,
    /// joining multiple horizontal segments in left-to-right reading order while rejecting vertically adjacent rows.
    public func findMatchingLine(for sliceRect: CGRect, verticalTolerance: CGFloat = 16.0) -> RecognizedTextLine? {
        var candidates: [(line: RecognizedTextLine, vOverlap: CGFloat, centerDist: CGFloat)] = []

        for line in lines {
            // 1. Check horizontal overlap first (critical for multi-column pages!)
            let left = max(sliceRect.minX, line.rect.minX)
            let right = min(sliceRect.maxX, line.rect.maxX)
            let hOverlap = right - left
            let minReqHOverlap = max(4.0, min(sliceRect.width, line.rect.width) * 0.25)
            guard hOverlap >= minReqHOverlap else { continue }

            // 2. Check vertical overlap
            let top = max(sliceRect.minY, line.rect.minY)
            let bottom = min(sliceRect.maxY, line.rect.maxY)
            let vOverlap = bottom - top
            let minH = min(sliceRect.height, line.rect.height)
            let minReqVOverlap = max(4.0, minH * 0.38)
            let centerDist = abs(sliceRect.midY - line.rect.midY)
            let dynamicVTol = min(verticalTolerance, minH * 0.38)

            if vOverlap >= minReqVOverlap || (vOverlap > 0 && centerDist <= dynamicVTol) {
                candidates.append((line: line, vOverlap: vOverlap, centerDist: centerDist))
            }
        }

        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0].line }

        // Sort candidates by vertical overlap descending (then closest midY) so the primary row wins
        // over any vertically adjacent row whose font bounding box slightly grazes sliceRect.
        let ranked = candidates.sorted { a, b in
            if abs(a.vOverlap - b.vOverlap) > 1.5 {
                return a.vOverlap > b.vOverlap
            }
            return a.centerDist < b.centerDist
        }

        var selected: [RecognizedTextLine] = []
        for cand in ranked {
            // If this candidate horizontally overlaps an already-selected line, it belongs to a vertically
            // adjacent row (above or below), NOT a horizontal segment on the same row.
            let overlapsHorizontallyWithSelected = selected.contains { existing in
                let ox = min(existing.rect.maxX, cand.line.rect.maxX) - max(existing.rect.minX, cand.line.rect.minX)
                return ox > min(existing.rect.width, cand.line.rect.width) * 0.25
            }
            if !overlapsHorizontallyWithSelected {
                selected.append(cand.line)
            }
        }

        guard !selected.isEmpty else { return ranked[0].line }
        if selected.count == 1 { return selected[0] }

        // Sort genuine horizontal segments left-to-right and join cleanly
        selected.sort { $0.rect.minX < $1.rect.minX }
        let combinedText = PDFTextLayerAnalyzer.joinLinesIntoParagraph(selected.map { $0.text })
        let unionRect = selected.dropFirst().reduce(selected[0].rect) { $0.union($1.rect) }
        let avgConf = selected.reduce(Float(0)) { $0 + $1.confidence } / Float(selected.count)
        return RecognizedTextLine(text: combinedText, rect: unionRect, confidence: avgConf)
    }

    /// Detects candidate table regions within a specific columnRect based on multi-column short-cell alignments (OCR grid layout).
    /// Restricting to `columnRect` and short table cells prevents multi-column magazine body text from being misclassified as a table.
    public func detectTableZones(in columnRect: CGRect? = nil, expectedLineHeight: Int) -> [CGRect] {
        let candidateLines: [RecognizedTextLine]
        if let colRect = columnRect {
            candidateLines = lines.filter { line in
                colRect.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) &&
                line.rect.width <= colRect.width * 0.48
            }
        } else {
            candidateLines = lines
        }

        guard candidateLines.count >= 6 else { return [] }

        // Find clusters of horizontally parallel cells (cells sharing similar Y but distinct X within the column)
        var rowGroups: [[RecognizedTextLine]] = []
        for line in candidateLines {
            // Prose sentences ending with period are not table cells
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 18 || trimmed.hasSuffix("。") { continue }

            var added = false
            for (idx, group) in rowGroups.enumerated() {
                if let ref = group.first, abs(ref.rect.midY - line.rect.midY) < CGFloat(expectedLineHeight) * 0.55 {
                    rowGroups[idx].append(line)
                    added = true
                    break
                }
            }
            if !added {
                rowGroups.append([line])
            }
        }

        // Multi-column table rows (2 or more short cells in the same row, with reasonable horizontal gap)
        let multiColumnRows = rowGroups.compactMap { row -> [RecognizedTextLine]? in
            guard row.count >= 2 else { return nil }
            let sorted = row.sorted { $0.rect.minX < $1.rect.minX }
            let avgChars = Double(sorted.reduce(0) { $0 + $1.text.count }) / Double(sorted.count)
            guard avgChars <= 14.0 else { return nil }
            return sorted
        }
        guard multiColumnRows.count >= 3 else { return [] }

        // Cluster consecutive multi-column rows into table bounds
        var tableRects: [CGRect] = []
        var clusterRows: [[RecognizedTextLine]] = []

        for row in multiColumnRows {
            if let lastRow = clusterRows.last, let lastFirst = lastRow.first, let curFirst = row.first {
                let yGap = curFirst.rect.minY - lastFirst.rect.maxY
                if yGap < CGFloat(expectedLineHeight) * 2.5 {
                    clusterRows.append(row)
                } else {
                    if clusterRows.count >= 3 {
                        tableRects.append(computeClusterBounds(rows: clusterRows))
                    }
                    clusterRows = [row]
                }
            } else {
                clusterRows.append(row)
            }
        }

        if clusterRows.count >= 3 {
            tableRects.append(computeClusterBounds(rows: clusterRows))
        }

        // Never allow an OCR-inferred table to swallow > 70% of a tall narrow text column unless it is in a shorter/wider sub-zone
        if let colRect = columnRect, colRect.height > 2600 && colRect.width < 1500 {
            tableRects = tableRects.filter { tRect in
                tRect.height <= colRect.height * 0.70
            }
        }

        return tableRects
    }

    private func computeClusterBounds(rows: [[RecognizedTextLine]]) -> CGRect {
        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity

        for row in rows {
            for cell in row {
                minX = min(minX, cell.rect.minX)
                maxX = max(maxX, cell.rect.maxX)
                minY = min(minY, cell.rect.minY)
                maxY = max(maxY, cell.rect.maxY)
            }
        }

        let pad: CGFloat = 8.0
        return CGRect(
            x: max(0, minX - pad),
            y: max(0, minY - pad),
            width: maxX - minX + pad * 2,
            height: maxY - minY + pad * 2
        )
    }

    /// Evaluates semantic level of a text line/paragraph based on linguistic patterns, page geometry and font sizes
    public func classifySemanticLevel(
        text: String,
        lineHeight: CGFloat,
        medianBodyHeight: CGFloat,
        isEarlyInDoc: Bool,
        rect: CGRect? = nil,
        pageHeight: CGFloat = 0.0
    ) -> SemanticLevel {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .body }

        // 1. Footer / Page Number / Magazine Running Footer (e.g. "26 财经｜2026.6.22"):
        let isPageNumber = trimmed.range(of: "^([—\\-~–]?\\s*[0-9一二三四五六七八九十]+\\s*[—\\-~–]?|第\\s*[0-9]+\\s*页(\\s*[/共]\\s*[0-9]+\\s*页)?|\\s*[0-9]+\\s*)$", options: .regularExpression) != nil
        let isMagazineFooter = trimmed.count <= 28 && (trimmed.contains("财经｜") || trimmed.contains("財经｜") || trimmed.contains("财经|") || trimmed.range(of: "^[0-9]{1,3}\\s+.*[0-9]{4}\\.[0-9]{1,2}", options: .regularExpression) != nil)
        if isMagazineFooter {
            return .footer
        }
        if let r = rect, pageHeight > 0, r.minY >= pageHeight * 0.925 {
            if isPageNumber || (trimmed.count <= 16 && !trimmed.hasSuffix("。") && !trimmed.hasSuffix("，")) {
                return .footer
            }
        }
        if isPageNumber && trimmed.count <= 10 {
            return .footer
        }

        // 2. Header / Running Header / Magazine Section Tag (e.g. "封面", "Cover Story", "经济", "Economy"):
        let magazineSectionTags = ["封面", "经济", "观察", "金融", "产业", "科技", "法治", "国际", "专访", "特稿", "焦点", "评论", "专栏", "Cover Story", "er Story", "Economy", "Feature", "Column"]
        if let r = rect, pageHeight > 0, r.maxY <= pageHeight * 0.12 {
            let hasTitleKeywords = trimmed.contains("关于") || trimmed.contains("通报") || trimmed.contains("通知") || trimmed.contains("决定") || trimmed.contains("方案")
            let isMagTag = magazineSectionTags.contains { trimmed.caseInsensitiveCompare($0) == .orderedSame } || (trimmed.count <= 12 && r.maxY <= pageHeight * 0.09)
            if isMagTag {
                return .header
            }
            if !hasTitleKeywords && trimmed.count <= 35 && lineHeight <= medianBodyHeight * 1.15 {
                return .header
            }
        }

        // 3. Annotations / Captions / Notes / Footnotes / Magazine Credits:
        // E.g. "注：", "说明：", "图1：", "表1：", "资料来源：", "数据来源：", "图/视觉中国", "文/周浩"
        let captionPrefixes = ["注：", "注:", "说明：", "说明:", "特别提示", "资料来源", "数据来源", "图表来源", "来源：", "来源:", "图/", "摄/", "图片/", "*", "※"]
        if captionPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return .caption
        }
        if trimmed.count <= 90 && (trimmed.contains("图/视觉中国") || trimmed.contains("图/受访者") || trimmed.contains("图/IC") || trimmed.contains("资料来源：") || trimmed.contains("数据来源：")) {
            return .caption
        }
        if let first = trimmed.first {
            let s = String(first)
            if (s >= "\u{2460}" && s <= "\u{2473}") || (s >= "\u{3251}" && s <= "\u{32BF}") {
                return .caption
            }
        }
        let footnotePattern = "^([①-⑳㉑-㉟]|[(（\\[【][0-9]{1,2}[)）\\]】]|(图|表|图表)\\s*[0-9一二三四五六七八九十]+[：:.:\\s])"
        if trimmed.range(of: footnotePattern, options: .regularExpression) != nil && trimmed.count <= 85 {
            return .caption
        }

        // Magazine Author Byline / Lead-in (e.g. "文/周浩", "文｜本刊记者..."):
        if trimmed.count <= 28 && (trimmed.hasPrefix("文/") || trimmed.hasPrefix("文｜") || trimmed.hasPrefix("文|") || trimmed.hasPrefix("本刊记者") || trimmed.hasPrefix("编辑/") || trimmed.hasPrefix("编辑｜")) {
            return .salutation
        }

        // Long prose paragraphs (> 42 chars) are always body text, never headings
        if trimmed.count > 42 {
            return .body
        }

        // 4. Large Document / Article Title: substantial height (> 1.32x body height)
        let hasTitleKeywords = trimmed.contains("关于") || trimmed.contains("通报") || trimmed.contains("通知") || trimmed.contains("决定") || trimmed.contains("公告") || trimmed.contains("方案") || trimmed.contains("意见")
        if (lineHeight >= medianBodyHeight * 1.25 && isEarlyInDoc) || lineHeight >= medianBodyHeight * 1.35 || (hasTitleKeywords && isEarlyInDoc && lineHeight >= medianBodyHeight * 1.12) {
            return .title
        }

        // 5. Section Heading (一级标题): e.g. "一、总体情况", "第1章", "【一】" or medium-large standalone sub-headline in magazine
        if trimmed.range(of: "^([一二三四五六七八九十]+[、.．]|第[0-9一二三四五六七八九十]+[章节篇]|【)", options: .regularExpression) != nil {
            return .sectionHeader
        }
        if lineHeight >= medianBodyHeight * 1.18 && trimmed.count <= 30 && !trimmed.hasSuffix("。") {
            return .sectionHeader
        }

        // 6. Sub-header (二级标题): e.g. "（一）", "(1)", "1. 标题" (excluding decimals!)
        if RecognizedTextLine.isHeadingPrefix(trimmed) && !trimmed.hasSuffix("。") {
            return .subHeader
        }

        // 7. Salutation / Lead-in (称谓/冒号导语): e.g. "各股室、定点医疗机构：", "如下："
        if trimmed.hasSuffix("：") || trimmed.hasSuffix(":") {
            if trimmed.count <= 18 {
                return .salutation
            }
        }

        return .body
    }
}

public struct VisionTextRecognizer {
    /// Performs Apple Vision neural text recognition on the rendered page CGImage
    public static func recognize(cgImage: CGImage) -> VisionPageAnalysis? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 10, height > 10 else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results else {
            return VisionPageAnalysis(lines: [])
        }

        var lines: [RecognizedTextLine] = []

        for obs in observations {
            guard let candidate = obs.topCandidates(1).first, !candidate.string.isEmpty else {
                continue
            }

            // Convert normalized Vision coordinates (origin bottom-left) to image pixel coordinates (origin top-left)
            let norm = obs.boundingBox
            let pixelRect = CGRect(
                x: norm.minX * width,
                y: (1.0 - norm.maxY) * height,
                width: norm.width * width,
                height: norm.height * height
            )

            lines.append(RecognizedTextLine(
                text: candidate.string,
                rect: pixelRect,
                confidence: candidate.confidence
            ))
        }

        // Sort lines top-to-bottom
        lines.sort { $0.rect.minY < $1.rect.minY }

        return VisionPageAnalysis(lines: lines)
    }
}
