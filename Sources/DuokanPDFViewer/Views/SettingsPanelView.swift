import SwiftUI

/// Simplified, foolproof reader settings panel (focusing on comfort and essential controls)
public struct SettingsPanelView: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @ObservedObject private var cloudSync = iCloudSyncService.shared
    @ObservedObject private var proStore = ProStoreService.shared

    public init(viewModel: PDFReaderViewModel) {
        self.viewModel = viewModel
    }

    private var lang: AppLanguage { viewModel.appLanguage }
    private var l10n: L10n { viewModel.l10n }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // 0. Pro Lifetime Status Badge (仅在已解锁后显示状态徽章；未升级前不在弹窗内放链接，避免 Sheet 弹窗层叠冲突)
                if proStore.isProUnlocked {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(proTitleText)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.primary)
                            Text(proUnlockedSubtitleText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))

                    Divider()
                        .padding(.vertical, 2)
                }

                // 1. Reading Paper Theme
                HStack {
                    Text(l10n.paperTheme)
                        .font(.subheadline)
                    Spacer()
                    Picker(l10n.paperTheme, selection: Binding(
                        get: { viewModel.config.readingTheme },
                        set: {
                            viewModel.config.readingTheme = $0
                            viewModel.saveCurrentBookPreference()
                        }
                    )) {
                        ForEach(ReadingTheme.allCases) { theme in
                            Text(l10n.themeTitle(theme)).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if viewModel.config.readingTheme == .dark && !viewModel.isNativeTextPage {
                    Toggle(darkInvertLabel, isOn: $viewModel.config.invertColorsInDarkTheme)
                        .font(.subheadline)
                }

                Divider()
                    .padding(.vertical, 2)

                // 2. Typography & Spacing (Fixed 5-level presets)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(fontSizeLabel)
                            .font(.subheadline)
                        Spacer()
                        let currentOpt = FontSizeOption.closest(to: viewModel.config.textScale)
                        Text("\(currentOpt.title(in: lang)) (\(currentOpt.percentageText))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Picker(fontSizeLabel, selection: Binding(
                        get: { FontSizeOption.closest(to: viewModel.config.textScale) },
                        set: { opt in
                            PlatformHaptics.selection()
                            viewModel.config.textScale = opt.rawValue
                            viewModel.saveCurrentBookPreference()
                        }
                    )) {
                        ForEach(FontSizeOption.allCases) { opt in
                            Text(opt.title(in: lang)).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(l10n.lineSpacingShort)
                            .font(.subheadline)
                        Spacer()
                        let currentOpt = LineSpacingOption.closest(to: viewModel.config.sliceSpacing)
                        Text("\(currentOpt.title(in: lang)) (\(currentOpt.ptText))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Picker(l10n.lineSpacingShort, selection: Binding(
                        get: { LineSpacingOption.closest(to: viewModel.config.sliceSpacing) },
                        set: { opt in
                            PlatformHaptics.selection()
                            viewModel.config.sliceSpacing = opt.rawValue
                            viewModel.saveCurrentBookPreference()
                        }
                    )) {
                        ForEach(LineSpacingOption.allCases) { opt in
                            Text(opt.title(in: lang)).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(maxWidthLabel)
                            .font(.subheadline)
                        Spacer()
                        let currentOpt = ReadingWidthOption.closest(to: viewModel.config.reflowMaxWidth)
                        Text(currentOpt.description(in: lang))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Picker(maxWidthLabel, selection: Binding(
                        get: { ReadingWidthOption.closest(to: viewModel.config.reflowMaxWidth) },
                        set: { opt in
                            PlatformHaptics.selection()
                            viewModel.config.reflowMaxWidth = opt.rawValue
                            viewModel.saveCurrentBookPreference()
                        }
                    )) {
                        ForEach(ReadingWidthOption.allCases) { opt in
                            Text(opt.title(in: lang)).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider()
                    .padding(.vertical, 2)

                // 3. Foolproof Page Preprocessing & Scan Clarity (智能画质预处理)
                Toggle(enablePreprocessLabel, isOn: Binding(
                    get: { viewModel.config.enablePageEnhancement },
                    set: {
                        viewModel.config.enablePageEnhancement = $0
                        if !$0 {
                            viewModel.config.applyEnhancePreset(.raw)
                        } else {
                            viewModel.config.applyEnhancePreset(.standard)
                        }
                        viewModel.updatePreprocessSettings()
                    }
                ))
                .font(.subheadline)

                if viewModel.config.enablePageEnhancement {
                    HStack {
                        Text(enhancePresetLabel)
                            .font(.subheadline)
                        Spacer()
                        Picker(enhancePresetLabel, selection: Binding(
                            get: { viewModel.config.currentEnhancePreset },
                            set: { newPreset in
                                viewModel.config.applyEnhancePreset(newPreset)
                                viewModel.updatePreprocessSettings()
                            }
                        )) {
                            ForEach(ImageEnhancePreset.allCases) { preset in
                                Text(preset.title(in: lang)).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Picker(inkPresetLabel, selection: Binding(
                        get: { viewModel.config.inkLevel },
                        set: {
                            viewModel.setInkLevel($0)
                            viewModel.updatePreprocessSettings()
                        }
                    )) {
                        ForEach(InkLevel.allCases) { level in
                            Text(l10n.inkLevelTitle(level)).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 仅对图片文档开放手动切边纠偏
                if viewModel.config.isImageDocument {
                    Button(action: {
                        viewModel.showSettingsPanel = false
                        viewModel.isShowingManualCropView = true
                    }) {
                        HStack {
                            Label("当前图片手动切边与纠偏...", systemImage: "crop")
                                .font(.subheadline)
                            Spacer()
                            if viewModel.manualPageQuads[viewModel.currentPageIndex] != nil {
                                Text("已自定义")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .padding(.vertical, 2)

                // 4. Apple System Translation & Bilingual Reading (双语对照)
                Toggle("开启双语对照翻译", isOn: Binding(
                    get: { viewModel.translationMode != .original },
                    set: { isEnabled in
                        if isEnabled {
                            viewModel.translationMode = .bilingual
                        } else {
                            viewModel.translationMode = .original
                        }
                    }
                ))
                .font(.subheadline)

                if viewModel.translationMode != .original {
                    HStack {
                        Text(l10n.targetLanguageLabel)
                            .font(.subheadline)
                        Spacer()
                        Picker(l10n.targetLanguageLabel, selection: $viewModel.targetLanguage) {
                            ForEach(TranslationTargetLanguage.allCases) { target in
                                Text(target.displayName).tag(target)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Picker("对照模式", selection: $viewModel.translationMode) {
                        Text("双语对照").tag(TranslationDisplayMode.bilingual)
                        Text("仅显示译文").tag(TranslationDisplayMode.translated)
                    }
                    .pickerStyle(.segmented)
                }

                Divider()
                    .padding(.vertical, 2)

                // 5. iCloud Multi-Device Progress Sync (跨端进度同步)
                Toggle("开启跨设备阅读进度同步", isOn: $cloudSync.isSyncEnabled)
                    .font(.subheadline)

                HStack {
                    Text("同步状态")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(cloudSync.syncStatusMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Button(action: {
                        PlatformHaptics.impact(.light)
                        cloudSync.syncNow()
                        viewModel.showToast(message: "已刷新 iCloud 跨设备阅读进度")
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .padding(.vertical, 2)

                // 6. Interface Language (界面语言)
                HStack {
                    Text(l10n.interfaceLanguageTitle)
                        .font(.subheadline)
                    Spacer()
                    Picker(l10n.interfaceLanguageTitle, selection: $viewModel.appLanguage) {
                        ForEach(AppLanguage.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        #if os(macOS)
        .frame(minWidth: 300, maxWidth: 340)
        #endif
    }

    // MARK: - Localized Labels

    private var enablePreprocessLabel: String {
        switch lang {
        case .zhHans: return "智能画质优化 (去黑边/纠偏/清晰)"
        case .zhHant: return "智慧畫質最佳化 (去黑邊/糾偏/清晰)"
        case .en: return "Smart Document Enhancement"
        case .de: return "Dokumenten-Optimierung"
        case .ja: return "スマート画質最適化"
        }
    }

    private var enhancePresetLabel: String {
        switch lang {
        case .zhHans: return "优化方案"
        case .zhHant: return "最佳化方案"
        case .en: return "Enhance Profile"
        case .de: return "Optimierungsprofil"
        case .ja: return "補正モード"
        }
    }

    private var darkInvertLabel: String {
        switch lang {
        case .zhHans: return "夜间模式墨迹反白"
        case .zhHant: return "夜間模式墨跡反白"
        case .en: return "Invert Scan Ink in Dark Mode"
        case .de: return "Tinte im Dunkelmodus invertieren"
        case .ja: return "ダークモードで文字を反転"
        }
    }

    private var fontSizeLabel: String {
        switch lang {
        case .zhHans: return "字号大小"
        case .zhHant: return "字級大小"
        case .en: return "Text Size"
        case .de: return "Schriftgröße"
        case .ja: return "文字サイズ"
        }
    }

    private var maxWidthLabel: String {
        switch lang {
        case .zhHans: return "阅读宽度"
        case .zhHant: return "閱讀寬度"
        case .en: return "Reading Width"
        case .de: return "Lesebreite"
        case .ja: return "表示幅"
        }
    }

    private var inkPresetLabel: String {
        switch lang {
        case .zhHans: return "字迹浓淡"
        case .zhHant: return "字跡濃淡"
        case .en: return "Ink Darkness"
        case .de: return "Tintenstärke"
        case .ja: return "文字の濃さ"
        }
    }

    private var proTitleText: String {
        switch lang {
        case .zhHans: return "PDFview Pro 永久买断版"
        case .zhHant: return "PDFview Pro 永久買斷版"
        case .en: return "PDFview Pro Lifetime"
        case .de: return "PDFview Pro Einmalkauf"
        case .ja: return "PDFview Pro 買い切り版"
        }
    }

    private var proUnlockedSubtitleText: String {
        switch lang {
        case .zhHans: return "已解锁全书重排及全部高级功能"
        case .zhHant: return "已解鎖全書重排及全部高級功能"
        case .en: return "Unlimited pages reflow & all features unlocked"
        case .de: return "Unbegrenzter Textumfluss & alle Funktionen freigeschaltet"
        case .ja: return "全ページリフロー＆全機能解放済み"
        }
    }
}
