import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Pure Text OCR Reading View: allows fluid reading, real-time font and line spacing synchronization,
/// and native text selection, while seamlessly preserving tables and diagrams.
public struct OCRTextView: View {
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
                } else if let result = viewModel.currentReflowResult, !result.paragraphs.isEmpty {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .center, spacing: 0) {
                            Color.clear.frame(height: 12)

                            // Paragraph stream
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

                                    OCRParagraphRow(
                                        paragraph: paragraph,
                                        containerWidth: containerWidth,
                                        config: viewModel.config,
                                        translationMode: viewModel.translationMode,
                                        translatedText: viewModel.translatedParagraphs[paragraph.id],
                                        theme: theme
                                    )
                                }
                            }
                            .frame(width: containerWidth, alignment: .leading)
                            .padding(.bottom, 40)

                            // Page bottom navigation
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
                        Image(systemName: "character.cursor.ibeam")
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

private struct OCRParagraphRow: View {
    let paragraph: ParagraphBlock
    let containerWidth: CGFloat
    let config: ReflowConfig
    let translationMode: TranslationDisplayMode
    let translatedText: String?
    let theme: ReadingTheme

    var body: some View {
        let textColor = Color(nsColor: theme.textColor)
        let baseFontSize = max(11.0, config.standardBodyLineHeight * 0.68 * config.textScale)
        let cleanTranslated = translatedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasTranslation = !cleanTranslated.isEmpty

        if paragraph.isTable, let tableSlice = paragraph.figureSlice {
            // Table block: preserved intact
            let tableW = min(containerWidth, tableSlice.originalRect.width * config.textScale)
            let tableAspect = tableSlice.aspectRatio > 0 ? tableSlice.aspectRatio : 1.4
            let tableH = tableW / tableAspect

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer(minLength: 0)
                    SliceImageView(image: tableSlice.image, theme: theme, invertDark: config.invertColorsInDarkTheme)
                        .frame(width: tableW, height: tableH)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    Spacer(minLength: 0)
                }
            }
            .frame(width: containerWidth)
        } else if paragraph.isFigure, let figSlice = paragraph.figureSlice {
            // Figure block: preserved intact
            let figAspect = figSlice.aspectRatio > 0 ? figSlice.aspectRatio : 1.0
            let figW = min(containerWidth, figSlice.originalRect.width * config.textScale)
            let figH = figW / figAspect

            HStack {
                Spacer(minLength: 0)
                SliceImageView(image: figSlice.image, theme: theme, invertDark: config.invertColorsInDarkTheme)
                    .frame(width: figW, height: figH)
                    .cornerRadius(6)
                Spacer(minLength: 0)
            }
            .frame(width: containerWidth)
        } else {
            // Text Paragraph
            let level = paragraph.semanticLevel
            let fontSize = baseFontSize * level.scaleRatio
            let text = paragraph.recognizedText ?? ""

            if translationMode == .translated && hasTranslation {
                renderTextBlock(text: cleanTranslated, level: level, fontSize: fontSize, textColor: textColor)
            } else if translationMode == .bilingual && hasTranslation {
                VStack(alignment: .leading, spacing: max(6.0, config.sliceSpacing * 0.6)) {
                    renderTextBlock(text: text, level: level, fontSize: fontSize, textColor: textColor)

                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.accentColor.opacity(0.65))
                            .frame(width: 3)

                        renderTextBlock(text: cleanTranslated, level: level, fontSize: fontSize * 0.95, textColor: textColor.opacity(0.86))
                    }
                    .padding(.vertical, 4)
                    .padding(.leading, 2)
                }
            } else {
                renderTextBlock(text: text, level: level, fontSize: fontSize, textColor: textColor)
            }
        }
    }

    @ViewBuilder
    private func renderTextBlock(text: String, level: SemanticLevel, fontSize: CGFloat, textColor: Color) -> some View {
        switch level {
        case .title:
            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .lineSpacing(config.sliceSpacing)
                .frame(width: containerWidth, alignment: .center)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .textSelection(.enabled)

        case .sectionHeader:
            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(config.sliceSpacing)
                .frame(width: containerWidth, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .textSelection(.enabled)

        case .subHeader:
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(config.sliceSpacing)
                .frame(width: containerWidth, alignment: .leading)
                .padding(.top, 4)
                .textSelection(.enabled)

        case .salutation:
            Text(text)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(config.sliceSpacing)
                .frame(width: containerWidth, alignment: .leading)
                .textSelection(.enabled)

        case .header:
            Text(text)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundColor(textColor.opacity(0.65))
                .multilineTextAlignment(.trailing)
                .lineSpacing(config.sliceSpacing)
                .frame(width: containerWidth, alignment: .trailing)
                .padding(.bottom, 4)
                .textSelection(.enabled)

        case .footer:
            Text(text)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundColor(textColor.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(config.sliceSpacing)
                .frame(width: containerWidth, alignment: .center)
                .padding(.top, 12)
                .textSelection(.enabled)

        case .caption:
            Text(text)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundColor(textColor.opacity(0.78))
                .multilineTextAlignment(.leading)
                .lineSpacing(config.sliceSpacing)
                .frame(width: containerWidth, alignment: .leading)
                .padding(.vertical, 2)
                .textSelection(.enabled)

        case .body:
            let displayText = paragraph.hasIndent ? ("\u{3000}\u{3000}" + text) : text
            Text(displayText)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(config.sliceSpacing)
                .frame(width: containerWidth, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
