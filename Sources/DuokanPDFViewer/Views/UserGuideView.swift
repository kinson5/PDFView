import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Concise, richly illustrated multi-language User Guide (serves as both the initial Home View and the Help Sheet)
public struct UserGuideView: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    public var isEmbeddedHome: Bool
    public var onOpenFile: (() -> Void)?
    public var onOpenPhotos: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    public init(
        viewModel: PDFReaderViewModel,
        isEmbeddedHome: Bool = false,
        onOpenFile: (() -> Void)? = nil,
        onOpenPhotos: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.isEmbeddedHome = isEmbeddedHome
        self.onOpenFile = onOpenFile
        self.onOpenPhotos = onOpenPhotos
    }

    private var lang: AppLanguage { viewModel.appLanguage }
    private var l10n: L10n { viewModel.l10n }

    private var surfaceBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }

    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    public var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.width < 620

            VStack(spacing: 0) {
                // Top Header (Only shown in modal User Guide sheet; hidden on home to avoid duplicate app branding)
                if !isEmbeddedHome {
                    if isCompact {
                        HStack(spacing: 12) {
                            appBadgeIcon(size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(guideHeaderTitle)
                                    .font(.headline.bold())
                                Text(guideHeaderSubtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(surfaceBackgroundColor)
                    } else {
                        HStack(spacing: 14) {
                            appBadgeIcon(size: 44)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(guideHeaderTitle)
                                    .font(.title2.bold())
                                Text(guideHeaderSubtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(surfaceBackgroundColor)
                    }

                    Divider()
                }

                // Main Content (Hero Open Entry + Recent Documents + Feature Guide)
                ScrollView {
                    VStack(spacing: 16) {
                        if isEmbeddedHome {
                            // 1. Single Hero Open Document Entry (唯一的打开文档入口)
                            heroOpenDocumentSection(isCompact: isCompact)

                            // 2. Recent Documents History (最新阅读记录)
                            recentDocumentsSection(isCompact: isCompact)
                        } else {
                            detailedFeatureGuideSection(isCompact: isCompact)
                        }
                    }
                    .padding(isCompact ? 14 : 22)
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                }

                Divider()

                // Footer Bar
                if isEmbeddedHome {
                    // Fixed Slogan & Guide Link Bar at bottom: "大文件 → 重排 → 小屏幕" + [使用指南 >]
                    HStack(spacing: 8) {
                        // Slogan: 大文件 → 重排 → 小屏幕
                        HStack(spacing: isCompact ? 5 : 7) {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: isCompact ? 10 : 11))
                                    .foregroundColor(.secondary)
                                Text(sloganBigFiles)
                                    .font(.system(size: isCompact ? 11 : 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }

                            Image(systemName: "arrow.right")
                                .font(.system(size: isCompact ? 9 : 10, weight: .bold))
                                .foregroundColor(.accentColor)

                            HStack(spacing: 3) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: isCompact ? 10 : 11))
                                    .foregroundColor(.accentColor)
                                Text(sloganReflow)
                                    .font(.system(size: isCompact ? 11 : 12, weight: .black, design: .rounded))
                                    .foregroundColor(.accentColor)
                            }

                            Image(systemName: "arrow.right")
                                .font(.system(size: isCompact ? 9 : 10, weight: .bold))
                                .foregroundColor(.accentColor)

                            HStack(spacing: 3) {
                                Image(systemName: "iphone")
                                    .font(.system(size: isCompact ? 10 : 11))
                                    .foregroundColor(.primary)
                                Text(sloganSmallScreen)
                                    .font(.system(size: isCompact ? 11 : 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                        Spacer(minLength: 4)

                        // 右侧单行使用指南链接入口
                        Button(action: {
                            PlatformHaptics.selection()
                            viewModel.showUserGuide = true
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "book.pages.fill")
                                    .font(.system(size: isCompact ? 10 : 11))
                                Text(l10n.userGuideTitle)
                                    .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: isCompact ? 8 : 9, weight: .bold))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, isCompact ? 8 : 10)
                            .padding(.vertical, isCompact ? 4 : 5)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, isCompact ? 12 : 18)
                    .padding(.vertical, 8)
                    .background(surfaceBackgroundColor)
                } else {
                    // Modal Guide Footer with Language tip & Close button
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.orange)
                        Text(l10n.settingsLanguageTip)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button(closeButtonTitle) {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    .padding(.horizontal, isCompact ? 16 : 24)
                    .padding(.vertical, 12)
                    .background(surfaceBackgroundColor)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: isEmbeddedHome ? 640 : 780, minHeight: isEmbeddedHome ? 500 : 610)
        #endif
    }

    @ViewBuilder
    private func appBadgeIcon(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24)
                .fill(LinearGradient(
                    colors: [Color(red: 0.95, green: 0.22, blue: 0.24), Color(red: 0.75, green: 0.08, blue: 0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
                .shadow(color: Color.red.opacity(0.25), radius: 3, x: 0, y: 1.5)

            VStack(spacing: size * 0.04) {
                Text("PDF")
                    .font(.system(size: size * 0.28, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: size * 0.44, height: max(1.5, size * 0.04))
            }
        }
    }

    // MARK: - Recent Documents History Section

    // MARK: - Hero Open Document Section (唯一的打开文档入口)

    @ViewBuilder
    private func heroOpenDocumentSection(isCompact: Bool) -> some View {
        VStack(spacing: 12) {
            #if os(iOS)
            if isCompact {
                VStack(spacing: 10) {
                    Button(action: {
                        PlatformHaptics.impact(.medium)
                        onOpenFile?()
                    }) {
                        Label(l10n.openPDFOrImage, systemImage: "folder.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    if let onOpenPhotos {
                        Button(action: {
                            PlatformHaptics.impact(.light)
                            onOpenPhotos()
                        }) {
                            Label(l10n.importFromPhotos, systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 4)
            } else {
                if let onOpenPhotos {
                    HStack(spacing: 12) {
                        Button(action: {
                            PlatformHaptics.impact(.medium)
                            onOpenFile?()
                        }) {
                            Label(l10n.openPDFOrImage, systemImage: "folder.badge.plus")
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button(action: {
                            PlatformHaptics.impact(.light)
                            onOpenPhotos()
                        }) {
                            Label(l10n.importFromPhotos, systemImage: "photo.on.rectangle.angled")
                                .font(.body.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                } else {
                    Button(action: {
                        PlatformHaptics.impact(.medium)
                        onOpenFile?()
                    }) {
                        Label(l10n.openPDFOrImage, systemImage: "folder.badge.plus")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            #else
            Button(action: { onOpenFile?() }) {
                Label(l10n.openPDFOrImage, systemImage: "folder.badge.plus")
                    .font(.headline)
                    .frame(minWidth: isCompact ? 200 : 250)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: [.command])
            .help("打开 PDF 或图片文件（快捷键 ⌘O，或直接拖拽文件到此窗口）")
            #endif

            HStack(spacing: 8) {
                ForEach(["PDF", "PNG", "JPG", "HEIC", "扫描件", "竖排书刊"], id: \.self) { format in
                    Text(format)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, isCompact ? 14 : 18)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1.2)
        )
    }

    @ViewBuilder
    private func recentDocumentsSection(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label {
                    HStack(spacing: 6) {
                        Text(l10n.recentDocumentsTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                        if !viewModel.recentDocuments.isEmpty {
                            Text("\(viewModel.recentDocuments.count)")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }

                Spacer()

                if !viewModel.recentDocuments.isEmpty {
                    Button(action: {
                        viewModel.clearRecentDocuments()
                    }) {
                        Label(l10n.clearRecentHistory, systemImage: "trash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.clearRecentHistory)
                }
            }

            if viewModel.recentDocuments.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "books.vertical")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(l10n.noRecentDocuments)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: isCompact ? 280 : 320), spacing: 12)
                ]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.recentDocuments) { item in
                        recentDocumentCard(item: item, isCompact: isCompact)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentDocumentCard(item: RecentDocumentItem, isCompact: Bool) -> some View {
        Button(action: {
            viewModel.openRecentDocument(item)
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 40, height: 44)
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Text(l10n.lastReadProgress(page: item.lastPageIndex + 1, total: max(1, item.totalPages)))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let size = item.fileSizeDescription {
                            Text("·")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(size)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if item.totalPages > 0 {
                        let progress = min(1.0, max(0.0, Double(item.lastPageIndex + 1) / Double(item.totalPages)))
                        GeometryReader { barGeo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: 3)
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(width: barGeo.size.width * CGFloat(progress), height: 3)
                            }
                        }
                        .frame(height: 3)
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 4)

                Button(action: {
                    viewModel.removeRecentDocument(item)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("从历史中移除")
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CardPressButtonStyle())
    }

    @ViewBuilder
    private func detailedFeatureGuideSection(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(l10n.quickFeaturesGuide, systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.top, 4)

            guideCard(
                stepNumber: "01",
                badgeColor: .blue,
                title: card1Title,
                bullets: card1Bullets,
                illustration: AnyView(detectTypeIllustration),
                isCompact: isCompact
            )

            guideCard(
                stepNumber: "02",
                badgeColor: .indigo,
                title: card2Title,
                bullets: card2Bullets,
                illustration: AnyView(reflowIllustration),
                isCompact: isCompact
            )

            guideCard(
                stepNumber: "03",
                badgeColor: .teal,
                title: card3Title,
                bullets: card3Bullets,
                illustration: AnyView(gestureAndNavigationIllustration),
                isCompact: isCompact
            )

            guideCard(
                stepNumber: "04",
                badgeColor: .orange,
                title: card4Title,
                bullets: card4Bullets,
                illustration: AnyView(toolbarIllustration),
                isCompact: isCompact
            )

            guideCard(
                stepNumber: "05",
                badgeColor: .purple,
                title: card5Title,
                bullets: card5Bullets,
                illustration: AnyView(manualCropIllustration),
                isCompact: isCompact
            )

            guideCard(
                stepNumber: "06",
                badgeColor: .blue,
                title: card6Title,
                bullets: card6Bullets,
                illustration: AnyView(iCloudSyncIllustration),
                isCompact: isCompact
            )
        }
    }

    // MARK: - Card Template

    @ViewBuilder
    private func guideCard(
        stepNumber: String,
        badgeColor: Color,
        title: String,
        bullets: [String],
        illustration: AnyView,
        isCompact: Bool
    ) -> some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(stepNumber)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(badgeColor))

                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                illustration
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(badgeColor.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(badgeColor.opacity(0.20), lineWidth: 1)
                    )

                ForEach(bullets, id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(badgeColor)
                            .padding(.top, 2)
                        Text(line)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(cardBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.14), lineWidth: 1))
        } else {
            HStack(alignment: .center, spacing: 18) {
                // Left: Visual Diagram Illustration
                illustration
                    .frame(width: 225, height: 118)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(badgeColor.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(badgeColor.opacity(0.20), lineWidth: 1)
                    )

                // Right: Step Title & Concise Bullets
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(stepNumber)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(badgeColor))

                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    ForEach(bullets, id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(badgeColor)
                                .padding(.top, 2)
                            Text(line)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
        }
    }

    // MARK: - Rich Visual Illustrations (图文并茂矢量示意图)

    private var detectTypeIllustration: some View {
        HStack(spacing: 10) {
            // Left Mini Card: Graphic Slices (Default)
            VStack(spacing: 5) {
                HStack(spacing: 3) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("图形文字切片")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.blue)
                }
                HStack(spacing: 2) {
                    ForEach(["原", "汁", "原", "味"], id: \.self) { ch in
                        Text(ch)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(2)
                            .background(RoundedRectangle(cornerRadius: 3).stroke(Color.blue.opacity(0.5), lineWidth: 1))
                    }
                }
                Text("默认原书印刷版式")
                    .font(.system(size: 8.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
            }
            .frame(width: 96, height: 88)
            .background(RoundedRectangle(cornerRadius: 8).fill(surfaceBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.35), lineWidth: 1))

            // Right Mini Card: Vector Text (1-tap toggle)
            VStack(spacing: 5) {
                HStack(spacing: 3) {
                    Image(systemName: "character.textbox")
                        .font(.caption)
                        .foregroundColor(.purple)
                    Text("矢量文字横排")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.purple)
                }
                Text("Aa 零失真缩放")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundColor(.primary)
                Text("长按划词 · 自由选句")
                    .font(.system(size: 8.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.purple.opacity(0.15)))
            }
            .frame(width: 96, height: 88)
            .background(RoundedRectangle(cornerRadius: 8).fill(surfaceBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.35), lineWidth: 1))
        }
        .padding(8)
    }

    private var reflowIllustration: some View {
        HStack(spacing: 10) {
            // Classical Vertical RTL Book Page Simulation
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.square.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.indigo)
                    Text("竖排古籍")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.indigo)
                }

                HStack(spacing: 4) {
                    // RTL vertical columns (right to left)
                    ForEach(0..<3, id: \.self) { col in
                        VStack(spacing: 2) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(col == 2 ? Color.brown : Color.secondary.opacity(0.6))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 14, height: 18)
                        .overlay(Image(systemName: "seal.fill").font(.system(size: 8)).foregroundColor(.red.opacity(0.8)))
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.96, green: 0.93, blue: 0.85)))
            }
            .padding(6)
            .frame(width: 78, height: 88)
            .background(RoundedRectangle(cornerRadius: 6).fill(surfaceBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.indigo.opacity(0.3), lineWidth: 1))

            Image(systemName: "arrow.right.circle.fill")
                .font(.title3)
                .foregroundColor(.indigo)

            // Flowing 1-Column Horizontal Mobile Reading with Intact Seal
            VStack(alignment: .leading, spacing: 4.5) {
                HStack(spacing: 4) {
                    Text("单栏流式畅读")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.indigo)
                    Spacer()
                    Image(systemName: "seal.fill").font(.system(size: 8)).foregroundColor(.red.opacity(0.8))
                }
                RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.7)).frame(height: 3.5)
                RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.7)).frame(height: 3.5)
                RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.7)).frame(height: 3.5)
                RoundedRectangle(cornerRadius: 1.5).fill(Color.indigo).frame(width: 56, height: 3.5)
            }
            .padding(8)
            .frame(width: 98, height: 88)
            .background(RoundedRectangle(cornerRadius: 6).fill(surfaceBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.indigo.opacity(0.45), lineWidth: 1.2))
        }
        .padding(8)
    }

    private var gestureAndNavigationIllustration: some View {
        HStack(spacing: 10) {
            // Left: Swipe gesture
            VStack(spacing: 5) {
                HStack(spacing: 3) {
                    Image(systemName: "hand.draw.fill")
                        .font(.caption)
                        .foregroundColor(.teal)
                    Text("左右轻扫翻页")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.teal)
                }

                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.teal)
                    Image(systemName: "doc.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary.opacity(0.4))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.teal)
                }
                .padding(.vertical, 2)

                Text("横竖排自动顺应")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .frame(width: 92, height: 88)
            .background(RoundedRectangle(cornerRadius: 8).fill(surfaceBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.teal.opacity(0.35), lineWidth: 1))

            // Right: TOC outline & page pill
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.caption)
                        .foregroundColor(.teal)
                    Text("目录大纲 & 跳转")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.teal)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.teal).frame(width: 4, height: 4)
                        Text("第一章 导言与排版").font(.system(size: 8)).foregroundColor(.primary).lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.secondary).frame(width: 4, height: 4)
                        Text("第二章 算法与重排").font(.system(size: 8)).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 4).fill(cardBackgroundColor))

                HStack {
                    Spacer()
                    Text("12 / 180")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.teal.opacity(0.18)))
                        .foregroundColor(.teal)
                    Spacer()
                }
            }
            .frame(width: 104, height: 88)
            .background(RoundedRectangle(cornerRadius: 8).fill(surfaceBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.teal.opacity(0.35), lineWidth: 1))
        }
        .padding(8)
    }

    private var toolbarIllustration: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Label("A-", systemImage: "textformat.size.smaller")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(surfaceBackgroundColor))
                Text("130%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                Label("A+", systemImage: "textformat.size.larger")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(surfaceBackgroundColor))

                // Apple offline translation badge
                HStack(spacing: 2) {
                    Image(systemName: "character.bubble.fill")
                        .font(.system(size: 8))
                    Text("双语对照")
                        .font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
                .foregroundColor(.orange)
            }

            HStack(spacing: 8) {
                Circle().fill(Color.white).frame(width: 17, height: 17)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                Circle().fill(Color(red: 0.96, green: 0.93, blue: 0.84)).frame(width: 17, height: 17)
                    .overlay(Circle().stroke(Color.orange, lineWidth: 1.5))
                Circle().fill(Color(red: 0.85, green: 0.93, blue: 0.86)).frame(width: 17, height: 17)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                Circle().fill(Color(red: 0.16, green: 0.16, blue: 0.18)).frame(width: 17, height: 17)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
            }

            Text("四色护眼纸张 · 设置双语翻译 · 单书进度记忆")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(8)
    }

    private var manualCropIllustration: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(width: 80, height: 60)
                Circle().fill(Color.purple).frame(width: 8, height: 8).offset(x: -40, y: -30)
                Circle().fill(Color.purple).frame(width: 8, height: 8).offset(x: 40, y: -30)
                Circle().fill(Color.purple).frame(width: 8, height: 8).offset(x: 40, y: 30)
                Circle().fill(Color.purple).frame(width: 8, height: 8).offset(x: -40, y: 30)
                Image(systemName: "crop")
                    .font(.system(size: 20))
                    .foregroundColor(.purple)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("四角拖拽精准纠偏")
                    .font(.caption.bold())
                    .foregroundColor(.purple)
                Text("拖拽四角矫正页面倾斜与梯形，去除四周杂乱背景与黑边")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
    }

    private var iCloudSyncIllustration: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 80, height: 60)
                Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("iCloud 进度毫秒同步")
                    .font(.caption.bold())
                    .foregroundColor(.blue)
                Text("同名图书自动匹配，已读页码与切边数据多端实时共享")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
    }

    // MARK: - Localized Guide Content (中简 / 中繁 / EN / DE / JA)


    private var guideHeaderTitle: String {
        if isEmbeddedHome {
            switch lang {
            case .zhHans: return "PDFview 智能阅读器"
            case .zhHant: return "PDFview 智慧閱讀器"
            case .en: return "PDFview Smart Reader"
            case .de: return "PDFview Smart Reader"
            case .ja: return "PDFview スマートリーダー"
            }
        } else {
            switch lang {
            case .zhHans: return "PDFview 快速使用指南"
            case .zhHant: return "PDFview 快速使用指南"
            case .en: return "PDFview Quick Start Guide"
            case .de: return "PDFview Kurzanleitung"
            case .ja: return "PDFview クイックガイド"
            }
        }
    }

    private var guideHeaderSubtitle: String {
        if isEmbeddedHome {
            return l10n.homeHeroSubSlogan
        } else {
            switch lang {
            case .zhHans: return "图形与矢量自由切换 · 独立竖排古籍重排 · 手势与目录大纲 · 设置集成双语翻译"
            case .zhHant: return "圖形與向量自由切換 · 獨立直排古籍重排 · 手勢與目錄大綱 · 設定整合雙語翻譯"
            case .en: return "Graphic & Vector Reflow · Dedicated Vertical Checkbox · Gestures & TOC · Bilingual Translation"
            case .de: return "Bild- & Vektorumfluss · Eigene Vertikal-Checkbox · Wischgesten & Inhaltsverzeichnis · Übersetzung"
            case .ja: return "画像・ベクター切替 · 専用縦書きチェック · スワイプ＆目次連動 · 設定内多言語翻訳"
            }
        }
    }

    private var card1Title: String {
        switch lang {
        case .zhHans: return "图形切片与矢量文字横排 · 毫秒级秒开"
        case .zhHant: return "圖形切片與向量文字橫排 · 毫秒級秒開"
        case .en: return "Graphic Slices & Vector Text Reflow · Instant Open"
        case .de: return "Bildschnitte & Vektortext-Umfluss · Sofort-Öffnen"
        case .ja: return "画像スライス＆ベクター文字横書き · 瞬時表示"
        }
    }

    private var card1Bullets: [String] {
        switch lang {
        case .zhHans:
            return [
                "打开文档即刻呈现原始页面，无需等待重排耗时；就绪后默认采用高清晰「图形文字横排」切片，100% 保留原书印刷版式与插图。",
                "顶栏直接点击「文字」按钮，即可无缝切换为「矢量文字横排」，享受 50%–300% 零失真缩放与原生 iOS 长按划词选句复制。",
                "无论纯文字 PDF、复杂扫描文档、本地超长图还是手机相册照片，智能算法毫秒级切分段落与图表，支持长图完整重排，彻底杜绝文字错乱与截断。"
            ]
        case .zhHant:
            return [
                "開啟檔案即刻呈現原始頁面，無需等待重排耗時；就緒後預設採用高解析「圖形文字橫排」切片，100% 保留原書印刷版式與插圖。",
                "頂列直接點擊「文字」按鈕，即可無縫切換為「向量文字橫排」，享受 50%–300% 零失真縮放與原生 iOS 長按劃詞選句複製。",
                "無論純文字 PDF、複雜掃描文件、本地超長圖還是手機相簿照片，智慧演算法毫秒級切分段落與圖表，支援長圖完整重排，徹底杜絕文字錯亂與截斷。"
            ]
        case .en:
            return [
                "Opens documents instantly in Original layout without waiting; reflow automatically defaults to high-fidelity 'Graphic Slices' to preserve authentic typography and illustrations.",
                "Tap 'Text' in the top bar anytime to switch to 'Vector Text Reflow' for 50%–300% lossless scaling and native iOS long-press text selection.",
                "Intelligently segments text paragraphs and inline diagrams from text PDFs, scans, camera photos, and panoramic long images with full reflow support."
            ]
        case .de:
            return [
                "Dokumente öffnen sich sofort in der Originalansicht ohne Wartezeit; der Umfluss startet standardmäßig mit originalgetreuen Bildschnitten.",
                "Tippen Sie oben auf 'Text', um verlustfreien Vektortext (50%–300% Zoom) und native Textauswahl per langem Druck zu nutzen.",
                "Segmentiert Absätze und Abbildungen aus Text-PDFs, Scans, Kamerafotos und ultralangen Bildern präzise ohne Textüberlappungen."
            ]
        case .ja:
            return [
                "ファイルを開くと待ち時間なく元ページを即時表示。リフロー完了後は原本の印刷組版や図版を忠実に再現する「画像スライス横書き」で表示します。",
                "上部ツールバーの「文字」をタップすれば「ベクター文字横書き」へ即座に切替可能。50%〜300%の無劣化拡大や長押しテキスト選択に対応。",
                "テキストPDF、高精細スキャン、スマホ写真、超縦長画像のいずれも、段落や図表を自動認識して完全に再構築します。"
            ]
        }
    }

    private var card2Title: String {
        switch lang {
        case .zhHans: return "独立竖排复选框 · 古籍善本单栏流式重排"
        case .zhHant: return "獨立直排核取方塊 · 古籍善本單欄流式重排"
        case .en: return "Dedicated Vertical Checkbox · Flowing Ancient Books"
        case .de: return "Eigene Vertikal-Checkbox · Nahtloser Lesefluss für Klassiker"
        case .ja: return "専用の縦書きチェックボックス · 古籍の流れるような再構成"
        }
    }

    private var card2Bullets: [String] {
        switch lang {
        case .zhHans:
            return [
                "顶栏专设独立「[✓] 竖排」复选框，一键直观开关，拒绝复杂的多层菜单，极简操作完美契合手机使用习惯。",
                "针对古籍善本、竖排古卷与右起（RTL）书刊，智能按列逆序解构成舒适的由左至右单栏流式阅读，文字顺滑连贯。",
                "双栏论文、图书插图、照片印章完整内嵌于段落之中；底栏可随时在「智能重排」、「原始版面」与「双屏对照」间切换。"
            ]
        case .zhHant:
            return [
                "頂列專設獨立「[✓] 直排」核取方塊，一鍵直觀開關，拒絕複雜的多層選單，極簡操作完美契合手機使用習慣。",
                "針對古籍善本、直排古卷與由右至左（RTL）書刊，智慧按列逆序解構成舒適的由左至右單欄流式閱讀，文字順滑連貫。",
                "雙欄論文、圖書插圖、照片印章完整內嵌於段落之中；底列可隨時在「智慧重排」、「原始版面」與「雙屏對照」間切換。"
            ]
        case .en:
            return [
                "Dedicated '[✓] Vertical' checkbox in the top bar toggles vertical layout with 1 tap, eliminating complex nested menus.",
                "Intelligently deconstructs right-to-left (RTL) vertical columns in classical books into a natural, flowing single-column mobile layout.",
                "Preserves figures, charts, and seals inline between paragraphs; toggle between Reflow, Original, and Split View at the bottom."
            ]
        case .de:
            return [
                "Die eigene '[✓] Vertikal'-Checkbox in der oberen Leiste schaltet vertikalen Lesefluss mit 1 Klick um – ganz ohne Untermenüs.",
                "Wandelt klassische vertikale Textspalten von rechts nach links (RTL) automatisch in einen flüssigen einspaltigen Lesefluss um.",
                "Abbildungen, Tabellen und Stempel bleiben im Text eingebettet; Wechsel zwischen Umfluss, Original und geteilter Ansicht in der Fußleiste."
            ]
        case .ja:
            return [
                "ツールバー専用の「[✓] 縦書き」チェックボックスで迷わず切り替え。深いメニュー操作をなくし、スマホの片手操作に最適化。",
                "伝統的な右起こしの縦書き書籍や古典籍を、スマホで快適に読める自然な横書き1カラムの流れるレイアウトに自動再構成。",
                "挿絵や図表、落款印は段落の間に鮮明に保持。「リフロー」「元ページ」「見開き比較」は下のバーからいつでも切替可能。"
            ]
        }
    }

    private var card3Title: String {
        switch lang {
        case .zhHans: return "严密整页翻页、全书大纲与精简图案工具栏"
        case .zhHant: return "嚴密整頁翻頁、全書大綱與精簡圖案工具列"
        case .en: return "Strict Full-Page Swipe, TOC & Compact Icon Toolbar"
        case .de: return "Präzises seitenweises Blättern, Inhaltsverzeichnis & Icons"
        case .ja: return "正確な全ページ送り・目次しおり連動・アイコンツールバー"
        }
    }

    private var card3Bullets: [String] {
        switch lang {
        case .zhHans:
            return [
                "左右轻扫严密整页切换，彻底告别滑动半页卡顿或停滞；针对竖排古籍自动反转翻页手势，完美顺应传统翻书习惯。",
                "点击底部居中的页码胶囊，快速呼出全书多级目录大纲与精准跳转滑块，百页长书任意章节一触即达。",
                "顶栏全图案紧凑功能集：✂️ 图片切边纠偏、📋 一键复制全文、🔄 顺时针 90° 旋转、⚙️ 全屏设置，小屏手机亦不溢出。"
            ]
        case .zhHant:
            return [
                "左右輕掃嚴密整頁切換，徹底告別滑動半頁卡頓或停滯；針對直排古籍自動反轉翻頁手勢，完美順應傳統翻書習慣。",
                "點擊底部居中的頁碼膠囊，快速呼出全書多級目錄大綱與精準跳轉滑桿，百頁長書任意章節一觸即達。",
                "頂列全圖案緊湊功能集：✂️ 手動切邊糾偏、📋 一鍵複製全文、🔄 順時針 90° 旋轉、⚙️ 全螢幕設定，小螢幕手機亦不溢出。"
            ]
        case .en:
            return [
                "Strict full-page swipe ensures crisp page transitions without awkward half-page stops; swipe direction adapts to right-to-left vertical books.",
                "Tap the center page pill at the bottom to open hierarchical table of contents (TOC), bookmarks, and precision slider.",
                "Compact icon toolbar: ✂️ Manual Crop & Deskew, 📋 Copy Full Page Text, 🔄 Rotate 90° CW, and ⚙️ Fullscreen Settings."
            ]
        case .de:
            return [
                "Präzises seitenweises Wischen garantiert saubere Übergänge ohne Hängenbleiben; die Wischrichtung passt sich vertikalen Büchern an.",
                "Tippen Sie auf die Seitenzahl in der Fußleiste, um das hierarchische Inhaltsverzeichnis und den Seitenschieberegler zu öffnen.",
                "Kompakte Symbolleiste: ✂️ Manuelles Entzerren, 📋 Volltext kopieren, 🔄 90° Drehung und ⚙️ Vollbild-Einstellungen."
            ]
        case .ja:
            return [
                "左右スワイプで厳密に1ページごと切替。途中で止まる引っ掛かりを解消し、縦書き本では伝統的なめくり方向に自動適応。",
                "下部中央のページ番号をタップすると、階層付き目次大綱としおり、高速ジャンプ用スライダーがスムーズに展開します。",
                "スッキリとしたアイコンツールバー：✂️ 切辺・傾き補正、📋 全文コピー、🔄 時計回り90°回転、⚙️ 全画面設定。"
            ]
        }
    }

    private var card4Title: String {
        switch lang {
        case .zhHans: return "四色护眼纸张、设置双语翻译与单书记忆"
        case .zhHant: return "四色護眼紙張、設定雙語翻譯與單書記憶"
        case .en: return "Eye-Care Paper Themes, Bilingual Translation & Memory"
        case .de: return "Papierthemen, Einstellungen-Übersetzung & Buchspeicher"
        case .ja: return "4色の用紙テーマ・設定内多言語翻訳・読書履歴記憶"
        }
    }

    private var card4Bullets: [String] {
        switch lang {
        case .zhHans:
            return [
                "纯白、羊皮羊绒护眼、豆沙绿意与夜间暗黑四种温润纸张主题，搭配三档紧凑/适中/宽松行距与字号调节。",
                "设置面板集成 Apple 原生离线双语对照翻译，原生文字或 OCR 扫描件均可一键翻译为中繁英德日法等数十种语言。",
                "每本书的阅读进度、字号排版、纸张主题、竖排选择独立自动记忆，下次打开无缝继续精彩阅读。"
            ]
        case .zhHant:
            return [
                "純白、羊皮羊絨護眼、豆沙綠意與夜間暗黑四種溫潤紙張主題，搭配三檔緊湊/適中/寬鬆行距與字級調節。",
                "設定面板整合 Apple 原生離線雙語對照翻譯，原生文字或 OCR 掃描檔均可一鍵翻譯為中繁英德日法等數十種語言。",
                "每本書的閱讀進度、字級排版、紙張主題、直排選擇獨立自動記憶，下次開啟無縫繼續精彩閱讀。"
            ]
        case .en:
            return [
                "Four warm eye-care paper themes (White, Sepia, Soft Green, Night Dark) with 3 line-spacing options and font scaling.",
                "Settings panel integrates native Apple offline bilingual translation for both text PDFs and OCR scans across dozens of languages.",
                "Automatically remembers last read page, font size, paper theme, and vertical layout toggle for each individual document."
            ]
        case .de:
            return [
                "Vier augenfreundliche Papierthemen (Weiß, Sepia, Salbeigrün, Nachtmodus) mit 3 Zeilenabständen und Schriftgrößenanpassung.",
                "Einstellungen bieten integrierte Apple-Offline-Zweisprachübersetzung für Text-PDFs und Scans in Dutzenden von Sprachen.",
                "Speichert Lesefortschritt, Schriftgröße, Thema und Vertikal-Einstellung für jedes Buch separat zur nahtlosen Fortsetzung."
            ]
        case .ja:
            return [
                "ホワイト・羊皮紙セピア・若草グリーン・ダークの4種類の目に優しい用紙テーマと3段階の行間設定を完備。",
                "設定画面にApple内蔵のオフライン二ヶ国語翻訳を統合。テキストPDFやOCR認識テキストを日英独仏など多彩な言語へ即座に対訳。",
                "読書進度、文字サイズ、用紙テーマ、縦書き設定を開いた本ごとに個別自動保存。いつでも続きから読書を再開できます。"
            ]
        }
    }

    private var card5Title: String {
        switch lang {
        case .zhHans: return "手动切边与方框倾斜纠偏 · 复杂页面智能矫正"
        case .zhHant: return "手動切邊與方框傾斜糾偏 · 複雜頁面智慧矯正"
        case .en: return "Manual Crop & Quadrilateral De-skew · Perspective Correction"
        case .de: return "Manuelles Zuschneiden & Entzerren · Perspektivkorrektur"
        case .ja: return "手動トリミング＆台形補正 · 傾きを自在に矯正"
        }
    }

    private var card5Bullets: [String] {
        switch lang {
        case .zhHans:
            return [
                "针对手机拍摄倾斜、书脊弯曲、黑边过宽或包含杂乱桌面的照片与长图，提供高精度四角与四边交互式拖拽选区。",
                "系统根据自定义方框实时进行透视拉伸纠正（Perspective Correction），将倾斜梯形瞬间摆正为标准平直矩形。",
                "彻底切除黑边与四周杂色，为后续文字切片重排提供纯净高质量的页面源，大幅提升排版与识别精度。"
            ]
        case .zhHant:
            return [
                "針對手機拍攝傾斜、書脊彎曲、黑邊過寬或包含雜亂桌面的照片與長圖，提供高精度四角與四邊互動式拖曳選區。",
                "系統根據自訂方框即時進行透視拉伸糾正（Perspective Correction），將傾斜梯形瞬間擺正為標準平直矩形。",
                "徹底切除黑邊與四周雜色，為後續文字切片重排提供純淨高品質的頁面源，大幅提升排版與識別精度。"
            ]
        case .en:
            return [
                "Interactive 4-corner and edge-handle quadrilateral dragging tailored for tilted camera captures, long images, and scanned books.",
                "Automatically applies hardware-accelerated CIPerspectiveCorrection to unwarp keystoning and tilt into a crisp rectangle.",
                "Trims external clutter and black scanner margins, ensuring the downstream reflow engine operates on a clean page source."
            ]
        case .de:
            return [
                "Interaktives 4-Ecken- und Kanten-Ziehen speziell für schräg aufgenommene Buchfotos, lange Bilder und Scans.",
                "Korrigiert Trapezverzerrungen und Schräglagen automatisch anhand des gewählten Rahmens in ein gerades Rechteck.",
                "Schneidet dunkle Scanränder und Hintergrundobjekte sauber ab für eine optimale Textsegmentierung."
            ]
        case .ja:
            return [
                "スマホで撮影した斜めの本、長画像、歪みのあるスキャン向けに、直感的な4隅ドラッグによる自由枠選択を搭載。",
                "指定した4点枠に基づいてパースペクティブ補正（遠近感補正）を即座に適用し、歪んだ台形を真正面の長方形へ矯正。",
                "黒枠や余白の余計な映り込みを切り落とし、リフローエンジンが正確な行分割を行えるよう清書します。"
            ]
        }
    }

    private var card6Title: String {
        switch lang {
        case .zhHans: return "iCloud 跨设备阅读进度无缝同步"
        case .zhHant: return "iCloud 跨設備閱讀進度無縫同步"
        case .en: return "iCloud Multi-Device Reading Progress Sync"
        case .de: return "Nahtloser iCloud-Lesefortschritt über alle Geräte"
        case .ja: return "iCloud マルチデバイス読書進度シームレス同期"
        }
    }

    private var card6Bullets: [String] {
        switch lang {
        case .zhHans:
            return [
                "轻量书名自动匹配：只要在不同设备上打开同名图书，即可自动读取云端进度对齐页码，无需上传几百兆大文件。",
                "通过 Apple iCloud 键值存储毫秒级静默同步：已读页码、排版模式、缩放比例与切边数据多端实时共享。",
                "零空间占用与零流量负担，离线完全可用；通勤在 iPhone 上看一半，回家在 Mac 上拿起即读。"
            ]
        case .zhHant:
            return [
                "輕量書名自動匹配：只要在不同設備上打開同名圖書，即可自動讀取雲端進度對齊頁碼，無需上傳幾百兆大檔案。",
                "透過 Apple iCloud 鍵值儲存毫秒級靜默同步：已讀頁碼、排版模式、縮放比例與切邊數據多端即時共享。",
                "零空間佔用與零流量負擔，離線完全可用；通勤在 iPhone 上看一半，回家在 Mac 上拿起即讀。"
            ]
        case .en:
            return [
                "Instant Title Matching: Open the same-named book on any device to automatically sync progress without uploading bulky files.",
                "Real-time Key-Value Sync: Reading page index, reflow layout mode, zoom scale, and manual crop data sync silently via iCloud.",
                "Zero storage overhead and zero cellular waste; completely offline-ready, seamlessly resume between iPhone, iPad, and Mac."
            ]
        case .de:
            return [
                "Automatischer Titel-Abgleich: Öffnen Sie dasselbe Buch auf einem beliebigen Gerät, um die Seite ohne Datei-Upload fortzusetzen.",
                "Echtzeit-Synchronisation: Aktuelle Seitenzahl, Umflussmodus, Zoom und Zuschnittsdaten werden per iCloud abgeglichen.",
                "Kein Speicherplatz- oder Datenverbrauch; offline nutzbar, nahtloser Wechsel zwischen iPhone, iPad und Mac."
            ]
        case .ja:
            return [
                "書名による自動マッチング：同名の書籍を開くだけで、大容量ファイルを転送することなく進度を自動同期。",
                "iCloudキー値ストアによる瞬時同期：既読ページ、リフロー表示、拡大率、手動切辺データをリアルタイム共有。",
                "容量・通信量の消費ゼロで完全オフライン対応。iPhoneで読んだ続きを、Macの大画面ですぐに再開できます。"
            ]
        }
    }

    private var footerTip: String {
        switch lang {
        case .zhHans: return "提示：可在偏好设置中随时切换多国语言、设置双语翻译，或点击「?」重新打开本指南。"
        case .zhHant: return "提示：可在偏好設定中隨時切換多國語言、設定雙語翻譯，或點擊「?」重新開啟本指南。"
        case .en: return "Tip: Switch languages or configure bilingual translation in Settings, or tap ? to reopen this guide."
        case .de: return "Tipp: Sprache und Übersetzung in den Einstellungen anpassen oder ? tippen, um diese Anleitung zu öffnen."
        case .ja: return "ヒント：設定画面から表示言語や翻訳を設定可能。「?」でいつでもこのガイドを再表示できます。"
        }
    }

    private var sloganBigFiles: String {
        switch lang {
        case .zhHans: return "大文件"
        case .zhHant: return "大檔案"
        case .en: return "Large Files"
        case .de: return "Große Dateien"
        case .ja: return "大容量文書"
        }
    }

    private var sloganReflow: String {
        switch lang {
        case .zhHans: return "重排"
        case .zhHant: return "重排"
        case .en: return "Reflow"
        case .de: return "Umfluss"
        case .ja: return "リフロー"
        }
    }

    private var sloganSmallScreen: String {
        switch lang {
        case .zhHans: return "小屏幕"
        case .zhHant: return "小螢幕"
        case .en: return "Small Screen"
        case .de: return "Kleines Display"
        case .ja: return "小型画面"
        }
    }

    private var closeButtonTitle: String {
        switch lang {
        case .zhHans: return "开始阅读"
        case .zhHant: return "開始閱讀"
        case .en: return "Start Reading"
        case .de: return "Jetzt lesen"
        case .ja: return "読書を始める"
        }
    }
}

/// Responsive card button style providing immediate touch feedback and smooth scale animation
struct CardPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
