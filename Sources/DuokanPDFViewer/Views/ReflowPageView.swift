import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct ReflowPageView: View {
    @ObservedObject var viewModel: PDFReaderViewModel

    public init(viewModel: PDFReaderViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let theme = viewModel.config.readingTheme
        let bgColor = Color(nsColor: theme.backgroundColor)
        let textColor = Color(nsColor: theme.textColor)
        let l10n = viewModel.l10n
        #if os(iOS)
        let horizPad: CGFloat = 16.0
        #else
        let horizPad: CGFloat = 24.0
        #endif

        GeometryReader { geo in
            let availableWidth = geo.size.width
            // Max reading width clamped to the actual window container width (no horizontal overflow)
            let containerWidth = max(240.0, min(availableWidth - horizPad * 2.0, viewModel.config.reflowMaxWidth))

            ZStack {
                bgColor.ignoresSafeArea()

                if viewModel.isProcessing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(l10n.processingPage)
                            .font(.headline)
                            .foregroundColor(textColor)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.isReflowPageLocked(pageIndex: viewModel.currentPageIndex) {
                    proLockedPageTeaser(containerWidth: containerWidth, textColor: textColor)
                } else if let result = viewModel.currentReflowResult, (!result.paragraphs.isEmpty || !result.allSlices.isEmpty) {
                    let useVectorText = result.shouldUseVectorText(for: viewModel.config)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .center, spacing: 0) {
                            Color.clear.frame(height: 12)

                            if viewModel.config.enableWordReflow && !result.paragraphs.isEmpty {
                                // 🌟 Word-level / Vector-Text Paragraph Reflow with Smart Figure/Table, Side-by-Side & Apple Translation
                                LazyVStack(alignment: .leading, spacing: viewModel.config.paragraphSpacing) {
                                    ForEach(Array(result.paragraphs.enumerated()), id: \.element.id) { index, paragraph in
                                        let isFirstFootnote = (result.resolvedProfile != .officialDoc) && paragraph.semanticLevel == .caption && (index == 0 || result.paragraphs[index - 1].semanticLevel != .caption)
                                        if isFirstFootnote {
                                            HStack {
                                                Rectangle()
                                                    .fill(textColor.opacity(0.35))
                                                    .frame(width: min(130.0, containerWidth * 0.32), height: 1)
                                                Spacer(minLength: 0)
                                            }
                                            .frame(width: containerWidth)
                                            .padding(.top, 14)
                                            .padding(.bottom, 4)
                                        }

                                        ParagraphFlowView(
                                            paragraph: paragraph,
                                            containerWidth: containerWidth,
                                            textScale: viewModel.config.textScale,
                                            wordSpacing: viewModel.config.wordSpacing,
                                            lineSpacing: viewModel.config.sliceSpacing,
                                            standardBodyLineHeight: viewModel.config.standardBodyLineHeight,
                                            useVectorText: useVectorText,
                                            translationMode: viewModel.translationMode,
                                            translatedText: viewModel.translatedParagraphs[paragraph.id],
                                            l10n: l10n,
                                            theme: theme,
                                            invertDark: viewModel.config.invertColorsInDarkTheme
                                        )
                                    }
                                }
                                .frame(width: containerWidth, alignment: .leading)
                                .padding(.bottom, 40)
                            } else {
                                // Fallback Line-level slice mode
                                VStack(alignment: .leading, spacing: viewModel.config.sliceSpacing) {
                                    ForEach(result.allSlices) { slice in
                                        LineSliceRow(
                                            slice: slice,
                                            containerWidth: containerWidth,
                                            textScale: viewModel.config.textScale,
                                            theme: theme,
                                            invertDark: viewModel.config.invertColorsInDarkTheme
                                        )
                                    }
                                }
                                .frame(width: containerWidth, alignment: .leading)
                                .padding(.bottom, 40)
                            }

                            // Page bottom controls
                            HStack(spacing: 24) {
                                Button(action: { viewModel.prevPage() }) {
                                    Label(l10n.prevPageLabel, systemImage: "chevron.left")
                                }
                                .disabled(viewModel.currentPageIndex == 0)

                                Text("\(viewModel.currentPageIndex + 1) / \(viewModel.totalPages)")
                                    .font(.headline)
                                    .foregroundColor(textColor)

                                Button(action: { viewModel.nextPage() }) {
                                    Label(l10n.nextPageLabel, systemImage: "chevron.right")
                                }
                                .disabled(viewModel.currentPageIndex >= viewModel.totalPages - 1)
                            }
                            .padding(.vertical, 24)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, horizPad)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(l10n.untitledDocument)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func proLockedPageTeaser(containerWidth: CGFloat, textColor: Color) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.orange.opacity(0.2), Color.red.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)

                Image(systemName: "crown.fill")
                    .font(.system(size: 38))
                    .foregroundColor(.orange)
            }

            VStack(spacing: 8) {
                Text(pageLimitReachedTitle)
                    .font(.title3.weight(.bold))
                    .foregroundColor(textColor)

                Text(pageLimitReachedSubtitle)
                    .font(.subheadline)
                    .foregroundColor(textColor.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 12) {
                Button(action: {
                    viewModel.showProPaywall = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text(unlockProButtonTitle)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.activeMode = .original
                }) {
                    Text(returnToOriginalPDFTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var pageLimitReachedTitle: String {
        switch viewModel.appLanguage {
        case .zhHans: return "已达到前 20 页免费试读上限"
        case .zhHant: return "已達到前 20 頁免費試讀上限"
        case .en: return "Reached Free 20-Page Preview Limit"
        case .de: return "Vorschau auf 20 Seiten beendet"
        case .ja: return "無料試読（20ページ）の上限に達しました"
        }
    }

    private var pageLimitReachedSubtitle: String {
        switch viewModel.appLanguage {
        case .zhHans: return "当前为第 \(viewModel.currentPageIndex + 1) 页。解锁 PDFview Pro 永久买断版，即可畅读本书全部 \(viewModel.totalPages) 页智能重排。"
        case .zhHant: return "當前為第 \(viewModel.currentPageIndex + 1) 頁。解鎖 PDFview Pro 永久買斷版，即可暢享全書 \(viewModel.totalPages) 頁智慧重排。"
        case .en: return "Current page: \(viewModel.currentPageIndex + 1) of \(viewModel.totalPages). Unlock PDFview Pro Lifetime for unlimited pages reflow."
        case .de: return "Aktuell: Seite \(viewModel.currentPageIndex + 1) von \(viewModel.totalPages). Schalten Sie PDFview Pro für unbegrenzten Textumfluss frei."
        case .ja: return "現在 \(viewModel.currentPageIndex + 1) / \(viewModel.totalPages) ページ。PDFview Pro（買い切り版）で全編リフローを解放。"
        }
    }

    private var unlockProButtonTitle: String {
        switch viewModel.appLanguage {
        case .zhHans: return "解锁 Pro 永久买断"
        case .zhHant: return "解鎖 Pro 永久買斷"
        case .en: return "Unlock Pro Lifetime"
        case .de: return "Pro freischalten"
        case .ja: return "Pro 永久版を解放"
        }
    }

    private var returnToOriginalPDFTitle: String {
        switch viewModel.appLanguage {
        case .zhHans: return "切换为原版 PDF 阅读"
        case .zhHant: return "切換為原版 PDF 閱讀"
        case .en: return "Switch to Original PDF"
        case .de: return "Zum Original-PDF wechseln"
        case .ja: return "オリジナルPDFで閲覧"
        }
    }
}

/// Renders a paragraph or figure block, intelligently handling tables, side-by-side text/image layouts,
/// direct vector text rendering when the PDF has a native text layer, and Apple built-in translation.
private struct ParagraphFlowView: View {
    let paragraph: ParagraphBlock
    let containerWidth: CGFloat
    let textScale: CGFloat
    let wordSpacing: CGFloat
    let lineSpacing: CGFloat
    let standardBodyLineHeight: CGFloat
    let useVectorText: Bool
    let translationMode: TranslationDisplayMode
    let translatedText: String?
    let l10n: L10n
    let theme: ReadingTheme
    let invertDark: Bool

    var body: some View {
        let textColor = Color(nsColor: theme.textColor)
        let baseFontSize = max(11.0, standardBodyLineHeight * 0.68 * textScale)
        let cleanTranslated = translatedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasTranslation = !cleanTranslated.isEmpty

        if paragraph.isTable, let tableSlice = paragraph.figureSlice {
            // 📊 1. Table Block: Preserved 100% intact as a whole table
            let tableW = min(containerWidth, tableSlice.originalRect.width * textScale)
            let tableAspect = tableSlice.aspectRatio > 0 ? tableSlice.aspectRatio : 1.4
            let tableH = tableW / tableAspect

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer(minLength: 0)
                    SliceImageView(image: tableSlice.image, theme: theme, invertDark: invertDark)
                        .frame(width: tableW, height: tableH)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: containerWidth)
        } else if paragraph.isSideBySide, let sideFig = paragraph.sideFigure {
            // 🖼️ & 📝 2. Side-by-Side: Text and Image in the same horizontal row
            let minSideWidth: CGFloat = 360.0
            let rawSideText = paragraph.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if containerWidth >= minSideWidth {
                let figW = min(240.0, max(120.0, containerWidth * 0.38))
                let figAspect = sideFig.aspectRatio > 0 ? sideFig.aspectRatio : 1.0
                let figH = figW / figAspect
                let textW = containerWidth - figW - 16.0

                HStack(alignment: .top, spacing: 16) {
                    if !paragraph.figureOnRight {
                        SliceImageView(image: sideFig.image, theme: theme, invertDark: invertDark)
                            .frame(width: figW, height: figH)
                            .cornerRadius(6)
                            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)

                        renderTextColumn(rawText: rawSideText, cleanTranslated: cleanTranslated, hasTranslation: hasTranslation, width: textW, baseFontSize: baseFontSize, textColor: textColor)
                    } else {
                        renderTextColumn(rawText: rawSideText, cleanTranslated: cleanTranslated, hasTranslation: hasTranslation, width: textW, baseFontSize: baseFontSize, textColor: textColor)

                        SliceImageView(image: sideFig.image, theme: theme, invertDark: invertDark)
                            .frame(width: figW, height: figH)
                            .cornerRadius(6)
                            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                    }
                }
                .frame(width: containerWidth, alignment: .leading)
            } else {
                let figW = min(containerWidth, sideFig.originalRect.width * textScale)
                let figAspect = sideFig.aspectRatio > 0 ? sideFig.aspectRatio : 1.0
                let figH = figW / figAspect

                VStack(alignment: .leading, spacing: lineSpacing) {
                    HStack {
                        Spacer(minLength: 0)
                        SliceImageView(image: sideFig.image, theme: theme, invertDark: invertDark)
                            .frame(width: figW, height: figH)
                            .cornerRadius(6)
                        Spacer(minLength: 0)
                    }

                    renderTextColumn(rawText: rawSideText, cleanTranslated: cleanTranslated, hasTranslation: hasTranslation, width: containerWidth, baseFontSize: baseFontSize, textColor: textColor)
                }
                .frame(width: containerWidth, alignment: .leading)
            }
        } else if paragraph.isFigure, let figSlice = paragraph.figureSlice {
            // 🖼️ 3. Standalone Figure / Diagram: Preserved 100% intact, scaled cleanly and centered
            let figAspect = figSlice.aspectRatio > 0 ? figSlice.aspectRatio : 1.0
            let figW = min(containerWidth, figSlice.originalRect.width * textScale)
            let figH = figW / figAspect

            HStack {
                Spacer(minLength: 0)
                SliceImageView(image: figSlice.image, theme: theme, invertDark: invertDark)
                    .frame(width: figW, height: figH)
                    .cornerRadius(6)
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                Spacer(minLength: 0)
            }
            .frame(width: containerWidth)
        } else {
            // ✨ 4. Text Paragraph (Vector Text, Image Slice, Translated, or Bilingual)
            let rawText = paragraph.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            renderTextColumn(
                rawText: rawText,
                cleanTranslated: cleanTranslated,
                hasTranslation: hasTranslation,
                width: containerWidth,
                baseFontSize: baseFontSize,
                textColor: textColor
            )
            .contextMenu {
                let copyText = (translationMode == .translated && hasTranslation) ? cleanTranslated : rawText
                if !copyText.isEmpty {
                    Button(action: {
                        PlatformClipboard.copy(copyText)
                    }) {
                        Label(l10n.copyParagraph, systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renderTextColumn(
        rawText: String,
        cleanTranslated: String,
        hasTranslation: Bool,
        width: CGFloat,
        baseFontSize: CGFloat,
        textColor: Color
    ) -> some View {
        if translationMode == .translated && hasTranslation {
            // Translated-only mode: render translated text cleanly in vector typography
            renderVectorParagraph(
                text: cleanTranslated,
                width: width,
                baseFontSize: baseFontSize,
                textColor: textColor
            )
        } else if translationMode == .bilingual && hasTranslation {
            // Bilingual mode: original paragraph (vector or glyph slices) + accented translation block below
            VStack(alignment: .leading, spacing: max(6.0, lineSpacing * 0.6)) {
                renderOriginalParagraphContent(rawText: rawText, width: width, baseFontSize: baseFontSize, textColor: textColor)

                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor.opacity(0.65))
                        .frame(width: 3)

                    renderVectorParagraph(
                        text: cleanTranslated,
                        width: max(80.0, width - 16.0),
                        baseFontSize: baseFontSize * 0.95,
                        textColor: textColor.opacity(0.86)
                    )
                }
                .padding(.vertical, 4)
                .padding(.leading, 2)
            }
            .frame(width: width, alignment: .leading)
        } else {
            // Original mode (or while waiting for translation)
            renderOriginalParagraphContent(rawText: rawText, width: width, baseFontSize: baseFontSize, textColor: textColor)
        }
    }

    @ViewBuilder
    private func renderOriginalParagraphContent(
        rawText: String,
        width: CGFloat,
        baseFontSize: CGFloat,
        textColor: Color
    ) -> some View {
        if useVectorText {
            if !rawText.isEmpty {
                renderVectorParagraph(
                    text: rawText,
                    width: width,
                    baseFontSize: baseFontSize,
                    textColor: textColor
                )
            } else if paragraph.words.contains(where: { $0.originalRect.width > 80 && $0.originalRect.height > 40 }) {
                // Substantial graphic illustration without OCR text: render intact centered
                let wrappedLines = computeWrappedLines(forWidth: width)
                VStack(alignment: .center, spacing: lineSpacing) {
                    ForEach(wrappedLines) { line in
                        renderLineRow(line: line, lineWidth: width, isCentered: true, isHeader: false)
                    }
                }
            }
            // Minor icon speckles, divider fragments, and bounding noise without text are cleanly suppressed
        } else {
            let wrappedLines = computeWrappedLines(forWidth: width)
            let isCentered = paragraph.isTitle || paragraph.semanticLevel == .footer
            let isHeader = paragraph.semanticLevel == .header
            let isCaption = paragraph.semanticLevel == .caption
            let isFooter = paragraph.semanticLevel == .footer

            VStack(alignment: isCentered ? .center : (isHeader ? .trailing : .leading), spacing: lineSpacing) {
                ForEach(wrappedLines) { line in
                    renderLineRow(line: line, lineWidth: width, isCentered: isCentered, isHeader: isHeader)
                }
            }
            .frame(width: width, alignment: isCentered ? .center : (isHeader ? .trailing : .leading))
            .opacity(isFooter || isHeader ? 0.65 : (isCaption ? 0.82 : 1.0))
            .padding(.top, paragraph.isTitle ? 10 : (paragraph.semanticLevel == .sectionHeader ? 8 : (isFooter ? 14 : 0)))
            .padding(.bottom, paragraph.isTitle ? 8 : (isHeader ? 8 : (isCaption ? 4 : 0)))
        }
    }

    @ViewBuilder
    private func renderVectorParagraph(
        text: String,
        width: CGFloat,
        baseFontSize: CGFloat,
        textColor: Color
    ) -> some View {
        let level = paragraph.semanticLevel
        let fontSize = baseFontSize * level.scaleRatio

        switch level {
        case .title:
            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .lineSpacing(lineSpacing)
                .frame(width: width, alignment: .center)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .textSelection(.enabled)

        case .sectionHeader:
            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(lineSpacing)
                .frame(width: width, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .textSelection(.enabled)

        case .subHeader:
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(lineSpacing)
                .frame(width: width, alignment: .leading)
                .padding(.top, 4)
                .textSelection(.enabled)

        case .salutation:
            Text(text)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(lineSpacing)
                .frame(width: width, alignment: .leading)
                .textSelection(.enabled)

        case .header:
            Text(text)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundColor(textColor.opacity(0.65))
                .multilineTextAlignment(.trailing)
                .lineSpacing(lineSpacing)
                .frame(width: width, alignment: .trailing)
                .padding(.bottom, 4)
                .textSelection(.enabled)

        case .footer:
            Text(text)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundColor(textColor.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(lineSpacing)
                .frame(width: width, alignment: .center)
                .padding(.top, 12)
                .textSelection(.enabled)

        case .caption:
            Text(text)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundColor(textColor.opacity(0.80))
                .multilineTextAlignment(.leading)
                .lineSpacing(max(3.0, lineSpacing * 0.75))
                .frame(width: width, alignment: .leading)
                .textSelection(.enabled)

        case .body:
            let hasCjk = text.range(of: "\\p{Han}", options: .regularExpression) != nil
            let indentPrefix = hasCjk ? "　　" : "    "
            let displayText = (paragraph.hasIndent && !text.hasPrefix("　") && !text.hasPrefix("  ")) ? (indentPrefix + text) : text
            Text(displayText)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(lineSpacing)
                .frame(width: width, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func renderLineRow(line: RenderLine, lineWidth: CGFloat, isCentered: Bool = false, isHeader: Bool = false) -> some View {
        HStack(spacing: wordSpacing) {
            if isCentered || isHeader {
                Spacer(minLength: 0)
            } else if line.indentWidth > 0 {
                Color.clear.frame(width: line.indentWidth, height: 1)
            }

            ForEach(line.items) { item in
                SliceImageView(image: item.word.image, theme: theme, invertDark: invertDark)
                    .frame(width: item.glyphWidth, height: item.glyphHeight)
                    .padding(.bottom, item.bottomBaselineOffset)
                    .frame(
                        width: item.renderWidth,
                        height: item.lineHeight,
                        alignment: item.bottomBaselineOffset > 0 ? .bottomLeading : .center
                    )
            }

            if isCentered {
                Spacer(minLength: 0)
            } else if !isHeader {
                Spacer(minLength: 0)
            }
        }
        .frame(width: lineWidth, alignment: isCentered ? .center : (isHeader ? .trailing : .leading))
    }

    private struct RenderWordItem: Identifiable {
        let id: UUID
        let word: WordSlice
        let glyphWidth: CGFloat
        let glyphHeight: CGFloat
        let renderWidth: CGFloat
        let lineHeight: CGFloat
        let bottomBaselineOffset: CGFloat
    }

    private struct RenderLine: Identifiable {
        let id = UUID()
        let indentWidth: CGFloat
        let items: [RenderWordItem]
    }

    private func computeWrappedLines(forWidth targetWidth: CGFloat) -> [RenderLine] {
        guard !paragraph.words.isEmpty else { return [] }

        // Standard rendered line height for this paragraph
        let targetLineHeight = max(18.0, paragraph.baseLineHeight * textScale)
        // Indentation for paragraph first line (standard 2 Chinese characters ~ 1.8x line height)
        let indentWidth: CGFloat = paragraph.hasIndent ? (targetLineHeight * 1.8) : 0.0

        // Determine the natural source pixel size of standard full-height characters in this paragraph
        let sortedHeights = paragraph.words.map { $0.originalRect.height }.sorted()
        let sortedWidths = paragraph.words.map { $0.originalRect.width }.sorted()
        let p75H = sortedHeights.isEmpty ? paragraph.baseLineHeight : sortedHeights[(sortedHeights.count * 3) / 4]
        let p75W = sortedWidths.isEmpty ? paragraph.baseLineHeight : sortedWidths[(sortedWidths.count * 3) / 4]
        let naturalSourceHeight = max(16.0, max(p75H, min(p75W, p75H * 1.8)))

        var lines: [RenderLine] = []
        var currentItems: [RenderWordItem] = []
        var isFirstLine = true
        var currentLineWidth: CGFloat = 0.0

        for word in paragraph.words {
            // Horizontal PDF word slices already have full line height (>= 0.60 * naturalSourceHeight),
            // preserving exact original baseline/capline positioning of all punctuation (，。、“”.) inside the slice.
            // Tight-cropped vertical-book glyphs (< 0.60 * naturalSourceHeight, e.g. "一" or vertical punctuation)
            // scale relative to naturalSourceHeight so they are not stretched vertically.
            let isTightCroppedVerticalGlyph = word.originalRect.height < naturalSourceHeight * 0.60
            let refH = isTightCroppedVerticalGlyph
                ? max(naturalSourceHeight * 0.90, word.originalRect.height)
                : max(1.0, word.originalRect.height)
            let glyphScale = targetLineHeight / refH
            let glyphW = max(2.0, word.originalRect.width * glyphScale)
            let glyphH = max(2.0, min(targetLineHeight, word.originalRect.height * glyphScale))

            // For tight-cropped small punctuation from vertical-to-horizontal books (，。、),
            // give natural horizontal breathing room and anchor near the lower-left baseline instead of vertical center
            let isTightPunctuation = isTightCroppedVerticalGlyph && (glyphW <= targetLineHeight * 0.42) && (glyphH <= targetLineHeight * 0.48)
            let itemWidth = isTightPunctuation ? max(glyphW, targetLineHeight * 0.34) : glyphW
            let baselineOffset: CGFloat = isTightPunctuation ? (targetLineHeight * 0.14) : 0.0

            let lineAvailWidth = isFirstLine ? (targetWidth - indentWidth) : targetWidth

            let renderItem = RenderWordItem(
                id: word.id,
                word: word,
                glyphWidth: glyphW,
                glyphHeight: glyphH,
                renderWidth: itemWidth,
                lineHeight: targetLineHeight,
                bottomBaselineOffset: baselineOffset
            )

            if currentItems.isEmpty {
                currentItems.append(renderItem)
                currentLineWidth = itemWidth
            } else if currentLineWidth + wordSpacing + itemWidth <= lineAvailWidth {
                currentItems.append(renderItem)
                currentLineWidth += wordSpacing + itemWidth
            } else {
                // If this is a narrow punctuation mark (e.g. comma, period, quote) slightly overflowing,
                // allow it to hang at the end of the line (Chinese Kinsoku Shori / 禁则处理)
                let isNarrowPunctuation = itemWidth <= targetLineHeight * 0.45
                if isNarrowPunctuation && (currentLineWidth + wordSpacing + itemWidth <= lineAvailWidth + 14.0) {
                    currentItems.append(renderItem)
                    currentLineWidth += wordSpacing + itemWidth
                } else {
                    // Wrap to next line
                    lines.append(RenderLine(
                        indentWidth: isFirstLine ? indentWidth : 0.0,
                        items: currentItems
                    ))
                    isFirstLine = false
                    currentItems = [renderItem]
                    currentLineWidth = itemWidth
                }
            }
        }

        if !currentItems.isEmpty {
            lines.append(RenderLine(
                indentWidth: isFirstLine ? indentWidth : 0.0,
                items: currentItems
            ))
        }

        return lines
    }
}

/// Fallback Line-level slice row
private struct LineSliceRow: View {
    let slice: PageSlice
    let containerWidth: CGFloat
    let textScale: CGFloat
    let theme: ReadingTheme
    let invertDark: Bool

    var body: some View {
        if slice.isFigure || slice.isTable {
            let aspect = slice.aspectRatio > 0 ? slice.aspectRatio : 1.0
            let figW = min(containerWidth, slice.originalRect.width * textScale)
            let figH = figW / aspect

            HStack {
                Spacer(minLength: 0)
                SliceImageView(image: slice.image, theme: theme, invertDark: invertDark)
                    .frame(width: figW, height: figH)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                Spacer(minLength: 0)
            }
            .frame(width: containerWidth)
        } else {
            let baseColWidth = max(50.0, slice.columnWidth)
            let scale = (containerWidth / baseColWidth) * textScale
            let w = min(containerWidth, slice.originalRect.width * scale)
            let h = slice.originalRect.height * scale

            HStack(spacing: 0) {
                SliceImageView(image: slice.image, theme: theme, invertDark: invertDark)
                    .frame(width: w, height: h, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(width: containerWidth, alignment: .leading)
        }
    }
}

struct SliceImageView: View {
    let image: NSImage
    let theme: ReadingTheme
    let invertDark: Bool

    var body: some View {
        if theme == .dark && invertDark {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .colorInvert()
        } else {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
        }
    }
}
