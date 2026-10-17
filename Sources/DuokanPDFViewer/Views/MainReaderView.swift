import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
@preconcurrency import Translation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum MobileDevicePreset: String, CaseIterable, Identifiable {
    case iPhoneSE = "iPhone SE"
    case iPhone16Pro = "iPhone"
    case iPhoneMax = "iPhone Max"
    case iPad = "iPad"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iPhoneSE: return "SE (375pt)"
        case .iPhone16Pro: return "iPhone (393pt)"
        case .iPhoneMax: return "Max (430pt)"
        case .iPad: return "iPad (744pt)"
        }
    }

    public var width: CGFloat {
        switch self {
        case .iPhoneSE: return 375.0
        case .iPhone16Pro: return 393.0
        case .iPhoneMax: return 430.0
        case .iPad: return 744.0
        }
    }

    public var height: CGFloat {
        switch self {
        case .iPhoneSE: return 667.0
        case .iPhone16Pro: return 852.0
        case .iPhoneMax: return 932.0
        case .iPad: return 960.0
        }
    }

    public var cornerRadius: CGFloat {
        switch self {
        case .iPhoneSE: return 20.0
        case .iPhone16Pro: return 44.0
        case .iPhoneMax: return 48.0
        case .iPad: return 24.0
        }
    }
}

public struct MainReaderView: View {
    @StateObject private var viewModel = PDFReaderViewModel()
    @State private var isShowingInspector: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var isShowingPageJumpSheet: Bool = false
    @State private var selectedNavSheetTab: Int = 0
    @GestureState private var pinchMagnification: CGFloat = 1.0

    @State private var isShowingPhotoPicker: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isBarsVisible: Bool = true
    @State private var isShowingQuickAppearance: Bool = false

    @AppStorage("PDFviewMobilePreviewMode") private var isMobilePreviewMode: Bool = false
    @State private var selectedMobileDevice: MobileDevicePreset = .iPhone16Pro

    private var mobileLeadingPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarLeading
        #else
        return .navigation
        #endif
    }

    private var mobileTrailingPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }

    public init() {}

    public var body: some View {
        Group {
            #if os(macOS)
            if isMobilePreviewMode {
                iOSMobilePreviewContainer
            } else {
                macOSBody
            }
            #else
            iOSBody
            #endif
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--ios") || args.contains("--mobile") || ProcessInfo.processInfo.environment["PDFVIEW_MOBILE"] == "1" {
                isMobilePreviewMode = true
            }
        }
        .sheet(isPresented: $viewModel.showUserGuide) {
            UserGuideView(
                viewModel: viewModel,
                isEmbeddedHome: false,
                onOpenFile: triggerOpenFile
            )
        }
        .sheet(isPresented: $viewModel.isShowingManualCropView) {
            ManualCropDeskewView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showProPaywall) {
            ProPaywallView(viewModel: viewModel)
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.openFile(url: url)
            }
        }
        .onOpenURL { url in
            viewModel.openFile(url: url)
        }
        .translationTask(viewModel.translationConfiguration) { session in
            let (items, cached) = viewModel.prepareTranslationRequests()
            guard !items.isEmpty else { return }
            do {
                let results = try await PDFReaderViewModel.runSessionTranslation(session: session, items: items)
                viewModel.applyTranslationResults(items: results, initialCached: cached)
            } catch {
                viewModel.handleTranslationError(error.localizedDescription)
            }
        }
    }

    // MARK: - macOS Desktop Layout

    #if os(macOS)
    @ViewBuilder
    private var macOSBody: some View {
        let l10n = viewModel.l10n
        let lang = viewModel.appLanguage

        Group {
            if !viewModel.hasDocument {
                // Directly show the illustrated multi-language User Guide on startup (no sample PDF)
                UserGuideView(
                    viewModel: viewModel,
                    isEmbeddedHome: true,
                    onOpenFile: triggerOpenFile
                )
            } else {
                NavigationSplitView {
                    // Left: Page Navigation List
                    VStack(spacing: 0) {
                        HStack {
                            Text(l10n.pageNavigation)
                                .font(.headline)
                            Spacer()
                            Text(l10n.totalPages(viewModel.totalPages))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()

                        Divider()

                        ScrollViewReader { scrollProxy in
                            List(0..<viewModel.totalPages, id: \.self, selection: Binding(
                                get: { viewModel.currentPageIndex },
                                set: { if let newIdx = $0 { viewModel.goToPage(newIdx) } }
                            )) { pageIdx in
                                HStack {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(pageIdx == viewModel.currentPageIndex ? .accentColor : .secondary)
                                    Text(l10n.pageNumber(pageIdx + 1))
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(pageIdx == viewModel.currentPageIndex ? .semibold : .regular)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .tag(pageIdx)
                                .id(pageIdx)
                            }
                            .listStyle(.sidebar)
                            .onChange(of: viewModel.currentPageIndex) { _, newIdx in
                                withAnimation {
                                    scrollProxy.scrollTo(newIdx, anchor: .center)
                                }
                            }
                            .onAppear {
                                scrollProxy.scrollTo(viewModel.currentPageIndex, anchor: .center)
                            }
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 155, ideal: 185, max: 230)
                } detail: {
                    // Center & Right: Main Workspace + Bottom Status Bar + Unified Settings Panel
                    HSplitView {
                        VStack(spacing: 0) {
                            ZStack(alignment: .bottom) {
                                mainContentArea
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                backgroundReflowFloatingBanner
                                    .padding(.bottom, 16)

                                VStack {
                                    copiedToastBanner
                                        .padding(.top, 16)
                                    Spacer()
                                }
                            }

                            Divider()

                            // macOS Ergonomic Bottom Status Bar
                            macOSBottomStatusBar(lang: lang, l10n: l10n)
                        }

                        if isShowingInspector {
                            SettingsPanelView(viewModel: viewModel)
                                .frame(minWidth: 300, maxWidth: 340)
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.hasDocument ? "PDFview — \(viewModel.documentTitle)" : "PDFview")
        .toolbar {
            if viewModel.hasDocument {
                // 1. Navigation: 返回主界面 + 打开文件
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: {
                        viewModel.closeDocument()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回主界面")
                        }
                    }
                    .help("返回主界面（快捷键 ⌘W）")
                    .keyboardShortcut("w", modifiers: [.command])

                    Button(action: triggerOpenFile) {
                        Label(l10n.openPDFOrImage, systemImage: "folder.badge.plus")
                    }
                    .help(l10n.openPDFHelp)
                    .keyboardShortcut("o", modifiers: [.command])
                }

                // 2. Principal: Reading Mode Switcher
                ToolbarItemGroup(placement: .principal) {
                    Picker(l10n.readingMode, selection: $viewModel.activeMode) {
                        ForEach(viewModel.toolbarReaderModes) { mode in
                            Label(l10n.readerModeTitle(mode), systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }

                // 3. PrimaryAction: 页面放大缩小 + 画质增强切换 + 页面设置面板开关
                ToolbarItemGroup(placement: .primaryAction) {
                    // 🔍 Zoom Out / Reset 100% / Zoom In Controls
                    HStack(spacing: 3) {
                        Button(action: zoomOut) {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .help("缩小页面（快捷键 ⌘-）")
                        .keyboardShortcut("-", modifiers: [.command])

                        Button(action: resetZoom) {
                            Text("\(currentZoomPercentage)%")
                                .font(.caption.monospacedDigit().weight(.medium))
                                .frame(minWidth: 44)
                        }
                        .buttonStyle(.plain)
                        .help("点击重置缩放比例至 100%（快捷键 ⌘0）")
                        .keyboardShortcut("0", modifiers: [.command])

                        Button(action: zoomIn) {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .help("放大页面（快捷键 ⌘+）")
                        .keyboardShortcut("=", modifiers: [.command])
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))

                    if viewModel.activeMode == .original {
                        Button(action: {
                            viewModel.config.originalViewEnhanced.toggle()
                            viewModel.saveCurrentBookPreference()
                            if viewModel.config.originalViewEnhanced {
                                viewModel.refreshEnhancedOriginalPage()
                            }
                        }) {
                            Label(
                                viewModel.config.originalViewEnhanced ? "智能增强" : "原版纯净",
                                systemImage: viewModel.config.originalViewEnhanced ? "sparkles" : "doc.text.image"
                            )
                        }
                        .help(viewModel.config.originalViewEnhanced ? "当前已开启智能画质增强（自动纠偏/切黑边/漂白），点击切换回原版" : "点击开启智能画质增强（自动纠偏/切黑边/漂白）")
                    }

                    Button(action: {
                        viewModel.showProPaywall = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.orange)
                            Text(viewModel.isProUnlocked ? "Pro 已激活" : "升级 Pro")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .help(viewModel.isProUnlocked ? "PDFview Pro 永久买断版已激活" : "升级至 PDFview Pro 永久买断版，解锁全本重排")

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingInspector.toggle()
                        }
                    }) {
                        Label(l10n.settingsTitle, systemImage: "slider.horizontal.3")
                            .labelStyle(.titleAndIcon)
                            .foregroundColor(isShowingInspector ? .accentColor : .primary)
                    }
                    .help("\(l10n.settingsTitle)（快捷键 ⌘, 开关设置面板）")
                    .keyboardShortcut(",", modifiers: [.command])

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isMobilePreviewMode = true
                        }
                    }) {
                        Label("手机端视图", systemImage: "iphone")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("切换至 iOS 手机端真机运行模式（快捷键 ⌘M，免模拟器）")
                    .keyboardShortcut("m", modifiers: [.command])
                }
            }
        }
    }

    @ViewBuilder
    private func macOSBottomStatusBar(lang: AppLanguage, l10n: L10n) -> some View {
        HStack(spacing: 12) {
            // 1. Page Navigation (< 第 X / Y 页 >)
            HStack(spacing: 4) {
                Button(action: { viewModel.prevPage() }) {
                    Image(systemName: "chevron.left")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.currentPageIndex <= 0)
                .help("上一页（快捷键 [ 或 PageUp）")

                Text("\(viewModel.currentPageIndex + 1) / \(max(1, viewModel.totalPages))")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 4)

                Button(action: { viewModel.nextPage() }) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.currentPageIndex >= viewModel.totalPages - 1)
                .help("下一页（快捷键 ] 或 PageDown）")
            }

            Divider()
                .frame(height: 14)

            // 2. Document & Layout Affinity Badge
            HStack(spacing: 5) {
                if viewModel.isNativeTextPage {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text("文字版 PDF")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.blue)
                } else if viewModel.config.documentLayoutAffinity == .verticalBook || viewModel.currentReflowResult?.resolvedProfile == .verticalBook {
                    Image(systemName: "books.vertical")
                        .font(.caption2)
                        .foregroundColor(.purple)
                    Text("竖排版式")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.purple)
                } else {
                    Image(systemName: "doc.text.image")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(viewModel.config.isImageDocument ? "图片文档" : "扫描件重排")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))

            // 3. Center Status Indicator
            Spacer(minLength: 8)

            if viewModel.isProcessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("正在智能重排与优化...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if viewModel.isEnhancingPage {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("正在画质增强...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(viewModel.documentTitle)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            // 4. Quick Apple Translation Switcher
            if viewModel.hasRecognizedText {
                translationToolbarMenu(lang: lang, l10n: l10n)
                Divider()
                    .frame(height: 14)
            }

            // 5. Rotation Menu
            Menu {
                Button(action: { viewModel.rotateCurrentPage(by: 90) }) {
                    Label("顺时针旋转 90°", systemImage: "rotate.right")
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(action: { viewModel.rotateCurrentPage(by: -90) }) {
                    Label("逆时针旋转 90°", systemImage: "rotate.left")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button(action: { viewModel.rotateCurrentPage(by: 180) }) {
                    Label("翻转 180°", systemImage: "arrow.triangle.2.circlepath")
                }

                Divider()

                Button(action: { viewModel.rotateAllPages(by: 90) }) {
                    Label("全部页面顺时针旋转 90°", systemImage: "square.2.layers.3d.top.filled")
                }

                if viewModel.currentPageRotation != 0 {
                    Divider()
                    Button(action: { viewModel.resetCurrentPageRotation() }) {
                        Label("重置当前页方向 (0°)", systemImage: "arrow.uturn.backward")
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "rotate.right")
                        .font(.caption)
                    Text(viewModel.currentPageRotation == 0 ? "旋转" : "\(viewModel.currentPageRotation)°")
                        .font(.caption2.monospacedDigit())
                }
            }
            .menuStyle(.borderlessButton)
            .help("旋转页面方向（快捷键 ⌘R 顺时针，⇧⌘R 逆时针）")

            Divider()
                .frame(height: 14)

            // 6. Copy Current Page Text
            Button(action: {
                viewModel.copyCurrentPageText()
            }) {
                Label(l10n.copyPageText, systemImage: "doc.on.doc")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.hasCopyableText)
            .help("\(l10n.copyPageTextHelp)（快捷键 ⇧⌘C）")

            // 7. Manual Crop & Deskew (仅对图片文档开放)
            if viewModel.config.isImageDocument {
                Divider()
                    .frame(height: 14)

                Button(action: {
                    viewModel.isShowingManualCropView = true
                }) {
                    Label("切边纠偏", systemImage: "crop")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("手动切边与纠偏 (可拖动四角裁剪并矫正倾斜)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var iOSMobilePreviewContainer: some View {
        VStack(spacing: 0) {
            // Mode Banner & Switcher (can be toggled anytime or hidden)
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "iphone")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                    Text("iOS 手机端真机运行模式")
                        .font(.headline)
                    Text("(免模拟器 · 原生交互)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Quick Device Size Switcher: iPhone 16 / iPhone Plus / iPad
                Picker("设备规格", selection: $selectedMobileDevice) {
                    ForEach(MobileDevicePreset.allCases) { device in
                        Text(device.title).tag(device)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 270)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isMobilePreviewMode = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "macbook")
                        Text("切换至 macOS 桌面版 (⌘M)")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("m", modifiers: [.command])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(Divider(), alignment: .bottom)

            // Centered Mobile Screen Canvas with authentic iPhone Chassis / Shadow
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                    .ignoresSafeArea()

                iOSBody
                    .frame(width: selectedMobileDevice.width, height: selectedMobileDevice.height)
                    .clipShape(RoundedRectangle(cornerRadius: selectedMobileDevice.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: selectedMobileDevice.cornerRadius, style: .continuous)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 8)
                    .padding(20)
            }
        }
    }
    #endif

    // MARK: - iOS (iPhone & iPad) Mobile-Optimized Layout (Also runnable on macOS in Mobile Mode)

    @ViewBuilder
    private var iOSBody: some View {
        let l10n = viewModel.l10n
        let lang = viewModel.appLanguage

        NavigationStack {
            Group {
                if !viewModel.hasDocument {
                    // Directly show the illustrated multi-language User Guide on launch
                    UserGuideView(
                        viewModel: viewModel,
                        isEmbeddedHome: true,
                        onOpenFile: { isShowingFileImporter = true },
                        onOpenPhotos: { isShowingPhotoPicker = true }
                    )
                } else {
                    VStack(spacing: 0) {
                        if isBarsVisible {
                            iOSTopNavigationBar(l10n: l10n)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if isBarsVisible && viewModel.activeMode == .reflow {
                            iOSReflowTopControlStrip
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Main Reading Canvas + Floating Background Reflow Pill + Pinch-to-Zoom
                        // Main Reading Canvas + Floating Background Reflow Pill + Pinch-to-Zoom + Double-tap Zoom
                        ZStack(alignment: .bottom) {
                            mainContentArea
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    // 在矢量文字重排模式下，优先自适应屏幕排版，避免画布人工放大变形
                                    guard viewModel.activeMode != .reflow || !viewModel.config.reflowLayoutMode.isVectorText else { return }
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                        if currentZoomPercentage != 100 {
                                            resetZoom()
                                            PlatformHaptics.impact(.medium)
                                        } else {
                                            zoomIn()
                                            PlatformHaptics.impact(.light)
                                        }
                                    }
                                }
                                .onTapGesture(count: 1) {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        isBarsVisible.toggle()
                                    }
                                }
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 35)
                                        .onEnded { value in
                                            // 原生纯 PDFKit 模式下由 PDFView 自身 UIPageViewController 原生整页翻页，避免手势竞争中断导致卡顿
                                            if viewModel.activeMode == .original && !viewModel.config.originalViewEnhanced && !viewModel.config.isImageDocument {
                                                return
                                            }
                                            let horizontalAmount = value.translation.width
                                            let verticalAmount = value.translation.height
                                            // 判定为明显水平滑动手势（避免与上下长文滚动冲突）
                                            guard abs(horizontalAmount) > abs(verticalAmount) * 1.3, abs(horizontalAmount) > 40 else { return }
                                            let isVerticalBook = viewModel.config.reflowLayoutMode.isVertical && viewModel.activeMode == .reflow
                                            withAnimation(.easeInOut(duration: 0.22)) {
                                                if horizontalAmount < 0 {
                                                    // 向左滑：横排看下一页；古籍竖排(右往左)看上一页
                                                    PlatformHaptics.impact(.light)
                                                    if isVerticalBook {
                                                        viewModel.prevPage()
                                                    } else {
                                                        viewModel.nextPage()
                                                    }
                                                } else {
                                                    // 向右滑：横排看上一页；古籍竖排(右往左)看下一页
                                                    PlatformHaptics.impact(.light)
                                                    if isVerticalBook {
                                                        viewModel.nextPage()
                                                    } else {
                                                        viewModel.prevPage()
                                                    }
                                                }
                                            }
                                        }
                                )
                                .simultaneousGesture(
                                    MagnificationGesture()
                                        .updating($pinchMagnification) { value, state, _ in
                                            state = value
                                        }
                                        .onEnded { value in
                                            applyPinchScale(value)
                                        }
                                )

                            backgroundReflowFloatingBanner
                                .padding(.bottom, 12)

                            VStack {
                                copiedToastBanner
                                    .padding(.top, 12)
                                Spacer()
                            }
                        }

                        if isBarsVisible {
                            Divider()
                            // Mobile Ergonomic Two-tier Bottom Status Bar & Control Center
                            iOSBottomThumbBar(lang: lang, l10n: l10n)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
            .navigationTitle(viewModel.hasDocument ? "" : "PDFview")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(viewModel.hasDocument ? .hidden : .visible, for: .navigationBar)
            #endif
            .toolbar {
                if !viewModel.hasDocument {
                    // Home Screen: Single entry in body hero card, clean Settings entry in top bar
                    ToolbarItem(placement: mobileTrailingPlacement) {
                        Button(action: {
                            PlatformHaptics.selection()
                            isShowingInspector = true
                        }) {
                            Image(systemName: "gearshape")
                                .font(.body)
                        }
                        .accessibilityLabel(l10n.settingsTitle)
                    }
                }
            }
            .photosPicker(
                isPresented: $isShowingPhotoPicker,
                selection: $selectedPhotoItem,
                matching: .images
            )
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        viewModel.openImageData(data, title: "Photo.jpg")
                    }
                    selectedPhotoItem = nil
                }
            }
            .sheet(isPresented: $isShowingInspector) {
                NavigationStack {
                    SettingsPanelView(viewModel: viewModel)
                        .navigationTitle(l10n.settingsTitle)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("OK") {
                                    isShowingInspector = false
                                }
                            }
                        }
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $isShowingQuickAppearance) {
                quickAppearanceSheet
            }
            .sheet(isPresented: $isShowingPageJumpSheet) {
                NavigationStack {
                    VStack(spacing: 10) {
                        if !viewModel.outlineItems.isEmpty {
                            Picker("导航模式", selection: $selectedNavSheetTab) {
                                Text("目录大纲 (\(viewModel.outlineItems.count))").tag(0)
                                Text("页码跳转").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }

                        if selectedNavSheetTab == 0 && !viewModel.outlineItems.isEmpty {
                            // 1. 结构化目录大纲（PDF Outline / Bookmarks）
                            ScrollViewReader { proxy in
                                List(viewModel.outlineItems) { item in
                                    Button(action: {
                                        PlatformHaptics.selection()
                                        viewModel.goToPage(item.pageIndex)
                                        isShowingPageJumpSheet = false
                                    }) {
                                        HStack(spacing: 8) {
                                            if item.depth > 0 {
                                                Spacer().frame(width: CGFloat(item.depth * 14))
                                            }
                                            Image(systemName: item.depth == 0 ? "book.closed" : "text.alignleft")
                                                .font(.system(size: 13))
                                                .foregroundColor(item.pageIndex == viewModel.currentPageIndex ? .accentColor : .secondary)
                                            Text(item.title)
                                                .font(.system(size: 14, weight: item.depth == 0 ? .semibold : .regular))
                                                .foregroundColor(item.pageIndex == viewModel.currentPageIndex ? .accentColor : .primary)
                                                .lineLimit(2)
                                            Spacer()
                                            Text("\(item.pageIndex + 1)")
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    .id(item.id)
                                }
                                .listStyle(.plain)
                                .onAppear {
                                    if let currentItem = viewModel.outlineItems.last(where: { $0.pageIndex <= viewModel.currentPageIndex }) {
                                        proxy.scrollTo(currentItem.id, anchor: .center)
                                    }
                                }
                            }
                        } else {
                            // 2. 页码精准滑块与进度选择列表
                            VStack(spacing: 12) {
                                HStack {
                                    Text("\(l10n.pageNumber(viewModel.currentPageIndex + 1)) / \(l10n.totalPages(viewModel.totalPages))")
                                        .font(.headline)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.top, 4)

                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.currentPageIndex) },
                                        set: {
                                            let target = Int(round($0))
                                            if target != viewModel.currentPageIndex {
                                                PlatformHaptics.selection()
                                                viewModel.goToPage(target)
                                            }
                                        }
                                    ),
                                    in: 0...Double(max(0, viewModel.totalPages - 1)),
                                    step: 1
                                )
                                .padding(.horizontal)

                                Divider()

                                ScrollViewReader { proxy in
                                    List(0..<viewModel.totalPages, id: \.self) { idx in
                                        Button(action: {
                                            PlatformHaptics.selection()
                                            viewModel.goToPage(idx)
                                            isShowingPageJumpSheet = false
                                        }) {
                                            HStack {
                                                Text(l10n.pageNumber(idx + 1))
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                if idx == viewModel.currentPageIndex {
                                                    Image(systemName: "checkmark")
                                                        .foregroundColor(.accentColor)
                                                }
                                            }
                                        }
                                        .id(idx)
                                    }
                                    .listStyle(.plain)
                                    .onAppear {
                                        proxy.scrollTo(viewModel.currentPageIndex, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle(viewModel.outlineItems.isEmpty ? l10n.pageNavigation : "目录与导航")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("OK") {
                                isShowingPageJumpSheet = false
                            }
                        }
                    }
                    .onAppear {
                        if viewModel.outlineItems.isEmpty {
                            selectedNavSheetTab = 1
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - iOS Mobile Top Navigation Bar (完全自主控制像素布局，彻底消除系统导航栏在 iPhone SE 上的折叠溢出)

    @ViewBuilder
    private func iOSTopNavigationBar(l10n: L10n) -> some View {
        HStack(spacing: 0) {
            // Left Group: Back Button + Reading Mode Pattern Switcher (原版 📄 | 重排 ≣)
            HStack(spacing: 8) {
                Button(action: {
                    PlatformHaptics.impact(.medium)
                    viewModel.closeDocument()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .accessibilityLabel(l10n.backButtonTitle)

                mobileReaderModePatternPicker(l10n: l10n)
            }

            Spacer(minLength: 8)

            // Right Group: Direct Action Buttons (👑 Pro | ✂️ 切边纠偏(仅图片) | 📋 复制文本 | ⚙️ 设置面板)
            HStack(spacing: 8) {
                // 0. Pro Status / Upgrade Button
                Button(action: {
                    PlatformHaptics.selection()
                    viewModel.showProPaywall = true
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11))
                        if !viewModel.isProUnlocked {
                            Text("PRO")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                        }
                    }
                    .foregroundColor(viewModel.isProUnlocked ? .orange : .white)
                    .padding(.horizontal, viewModel.isProUnlocked ? 6 : 8)
                    .frame(height: 32)
                    .background(
                        viewModel.isProUnlocked
                            ? AnyShapeStyle(Color.orange.opacity(0.15))
                            : AnyShapeStyle(LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .clipShape(Capsule())
                }
                .accessibilityLabel(viewModel.isProUnlocked ? "PDFview Pro" : "升级至 Pro")

                // 1. 手动切边与倾斜纠偏 (仅对图片文档开放，PDF 文档不展示以保证极速流畅)
                if viewModel.config.isImageDocument {
                    Button(action: {
                        PlatformHaptics.impact(.medium)
                        viewModel.isShowingManualCropView = true
                    }) {
                        Image(systemName: "crop")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.secondary.opacity(0.12)))
                    }
                    .accessibilityLabel("切边纠偏")
                }

                // 2. 直观点击复制当前页文本 (带触感与已复制 Toast 反馈)
                Button(action: {
                    PlatformHaptics.notificationSuccess()
                    viewModel.copyCurrentPageText()
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .disabled(!viewModel.hasCopyableText)
                .accessibilityLabel(l10n.copyPageText)

                // 3. 顺时针旋转 90° (一键直观旋转，无需翻找设置)
                Button(action: {
                    PlatformHaptics.impact(.medium)
                    viewModel.rotateCurrentPage(by: 90)
                }) {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 14))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .accessibilityLabel("旋转 90°")

                // 4. 设置面板 (包含字体排版、画质增强、云同步等)
                Button(action: {
                    PlatformHaptics.selection()
                    isShowingInspector = true
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .accessibilityLabel(l10n.settingsTitle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - iOS Mobile Top Mode Pattern Picker (图案按钮，大幅节省手机端工具栏空间)

    @ViewBuilder
    private func mobileReaderModePatternPicker(l10n: L10n) -> some View {
        HStack(spacing: 2) {
            ForEach(viewModel.toolbarReaderModes) { mode in
                Button(action: {
                    if viewModel.activeMode != mode {
                        PlatformHaptics.selection()
                        withAnimation(.easeInOut(duration: 0.16)) {
                            viewModel.activeMode = mode
                        }
                    }
                }) {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 13, weight: viewModel.activeMode == mode ? .semibold : .regular))
                        .foregroundColor(viewModel.activeMode == mode ? .accentColor : .secondary)
                        .frame(width: 32, height: 28)
                        .background(
                            Group {
                                if viewModel.activeMode == mode {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        #if os(iOS)
                                        .fill(Color(uiColor: .systemBackground))
                                        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                                        #else
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                                        #endif
                                } else {
                                    Color.clear
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.readerModeTitle(mode))
                .help(l10n.readerModeTitle(mode))
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    // MARK: - iOS Mobile Top Reflow Direct Control Strip (直观点击，无下拉菜单或弹出窗口)

    @ViewBuilder
    private var iOSReflowTopControlStrip: some View {
        HStack(spacing: 12) {
            // 渲染方式直观分段切换 (图形文字 vs 矢量文字，直接点击，无下拉菜单)
            HStack(spacing: 6) {
                Text("渲染")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Picker("渲染方式", selection: Binding(
                    get: { viewModel.config.reflowLayoutMode.isVectorText ? 1 : 0 },
                    set: { newIdx in
                        PlatformHaptics.selection()
                        let isVector = (newIdx == 1)
                        let isVert = viewModel.config.reflowLayoutMode.isVertical
                        viewModel.setReflowLayoutMode(.mode(isVertical: isVert, isVector: isVector))
                    }
                )) {
                    Text("图形文字").tag(0)
                    Text("矢量文字").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 170)
            }

            Spacer()

            // 竖排专用复选框 (独立 Checkbox，1 次点击直观切换，不用罗列选项)
            Button(action: {
                PlatformHaptics.selection()
                let currentVert = viewModel.config.reflowLayoutMode.isVertical
                let isVector = viewModel.config.reflowLayoutMode.isVectorText
                viewModel.setReflowLayoutMode(.mode(isVertical: !currentVert, isVector: isVector))
            }) {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.config.reflowLayoutMode.isVertical ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(viewModel.config.reflowLayoutMode.isVertical ? .accentColor : .secondary)
                    Text("竖排")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换竖排版式")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - iOS Mobile Bottom Display Status Bar & Progress Center (凡是属于显示状态的移到下方)

    @ViewBuilder
    private func iOSBottomThumbBar(lang: AppLanguage, l10n: L10n) -> some View {
        HStack(spacing: 6) {
            // 1. Current Display Status Badge (当前阅读版式与模式显示状态)
            iOSLayoutBadge(l10n: l10n)

            // 2. Background Processing / Translation Status Indicator (后台任务状态显示)
            if viewModel.isProcessing {
                HStack(spacing: 3) {
                    ProgressView().controlSize(.mini)
                    Text("重排中...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } else if viewModel.isTranslating {
                HStack(spacing: 3) {
                    ProgressView().controlSize(.mini)
                    Text("翻译中...")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
            }

            Spacer(minLength: 4)

            // 3. Page Navigation Scrubber & Status Indicator (阅读进度与页码显示状态)
            HStack(spacing: 3) {
                Button(action: {
                    PlatformHaptics.impact(.light)
                    viewModel.prevPage()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .disabled(viewModel.currentPageIndex <= 0)

                if viewModel.totalPages > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.currentPageIndex) },
                            set: {
                                let target = Int(round($0))
                                if target != viewModel.currentPageIndex {
                                    PlatformHaptics.selection()
                                    viewModel.goToPage(target)
                                }
                            }
                        ),
                        in: 0...Double(max(0, viewModel.totalPages - 1)),
                        step: 1
                    )
                    .frame(minWidth: 60, maxWidth: 120)
                }

                // Direct Page Jump Badge (e.g. "12 / 85")
                Button(action: {
                    PlatformHaptics.selection()
                    isShowingPageJumpSheet = true
                }) {
                    HStack(spacing: 2) {
                        Text("\(viewModel.currentPageIndex + 1)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        Text("/\(max(1, viewModel.totalPages))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.14)))
                }
                .buttonStyle(.plain)

                Button(action: {
                    PlatformHaptics.impact(.light)
                    viewModel.nextPage()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .disabled(viewModel.currentPageIndex >= viewModel.totalPages - 1)
            }

            // 4. Zoom Scale Display Badge (缩放状态显示，轻触复位 100%)
            Button(action: {
                if currentZoomPercentage != 100 {
                    PlatformHaptics.impact(.medium)
                    resetZoom()
                }
            }) {
                Text("\(currentZoomPercentage)%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(currentZoomPercentage == 100 ? .secondary : .accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("当前缩放比例")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func iOSLayoutBadge(l10n: L10n) -> some View {
        HStack(spacing: 3) {
            Image(systemName: currentLayoutIcon)
                .font(.system(size: 10))
            Text(currentLayoutTitle)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(currentLayoutColor.opacity(0.14)))
        .foregroundColor(currentLayoutColor)
    }

    private var currentLayoutTitle: String {
        switch viewModel.activeMode {
        case .reflow:
            return viewModel.config.reflowLayoutMode.shortLabel
        case .original:
            return viewModel.config.originalViewEnhanced ? "增强原版" : "原始版面"
        case .ocrText:
            return "OCR纯文本"
        case .sideBySide:
            return "双屏对照"
        case .debug:
            return "调试切片"
        }
    }

    private var currentLayoutIcon: String {
        switch viewModel.activeMode {
        case .reflow:
            return viewModel.config.reflowLayoutMode.iconName
        case .original:
            return "doc.text.image"
        case .ocrText:
            return "text.viewfinder"
        case .sideBySide:
            return "rectangle.split.2x1"
        case .debug:
            return "square.dashed.circle"
        }
    }

    private var currentLayoutColor: Color {
        switch viewModel.activeMode {
        case .reflow:
            switch viewModel.config.reflowLayoutMode {
            case .horizontalGraphic: return .teal
            case .horizontalVector: return .blue
            case .verticalGraphic: return .purple
            case .verticalVector: return .indigo
            }
        case .original:
            return .secondary
        case .ocrText:
            return .orange
        case .sideBySide:
            return .accentColor
        case .debug:
            return .red
        }
    }

    private var currentLayoutDescription: String {
        switch viewModel.activeMode {
        case .reflow:
            return viewModel.config.reflowLayoutMode.rawValue
        case .original:
            return "PDF 原始版面"
        case .ocrText:
            return "OCR 离线文本提取"
        case .sideBySide:
            return "原版与重排双屏对照"
        case .debug:
            return "算法切片与视觉块分析"
        }
    }

    @ViewBuilder
    private var quickAppearanceSheet: some View {
        let l10n = viewModel.l10n
        let lang = viewModel.appLanguage
        NavigationStack {
            VStack(spacing: 20) {
                // 1. Reading Themes (4 circular color buttons)
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.paperTheme)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 14) {
                        ForEach([ReadingTheme.white, .sepia, .eyeCare, .dark]) { theme in
                            Button(action: {
                                PlatformHaptics.selection()
                                viewModel.config.readingTheme = theme
                                viewModel.saveCurrentBookPreference()
                            }) {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(nsColor: theme.backgroundColor))
                                            .frame(width: 44, height: 44)
                                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                                        if viewModel.config.readingTheme == theme {
                                            Circle()
                                                .stroke(Color.accentColor, lineWidth: 3)
                                                .frame(width: 48, height: 48)
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundColor(Color(nsColor: theme.textColor))
                                        } else {
                                            Circle()
                                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                                .frame(width: 44, height: 44)
                                        }
                                    }
                                    Text(l10n.themeTitle(theme))
                                        .font(.caption2)
                                        .foregroundColor(viewModel.config.readingTheme == theme ? .accentColor : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                Divider()

                // 2. Font Size Adjustment (Reflow: 5 presets, Original: Zoom)
                if viewModel.activeMode == .reflow || viewModel.activeMode == .ocrText {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(l10n.fontSizeLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            let currentOpt = FontSizeOption.closest(to: viewModel.config.textScale)
                            Text("\(currentOpt.title(in: lang)) (\(currentOpt.percentageText))")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }

                        Picker(l10n.fontSizeLabel, selection: Binding(
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

                    // 3. Line Spacing Presets (Reflow mode: 5 presets)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(l10n.lineSpacingShort)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            let currentOpt = LineSpacingOption.closest(to: viewModel.config.sliceSpacing)
                            Text("\(currentOpt.title(in: lang)) (\(currentOpt.ptText))")
                                .font(.caption.monospacedDigit())
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
                } else {
                    // Original Mode: Page Zoom
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(l10n.fontSizeLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(currentZoomPercentage)%")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button(action: {
                                PlatformHaptics.impact(.light)
                                zoomOut()
                            }) {
                                Image(systemName: "textformat.size.smaller")
                                    .font(.body)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Color.secondary.opacity(0.12)))
                            }

                            Slider(value: $viewModel.zoomScale, in: 0.5...2.5, step: 0.05)

                            Button(action: {
                                PlatformHaptics.impact(.light)
                                zoomIn()
                            }) {
                                Image(systemName: "textformat.size.larger")
                                    .font(.body)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Color.secondary.opacity(0.12)))
                            }
                        }
                    }
                }

                // 4. More settings link
                Button(action: {
                    isShowingQuickAppearance = false
                    isShowingInspector = true
                }) {
                    HStack(spacing: 4) {
                        Text(l10n.moreSettings)
                            .font(.footnote)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundColor(.accentColor)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .navigationTitle(l10n.quickAppearanceTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        isShowingQuickAppearance = false
                    }
                }
            }
        }
        .presentationDetents([.height(350), .medium])
    }

    @ViewBuilder
    private func translationBottomMenu(lang: AppLanguage, l10n: L10n) -> some View {
        Menu {
            Button(action: { viewModel.toggleQuickCNENTranslation() }) {
                Label(l10n.quickSwitchCNEN, systemImage: "arrow.left.arrow.right")
            }
            Divider()
            Section(l10n.translateButton) {
                ForEach(TranslationDisplayMode.allCases) { mode in
                    Button(action: { viewModel.translationMode = mode }) {
                        HStack {
                            Text(mode.title(in: lang))
                            if viewModel.translationMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Section(l10n.targetLanguageLabel) {
                ForEach(TranslationTargetLanguage.allCases) { target in
                    Button(action: {
                        viewModel.targetLanguage = target
                        if viewModel.translationMode == .original {
                            viewModel.translationMode = .bilingual
                        }
                    }) {
                        HStack {
                            Text(target.displayName)
                            if viewModel.targetLanguage == target {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "character.bubble.fill")
                Text(viewModel.translationMode == .original
                     ? l10n.translateButton
                     : viewModel.targetLanguage.shortName)
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    viewModel.translationMode != .original
                    ? Color.accentColor.opacity(0.18)
                    : Color.secondary.opacity(0.12)
                )
            )
            .foregroundColor(viewModel.translationMode != .original ? .accentColor : .primary)
        }
    }

    // MARK: - Shared Subviews & Helpers

    @ViewBuilder
    private var copiedToastBanner: some View {
        if viewModel.showCopiedToast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
                Text(viewModel.copiedToastMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Floating pill shown while viewing Original layout so the user knows background reflow is running or ready
    @ViewBuilder
    private var backgroundReflowFloatingBanner: some View {
        let l10n = viewModel.l10n
        if viewModel.activeMode == .original {
            if viewModel.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(l10n.backgroundReflowing)
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if viewModel.isCurrentPageReflowReady {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.activeMode = .reflow
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.accentColor)
                        Text(l10n.backgroundReflowReady)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    @ViewBuilder
    private func translationToolbarMenu(lang: AppLanguage, l10n: L10n) -> some View {
        HStack(spacing: 2) {
            Button(action: {
                viewModel.toggleQuickCNENTranslation()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "character.bubble.fill")
                        .foregroundColor(viewModel.translationMode != .original ? .accentColor : .primary)
                    Text(viewModel.translationMode == .original
                         ? l10n.translateButton
                         : "\(viewModel.translationMode.title(in: lang)) (\(viewModel.targetLanguage.shortName))")
                        .font(.caption.weight(viewModel.translationMode != .original ? .semibold : .regular))
                }
            }
            .help(l10n.quickSwitchCNEN)

            Menu {
                Section(l10n.translateButton) {
                    ForEach(TranslationDisplayMode.allCases) { mode in
                        Button(action: {
                            viewModel.translationMode = mode
                        }) {
                            HStack {
                                Text(mode.title(in: lang))
                                if viewModel.translationMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Section(l10n.targetLanguageLabel) {
                    ForEach(TranslationTargetLanguage.allCases) { target in
                        Button(action: {
                            viewModel.targetLanguage = target
                            if viewModel.translationMode == .original {
                                viewModel.translationMode = .bilingual
                            }
                        }) {
                            HStack {
                                Text(target.displayName)
                                if viewModel.targetLanguage == target {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .frame(width: 16)
        }
    }

    private var currentZoomPercentage: Int {
        if viewModel.activeMode == .original {
            return Int(round(viewModel.zoomScale * 100))
        } else {
            return Int(round(viewModel.config.textScale * 100))
        }
    }

    private func zoomOut() {
        if viewModel.activeMode == .original {
            viewModel.zoomScale = max(0.5, viewModel.zoomScale - 0.1)
        } else {
            viewModel.config.textScale = max(0.5, viewModel.config.textScale - 0.1)
            viewModel.saveCurrentBookPreference()
        }
    }

    private func zoomIn() {
        if viewModel.activeMode == .original {
            viewModel.zoomScale = min(3.0, viewModel.zoomScale + 0.1)
        } else {
            viewModel.config.textScale = min(3.0, viewModel.config.textScale + 0.1)
            viewModel.saveCurrentBookPreference()
        }
    }

    private func resetZoom() {
        if viewModel.activeMode == .original {
            viewModel.zoomScale = 1.0
        } else {
            viewModel.config.textScale = 1.0
            viewModel.saveCurrentBookPreference()
        }
    }

    private func applyPinchScale(_ delta: CGFloat) {
        let clampedDelta = max(0.6, min(1.6, delta))
        if viewModel.activeMode == .original {
            viewModel.zoomScale = max(0.5, min(3.0, viewModel.zoomScale * clampedDelta))
        } else {
            viewModel.config.textScale = max(0.5, min(3.0, viewModel.config.textScale * clampedDelta))
            viewModel.saveCurrentBookPreference()
        }
    }

    @ViewBuilder
    private var mainContentArea: some View {
        let l10n = viewModel.l10n
        Group {
            switch viewModel.activeMode {
            case .reflow:
                ReflowPageView(viewModel: viewModel)
            case .ocrText:
                OCRTextView(viewModel: viewModel)
            case .original:
                if viewModel.config.originalViewEnhanced {
                    EnhancedOriginalPageView(viewModel: viewModel)
                } else {
                    OriginalPDFView(viewModel: viewModel)
                }
            case .sideBySide:
                #if os(macOS)
                HSplitView {
                    VStack(spacing: 0) {
                        Text(l10n.readerModeTitle(.original))
                            .font(.caption)
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(Color(nsColor: .windowBackgroundColor))
                        Divider()
                        if viewModel.config.originalViewEnhanced {
                            EnhancedOriginalPageView(viewModel: viewModel)
                        } else {
                            OriginalPDFView(viewModel: viewModel)
                        }
                    }
                    .frame(minWidth: 320)

                    VStack(spacing: 0) {
                        Text(l10n.readerModeTitle(.reflow))
                            .font(.caption)
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(Color(nsColor: .windowBackgroundColor))
                        Divider()
                        ReflowPageView(viewModel: viewModel)
                    }
                    .frame(minWidth: 320)
                }
                #else
                ReflowPageView(viewModel: viewModel)
                #endif
            case .debug:
                SliceDebugView(viewModel: viewModel)
            }
        }
        .contextMenu {
            Button(action: { viewModel.rotateCurrentPage(by: 90) }) {
                Label("顺时针旋转 90° (⌘R)", systemImage: "rotate.right")
            }
            Button(action: { viewModel.rotateCurrentPage(by: -90) }) {
                Label("逆时针旋转 90° (⇧⌘R)", systemImage: "rotate.left")
            }
            Button(action: { viewModel.rotateCurrentPage(by: 180) }) {
                Label("翻转 180°", systemImage: "arrow.triangle.2.circlepath")
            }
            Divider()
            Button(action: {
                viewModel.copyCurrentPageText()
            }) {
                Label(l10n.copyPageText, systemImage: "doc.on.doc")
            }
        }
    }

    private func triggerOpenFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf, .image, .png, .jpeg, .heic, .tiff, .bmp, .gif]
        panel.message = viewModel.l10n.openPDFHelp

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.openFile(url: url)
        }
        #else
        isShowingFileImporter = true
        #endif
    }
}
