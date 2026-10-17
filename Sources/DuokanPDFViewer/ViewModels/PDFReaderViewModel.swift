import Foundation
import SwiftUI
import PDFKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
@preconcurrency import Translation
import NaturalLanguage

extension TranslationSession: @unchecked @retroactive Sendable {}
extension TranslationSession.Request: @unchecked @retroactive Sendable {}

public enum ReaderMode: String, CaseIterable, Identifiable {
    case original = "原始版面"
    case reflow = "智能重排"
    case ocrText = "OCR纯文本"
    case sideBySide = "双屏对照"
    case debug = "算法切片调试"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .original: return "doc.text.image"
        case .reflow: return "text.alignleft"
        case .ocrText: return "text.viewfinder"
        case .sideBySide: return "rectangle.split.2x1"
        case .debug: return "square.dashed.circle"
        }
    }
}

/// Represents a single chapter or bookmark heading in a PDF document outline
public struct DocumentOutlineItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let pageIndex: Int
    public let depth: Int

    public init(id: String, title: String, pageIndex: Int, depth: Int) {
        self.id = id
        self.title = title
        self.pageIndex = pageIndex
        self.depth = depth
    }
}

@MainActor
public final class PDFReaderViewModel: ObservableObject {
    @Published public var document: PDFDocument?
    @Published public var documentTitle: String = "未打开文件"
    @Published public var currentPageIndex: Int = 0
    @Published public var totalPages: Int = 0
    @Published public var outlineItems: [DocumentOutlineItem] = []

    /// Starts in `.original` mode immediately when a file is opened while reflow runs in the background
    @Published public var activeMode: ReaderMode = .original {
        didSet {
            if activeMode != oldValue {
                if activeMode == .original && config.originalViewEnhanced {
                    refreshEnhancedOriginalPage()
                } else if currentReflowResult == nil || currentReflowResult?.pageIndex != currentPageIndex {
                    refreshCurrentPage()
                }
            }
        }
    }
    @Published public var config: ReflowConfig = ReflowConfig()
    @Published public var isProcessing: Bool = false
    @Published public var currentReflowResult: PageReflowResult?

    // MARK: - Enhanced Original View State
    @Published public var enhancedPageImage: NSImage? = nil
    @Published public var isEnhancingPage: Bool = false
    @Published public var currentPreprocessResult: PagePreprocessResult? = nil

    // MARK: - Manual Page Rotation State
    @Published public var pageRotationVersion: Int = 0
    public var pageRotations: [Int: Int] = [:]

    // MARK: - Manual Page Crop & Deskew State
    @Published public var isShowingManualCropView: Bool = false
    public var manualPageQuads: [Int: ManualCropQuad] = [:]

    @Published public var allPageSlices: [Int: [PageSlice]] = [:]
    @Published public var isContinuousScroll: Bool = false
    @Published public var zoomScale: CGFloat = 1.0
    @Published public var showSettingsPanel: Bool = false
    @Published public var showUserGuide: Bool = false
    @Published public var showProPaywall: Bool = false
    @Published public var recentDocuments: [RecentDocumentItem] = []

    // MARK: - Pro Store & Paywall Logic
    public static let freeReflowPageLimit = 20

    public var isProUnlocked: Bool {
        ProStoreService.shared.isProUnlocked
    }

    /// Determines whether the given page index is locked in Reflow / OCR mode for free users
    public func isReflowPageLocked(pageIndex: Int) -> Bool {
        if isProUnlocked { return false }
        if config.isImageDocument { return false }
        return pageIndex >= Self.freeReflowPageLimit
    }

    // MARK: - Clipboard & Toast Feedback State
    @Published public var showCopiedToast: Bool = false
    @Published public var copiedToastMessage: String = ""
    private var toastDismissTask: Task<Void, Never>? = nil

    // MARK: - Multi-Language UI State
    @Published public var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "PDFview_AppLanguage")
        }
    }

    public var l10n: L10n {
        L10n(appLanguage)
    }

    // MARK: - Apple Built-in Translation State
    @Published public var translationMode: TranslationDisplayMode = .original {
        didSet {
            if translationMode != .original {
                requestPageTranslation()
            }
        }
    }

    @Published public var targetLanguage: TranslationTargetLanguage = .zhHans {
        didSet {
            UserDefaults.standard.set(targetLanguage.rawValue, forKey: "PDFview_TargetLanguage")
            if translationMode != .original {
                requestPageTranslation()
            }
        }
    }

    @Published public var translatedParagraphs: [UUID: String] = [:]
    @Published public var isTranslating: Bool = false
    @Published public var translationError: String? = nil
    @Published public var translationConfiguration: TranslationSession.Configuration? = nil

    private var translationCache: [String: String] = [:]
    private let engine = ReflowEngine.shared

    // MARK: - Context-Aware Document / Page Inspection

    /// True when a PDF or Image document is currently loaded
    public var hasDocument: Bool {
        document != nil && totalPages > 0
    }

    /// True when the current page is a native vector text PDF or recognized text PDF (no OCR or scan color adjustments needed)
    public var isNativeTextPage: Bool {
        currentReflowResult?.textSourceType == .nativeVectorText || currentReflowResult?.textSourceType == .ocrRecognizedText
    }

    /// True when background reflow has completed for the current page
    public var isCurrentPageReflowReady: Bool {
        !isProcessing && currentReflowResult != nil
    }

    /// Toolbar modes for reading screen (精简为原版与重排，避免与重排中的矢量文字功能重叠)
    public var toolbarReaderModes: [ReaderMode] {
        #if os(iOS)
        return [.original, .reflow]
        #else
        return [.original, .reflow, .sideBySide]
        #endif
    }

    /// True if the current page has extracted or OCR-recognized text available for translation
    public var hasRecognizedText: Bool {
        guard let paragraphs = currentReflowResult?.paragraphs else { return false }
        return paragraphs.contains { para in
            guard let t = para.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !t.isEmpty
        }
    }

    public var currentResolvedProfile: LayoutProfile {
        currentReflowResult?.resolvedProfile ?? config.layoutProfile
    }

    public var activeProfileBadgeText: String {
        if config.layoutProfile == .auto {
            if let res = currentReflowResult {
                return res.resolvedProfile.rawValue
            }
            return LayoutProfile.auto.rawValue
        } else {
            return config.layoutProfile.rawValue
        }
    }

    public init() {
        if let savedLang = UserDefaults.standard.string(forKey: "PDFview_AppLanguage"),
           let parsed = AppLanguage(rawValue: savedLang) {
            self.appLanguage = parsed
        } else {
            self.appLanguage = AppLanguage.detectSystemDefault()
        }

        if let savedTarget = UserDefaults.standard.string(forKey: "PDFview_TargetLanguage"),
           let parsedTarget = TranslationTargetLanguage(rawValue: savedTarget) {
            self.targetLanguage = parsedTarget
        } else {
            self.targetLanguage = .zhHans
        }
        self.recentDocuments = RecentDocumentsStore.shared.loadRecents()

        // Listen for iCloud external progress updates across devices
        NotificationCenter.default.addObserver(
            forName: iCloudSyncService.progressDidChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.recentDocuments = RecentDocumentsStore.shared.loadRecents()
                if self.hasDocument, let cloudPref = BookPreferenceStore.shared.load(for: self.documentTitle) {
                    if cloudPref.lastPageIndex != self.currentPageIndex && cloudPref.lastPageIndex < self.totalPages {
                        self.showToast(message: "已同步云端进度：第 \(cloudPref.lastPageIndex + 1) 页")
                    }
                }
            }
        }
    }

    private var activeSecurityScopedURL: URL? = nil

    /// Opens either a PDF file or an Image file (.png, .jpg, .jpeg, .heic, .tiff, .webp, .bmp, .gif)
    public func openFile(url: URL) {
        // Dismiss user guide modal if it was open
        self.showUserGuide = false

        // Release any previous security-scoped resource before acquiring new one
        if let previous = activeSecurityScopedURL {
            previous.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
        }
        if url.startAccessingSecurityScopedResource() {
            activeSecurityScopedURL = url
        }

        // Check if ubiquitous iCloud item needs downloading first
        if FileManager.default.isUbiquitousItem(at: url) {
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                self.showToast(message: "正在从 iCloud 下载《\(url.lastPathComponent)》...")
                return
            }
        }

        // Coordinate reading with NSFileCoordinator for iCloud ubiquitous & sandbox file safety
        var fileData: Data? = nil
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { safeURL in
            fileData = try? Data(contentsOf: safeURL)
        }
        if fileData == nil {
            fileData = try? Data(contentsOf: url)
        }

        let isImage = PlatformImageDocumentLoader.isImageFile(url: url)
        let effectiveTitle = url.lastPathComponent

        // 1. Try Image Document loading
        if isImage {
            if let data = fileData, let imageDoc = PlatformImageDocumentLoader.createPDFDocument(fromImageData: data) {
                self.config.isImageDocument = true
                self.config.originalViewEnhanced = true
                setDocument(imageDoc, title: effectiveTitle)
                RecentDocumentsStore.shared.addOrUpdate(url: url, title: effectiveTitle, pageIndex: self.currentPageIndex, totalPages: imageDoc.pageCount)
                self.recentDocuments = RecentDocumentsStore.shared.loadRecents()
                return
            }
            if let imageDoc = PlatformImageDocumentLoader.createPDFDocument(fromImageURL: url) {
                self.config.isImageDocument = true
                self.config.originalViewEnhanced = true
                setDocument(imageDoc, title: effectiveTitle)
                RecentDocumentsStore.shared.addOrUpdate(url: url, title: effectiveTitle, pageIndex: self.currentPageIndex, totalPages: imageDoc.pageCount)
                self.recentDocuments = RecentDocumentsStore.shared.loadRecents()
                return
            }
        }

        // 2. Try PDF loading from coordinated Data
        if let data = fileData, let pdfDoc = PDFDocument(data: data), pdfDoc.pageCount > 0 {
            self.config.isImageDocument = false
            setDocument(pdfDoc, title: effectiveTitle)
            RecentDocumentsStore.shared.addOrUpdate(url: url, title: effectiveTitle, pageIndex: self.currentPageIndex, totalPages: pdfDoc.pageCount)
            self.recentDocuments = RecentDocumentsStore.shared.loadRecents()
            return
        }

        // 3. Try PDF loading directly from URL
        if let pdfDoc = PDFDocument(url: url), pdfDoc.pageCount > 0 {
            self.config.isImageDocument = false
            setDocument(pdfDoc, title: effectiveTitle)
            RecentDocumentsStore.shared.addOrUpdate(url: url, title: effectiveTitle, pageIndex: self.currentPageIndex, totalPages: pdfDoc.pageCount)
            self.recentDocuments = RecentDocumentsStore.shared.loadRecents()
            return
        }

        // 4. Fallback: try decoding as an image even if extension wasn't standard
        if let data = fileData, let imageDoc = PlatformImageDocumentLoader.createPDFDocument(fromImageData: data) {
            self.config.isImageDocument = true
            setDocument(imageDoc, title: effectiveTitle)
            RecentDocumentsStore.shared.addOrUpdate(url: url, title: effectiveTitle, pageIndex: self.currentPageIndex, totalPages: imageDoc.pageCount)
            self.recentDocuments = RecentDocumentsStore.shared.loadRecents()
            return
        }

        // If all attempts failed, give clear feedback to the user
        self.showToast(message: "无法打开文件《\(effectiveTitle)》")
    }

    /// Opens an image directly from raw Data (e.g. from iOS PhotosPicker)
    public func openImageData(_ data: Data, title: String = "Photo.jpg") {
        self.showUserGuide = false
        guard let imageDoc = PlatformImageDocumentLoader.createPDFDocument(fromImageData: data) else {
            self.showToast(message: "无法解析图片数据")
            return
        }
        self.config.isImageDocument = true
        self.config.originalViewEnhanced = true
        setDocument(imageDoc, title: title)

        // Save imported photo to the persistent documents directory and record in recents
        Task {
            let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let targetURL = baseDir.appendingPathComponent(title)
            try? data.write(to: targetURL)

            RecentDocumentsStore.shared.addOrUpdate(
                url: targetURL,
                title: title,
                pageIndex: 0,
                totalPages: imageDoc.pageCount
            )
            await MainActor.run {
                self.recentDocuments = RecentDocumentsStore.shared.loadRecents()
            }
        }
    }

    /// Closes the current document and returns to the User Guide home screen
    public func closeDocument() {
        if let active = activeSecurityScopedURL {
            active.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
        }
        self.document = nil
        self.documentTitle = l10n.untitledDocument
        self.totalPages = 0
        self.currentPageIndex = 0
        self.currentReflowResult = nil
        self.enhancedPageImage = nil
        self.currentPreprocessResult = nil
        self.allPageSlices.removeAll()
        self.translatedParagraphs.removeAll()
        self.pageRotations.removeAll()
        self.pageRotationVersion = 0
        self.manualPageQuads.removeAll()
        self.config.manualPageQuad = nil
        self.isShowingManualCropView = false
        self.config.documentLayoutAffinity = nil
        self.outlineItems.removeAll()
        self.isProcessing = false
        self.isEnhancingPage = false
    }

    public func setDocument(_ doc: PDFDocument, title: String) {
        self.document = doc
        self.documentTitle = title
        self.totalPages = doc.pageCount
        self.currentPageIndex = 0
        self.outlineItems = Self.extractOutline(from: doc)
        self.currentReflowResult = nil
        self.config.documentLayoutAffinity = nil
        self.translatedParagraphs.removeAll()
        self.translationError = nil
        self.pageRotations.removeAll()
        self.pageRotationVersion = 0

        if doc.documentAttributes?[PDFDocumentAttribute(rawValue: "IsImageDocument")] != nil {
            self.config.isImageDocument = true
        }

        // Always open immediately in Original mode so the user never waits on a spinner,
        // while reflow runs asynchronously in the background.
        self.activeMode = .original

        // Restore book preferences if previously opened
        if let pref = BookPreferenceStore.shared.load(for: title) {
            self.config.layoutProfile = pref.layoutProfile
            self.config.textScale = pref.textScale
            self.config.sliceSpacing = pref.sliceSpacing
            if let theme = ReadingTheme(rawValue: pref.readingTheme) {
                self.config.readingTheme = theme
            }
            if let ink = pref.inkLevel {
                self.config.setInkLevel(ink)
            }
            if let enh = pref.enablePageEnhancement {
                self.config.enablePageEnhancement = enh
            }
            if let mode = pref.scanEnhanceMode {
                self.config.scanEnhanceMode = mode
            }
            if let persp = pref.autoPerspectiveCorrection {
                self.config.autoPerspectiveCorrection = persp
            }
            if let deskew = pref.autoDeskew {
                self.config.autoDeskew = deskew
            }
            if let crop = pref.autoCropBlackBorders {
                self.config.autoCropBlackBorders = crop
            }
            if let staples = pref.autoRemoveStaplesAndPunchHoles {
                self.config.autoRemoveStaplesAndPunchHoles = staples
            }
            if let bleach = pref.backgroundBleachLevel {
                self.config.backgroundBleachLevel = bleach
            }
            if let sharp = pref.pageSharpening {
                self.config.pageSharpening = sharp
            }
            if let origEnh = pref.originalViewEnhanced {
                self.config.originalViewEnhanced = origEnh
            }
            if let trm = pref.textRenderMode {
                self.config.textRenderMode = trm
            }
            if let customRots = pref.pageRotations {
                self.pageRotations = customRots
                for (pageIdx, rot) in customRots {
                    if pageIdx < doc.pageCount, let p = doc.page(at: pageIdx) {
                        p.rotation = rot
                    }
                }
            } else if let docRot = pref.documentRotation, docRot != 0 {
                for i in 0..<doc.pageCount {
                    if let p = doc.page(at: i) {
                        p.rotation = ((p.rotation + docRot) % 360 + 360) % 360
                    }
                }
            }
            if let customQuads = pref.manualPageQuads {
                self.manualPageQuads = customQuads
            }
            self.currentPageIndex = min(pref.lastPageIndex, max(0, doc.pageCount - 1))
        }

        self.config.manualPageQuad = self.manualPageQuads[self.currentPageIndex]
        self.allPageSlices.removeAll()
        self.engine.clearCache()
        refreshCurrentPage()
    }

    public func setReflowLayoutMode(_ mode: ReflowLayoutMode) {
        self.config.reflowLayoutMode = mode
        saveCurrentBookPreference()
        reprocess()
    }

    public func setLayoutProfile(_ profile: LayoutProfile) {
        self.config.layoutProfile = profile
        saveCurrentBookPreference()
        reprocess()
    }

    public func setInkLevel(_ level: InkLevel) {
        self.config.setInkLevel(level)
        saveCurrentBookPreference()
        reprocess()
    }

    public func updatePreprocessSettings() {
        saveCurrentBookPreference()
        PagePreprocessEngine.shared.clearCache()
        if activeMode == .original && config.originalViewEnhanced {
            refreshEnhancedOriginalPage()
        }
        reprocess()
    }

    // MARK: - Manual Page Rotation Functions

    /// Rotates the current page by specified degrees (e.g. +90 for CW, -90 for CCW)
    public func rotateCurrentPage(by degrees: Int) {
        guard let doc = document, currentPageIndex < doc.pageCount,
              let page = doc.page(at: currentPageIndex) else { return }

        let newRotation = ((page.rotation + degrees) % 360 + 360) % 360
        page.rotation = newRotation
        pageRotations[currentPageIndex] = newRotation
        pageRotationVersion += 1

        PagePreprocessEngine.shared.clearCache()
        engine.clearCache()
        allPageSlices.removeAll()
        currentReflowResult = nil

        saveCurrentBookPreference()

        if activeMode == .original && config.originalViewEnhanced {
            refreshEnhancedOriginalPage()
        }
        reprocess()

        let directionStr = degrees > 0 ? "顺时针" : "逆时针"
        showToast(message: "当前页已\(directionStr)旋转 \(abs(degrees))° (当前: \(newRotation)°)")
    }

    /// Rotates all pages in the document by specified degrees
    public func rotateAllPages(by degrees: Int) {
        guard let doc = document, doc.pageCount > 0 else { return }

        for i in 0..<doc.pageCount {
            if let p = doc.page(at: i) {
                let newRot = ((p.rotation + degrees) % 360 + 360) % 360
                p.rotation = newRot
                pageRotations[i] = newRot
            }
        }
        pageRotationVersion += 1

        PagePreprocessEngine.shared.clearCache()
        engine.clearCache()
        allPageSlices.removeAll()
        currentReflowResult = nil

        saveCurrentBookPreference()

        if activeMode == .original && config.originalViewEnhanced {
            refreshEnhancedOriginalPage()
        }
        reprocess()

        let directionStr = degrees > 0 ? "顺时针" : "逆时针"
        showToast(message: "全部 \(doc.pageCount) 页已\(directionStr)旋转 \(abs(degrees))°")
    }

    /// Resets rotation of the current page to 0°
    public func resetCurrentPageRotation() {
        guard let doc = document, currentPageIndex < doc.pageCount,
              let page = doc.page(at: currentPageIndex) else { return }

        page.rotation = 0
        pageRotations[currentPageIndex] = 0
        pageRotationVersion += 1

        PagePreprocessEngine.shared.clearCache()
        engine.clearCache()
        allPageSlices.removeAll()
        currentReflowResult = nil

        saveCurrentBookPreference()

        if activeMode == .original && config.originalViewEnhanced {
            refreshEnhancedOriginalPage()
        }
        reprocess()

        showToast(message: "已重置当前页方向 (0°)")
    }

    /// Returns current page's rotation angle (0, 90, 180, 270)
    public var currentPageRotation: Int {
        guard let doc = document, currentPageIndex < doc.pageCount,
              let page = doc.page(at: currentPageIndex) else { return 0 }
        return ((page.rotation % 360) + 360) % 360
    }

    public func saveCurrentBookPreference() {
        guard documentTitle != "未打开文件" && documentTitle != l10n.untitledDocument else { return }
        let pref = BookPreference(
            layoutProfile: config.layoutProfile,
            textScale: config.textScale,
            sliceSpacing: config.sliceSpacing,
            readingTheme: config.readingTheme.rawValue,
            lastPageIndex: currentPageIndex,
            inkLevel: config.inkLevel,
            enablePageEnhancement: config.enablePageEnhancement,
            scanEnhanceMode: config.scanEnhanceMode,
            autoPerspectiveCorrection: config.autoPerspectiveCorrection,
            autoDeskew: config.autoDeskew,
            autoCropBlackBorders: config.autoCropBlackBorders,
            autoRemoveStaplesAndPunchHoles: config.autoRemoveStaplesAndPunchHoles,
            backgroundBleachLevel: config.backgroundBleachLevel,
            pageSharpening: config.pageSharpening,
            originalViewEnhanced: config.originalViewEnhanced,
            textRenderMode: config.textRenderMode,
            pageRotations: pageRotations.isEmpty ? nil : pageRotations,
            manualPageQuads: manualPageQuads.isEmpty ? nil : manualPageQuads
        )
        BookPreferenceStore.shared.save(for: documentTitle, preference: pref)
        RecentDocumentsStore.shared.updateProgress(title: documentTitle, pageIndex: currentPageIndex, totalPages: totalPages)
        self.recentDocuments = RecentDocumentsStore.shared.loadRecents()
    }

    /// Opens a recent document from history
    public func openRecentDocument(_ item: RecentDocumentItem) {
        if let url = RecentDocumentsStore.shared.resolveURL(for: item) {
            openFile(url: url)
        } else {
            self.translationError = l10n.fileNotFoundOrMoved
        }
    }

    /// Removes a document from recent history
    public func removeRecentDocument(_ item: RecentDocumentItem) {
        RecentDocumentsStore.shared.remove(urlString: item.urlString)
        self.recentDocuments = RecentDocumentsStore.shared.loadRecents()
    }

    /// Clears all recent documents history
    public func clearRecentDocuments() {
        RecentDocumentsStore.shared.clearAll()
        self.recentDocuments = []
    }

    // MARK: - Current Page Text Copy & Toast

    /// Extracts the readable plain text of the current page
    public func currentPageText() -> String {
        // 1. Prioritize reflowed paragraphs (proper reading order, horizontally aligned)
        if let result = currentReflowResult, !result.paragraphs.isEmpty {
            let texts = result.paragraphs.compactMap { para -> String? in
                if translationMode == .translated,
                   let trans = translatedParagraphs[para.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !trans.isEmpty {
                    return trans
                } else if translationMode == .bilingual,
                          let trans = translatedParagraphs[para.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !trans.isEmpty,
                          let orig = para.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !orig.isEmpty {
                    return "\(orig)\n\(trans)"
                } else if let orig = para.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !orig.isEmpty {
                    return orig
                }
                return nil
            }
            if !texts.isEmpty {
                return texts.joined(separator: "\n\n")
            }
        }

        // 2. Fallback to native PDFKit page string
        if let page = document?.page(at: currentPageIndex),
           let raw = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }

        return ""
    }

    /// Whether current page has readable text to copy
    public var hasCopyableText: Bool {
        !currentPageText().isEmpty
    }

    /// Copies current page's text to the system pasteboard and triggers a toast notification
    @discardableResult
    public func copyCurrentPageText() -> Bool {
        let text = currentPageText()
        guard !text.isEmpty else {
            showToast(message: l10n.noCopyableText)
            return false
        }
        PlatformClipboard.copy(text)
        showToast(message: l10n.copiedPageTextSuccess)
        return true
    }

    /// Displays an animated toast message that auto-dismisses after 2 seconds
    public func showToast(message: String) {
        toastDismissTask?.cancel()
        copiedToastMessage = message
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showCopiedToast = true
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.showCopiedToast = false
            }
        }
    }

    public func nextPage() {
        guard currentPageIndex < totalPages - 1 else { return }
        currentPageIndex += 1
        config.manualPageQuad = manualPageQuads[currentPageIndex]
        currentReflowResult = nil
        saveCurrentBookPreference()
        refreshCurrentPage()
    }

    public func prevPage() {
        guard currentPageIndex > 0 else { return }
        currentPageIndex -= 1
        config.manualPageQuad = manualPageQuads[currentPageIndex]
        currentReflowResult = nil
        saveCurrentBookPreference()
        refreshCurrentPage()
    }

    public func goToPage(_ index: Int) {
        guard index >= 0, index < totalPages else { return }
        currentPageIndex = index
        config.manualPageQuad = manualPageQuads[currentPageIndex]
        currentReflowResult = nil
        saveCurrentBookPreference()
        refreshCurrentPage()
    }

    // MARK: - Manual Crop & Perspective Deskew Methods

    /// Renders raw, unenhanced page image for interactive cropping / quadrilateral adjustment
    public func currentRawPageCGImage() -> CGImage? {
        guard let doc = document, currentPageIndex < doc.pageCount,
              let page = doc.page(at: currentPageIndex) else { return nil }
        return ReflowEngine.renderPageToCGImage(page: page, dpi: max(180.0, config.renderDPI))
    }

    /// Applies manual quadrilateral de-skewing and cropping for a page (restricted to image documents)
    public func applyManualCrop(for pageIndex: Int, quad: ManualCropQuad) {
        guard config.isImageDocument else { return }
        manualPageQuads[pageIndex] = quad
        if currentPageIndex == pageIndex {
            config.manualPageQuad = quad
            PagePreprocessEngine.shared.clearCache()
            engine.clearCache()
            allPageSlices.removeValue(forKey: pageIndex)
            saveCurrentBookPreference()
            if activeMode == .original && config.originalViewEnhanced {
                refreshEnhancedOriginalPage()
            }
            reprocess()
            showToast(message: "已应用手动切边与纠偏并重新排版")
        }
    }

    /// Resets manual crop for a page back to full document page
    public func resetManualCrop(for pageIndex: Int) {
        manualPageQuads.removeValue(forKey: pageIndex)
        if currentPageIndex == pageIndex {
            config.manualPageQuad = nil
            PagePreprocessEngine.shared.clearCache()
            engine.clearCache()
            allPageSlices.removeValue(forKey: pageIndex)
            saveCurrentBookPreference()
            if activeMode == .original && config.originalViewEnhanced {
                refreshEnhancedOriginalPage()
            }
            reprocess()
            showToast(message: "已重置切边与纠偏")
        }
    }

    public func reprocess() {
        engine.clearCache()
        allPageSlices.removeAll()
        currentReflowResult = nil
        refreshCurrentPage()
    }

    public func refreshCurrentPage() {
        if activeMode == .original && config.originalViewEnhanced {
            refreshEnhancedOriginalPage()
        }

        guard let doc = document, currentPageIndex < doc.pageCount,
              let page = doc.page(at: currentPageIndex) else {
            currentReflowResult = nil
            return
        }

        isProcessing = true
        let pageIdx = currentPageIndex
        let currentConfig = config

        Task {
            let result = await engine.processPage(
                page: page,
                pageIndex: pageIdx,
                config: currentConfig
            )

            if self.currentPageIndex == pageIdx {
                self.currentReflowResult = result
                if let slices = result?.allSlices {
                    self.allPageSlices[pageIdx] = slices
                }
                self.isProcessing = false

                // If translation is active, automatically translate the newly loaded page
                if self.translationMode != .original {
                    self.requestPageTranslation()
                }
            }

            // Pre-cache next page
            if pageIdx + 1 < doc.pageCount, let nextPage = doc.page(at: pageIdx + 1) {
                Task { [engine, currentConfig] in
                    _ = await engine.processPage(
                        page: nextPage,
                        pageIndex: pageIdx + 1,
                        config: currentConfig
                    )
                }
            }
        }
    }

    /// Re-renders and enhances the current page for the Enhanced Original View
    public func refreshEnhancedOriginalPage() {
        guard let doc = document, currentPageIndex < doc.pageCount,
              let page = doc.page(at: currentPageIndex) else {
            enhancedPageImage = nil
            currentPreprocessResult = nil
            return
        }

        isEnhancingPage = true
        let pageIdx = currentPageIndex
        let docTitle = documentTitle
        let currentConfig = config

        Task {
            let res = await PagePreprocessEngine.shared.preprocessPage(
                page: page,
                pageIndex: pageIdx,
                docIdentifier: docTitle,
                config: currentConfig
            )
            guard self.currentPageIndex == pageIdx else { return }
            if let result = res {
                self.currentPreprocessResult = result
                self.enhancedPageImage = NSImage(cgImage: result.processedImage, size: NSSize(width: result.processedImage.width, height: result.processedImage.height))
            }
            self.isEnhancingPage = false
        }
    }

    // MARK: - Smart One-Click CN ↔ EN Switch & Apple Translation Execution

    /// Smart one-click toggle between Original and Translated/Bilingual reading (auto-selects CN vs EN based on source text)
    public func toggleQuickCNENTranslation() {
        if translationMode != .original {
            translationMode = .original
            return
        }

        // Inspect current page text to pick the opposite target language automatically
        let sample = currentReflowResult?.paragraphs
            .compactMap { $0.recognizedText }
            .joined(separator: " ") ?? ""
        let cjkCount = sample.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        let totalCount = max(1, sample.filter { !$0.isWhitespace }.count)
        let isPredominantlyChinese = Double(cjkCount) / Double(totalCount) > 0.15

        if isPredominantlyChinese {
            targetLanguage = .en
        } else {
            targetLanguage = (appLanguage == .zhHant) ? .zhHant : .zhHans
        }
        translationMode = .bilingual
    }

    /// Triggers or refreshes the Apple TranslationSession configuration for the current page
    public func requestPageTranslation() {
        guard let paragraphs = currentReflowResult?.paragraphs, !paragraphs.isEmpty else { return }

        // Check if all paragraphs on this page are already cached for the target language
        var allCached = true
        var cachedMap: [UUID: String] = [:]
        for p in paragraphs {
            guard let text = p.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            let key = "\(targetLanguage.rawValue)::\(text)"
            if let cached = translationCache[key] {
                cachedMap[p.id] = cached
            } else {
                allCached = false
            }
        }

        if allCached && !cachedMap.isEmpty {
            self.translatedParagraphs = cachedMap
            self.isTranslating = false
            self.translationError = nil
            return
        }

        // Detect dominant source language using NaturalLanguage so Apple TranslationSession knows exact pair
        let combinedSample = paragraphs.compactMap { $0.recognizedText }.prefix(12).joined(separator: "\n")
        let sourceLocale = Self.detectSourceLocaleLanguage(for: combinedSample, avoiding: targetLanguage)

        let desiredConfig = TranslationSession.Configuration(
            source: sourceLocale,
            target: targetLanguage.localeLanguage
        )

        if var existing = translationConfiguration,
           existing.source == desiredConfig.source && existing.target == desiredConfig.target {
            existing.invalidate()
            translationConfiguration = existing
        } else {
            translationConfiguration = desiredConfig
        }
    }

    /// Prepares Sendable translation items on MainActor before calling TranslationSession
    public func prepareTranslationRequests() -> (items: [(id: String, text: String)], cached: [UUID: String]) {
        guard translationMode != .original,
              let paragraphs = currentReflowResult?.paragraphs else {
            return ([], [:])
        }

        isTranslating = true
        translationError = nil

        var items: [(id: String, text: String)] = []
        var updatedMap: [UUID: String] = translatedParagraphs

        for p in paragraphs {
            guard let text = p.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }
            let key = "\(targetLanguage.rawValue)::\(text)"
            if let cached = translationCache[key] {
                updatedMap[p.id] = cached
            } else {
                items.append((id: p.id.uuidString, text: text))
            }
        }

        if items.isEmpty {
            translatedParagraphs = updatedMap
            isTranslating = false
        }

        return (items, updatedMap)
    }

    /// Executes Apple TranslationSession batch translation outside MainActor region isolation
    public nonisolated static func runSessionTranslation(
        session: TranslationSession,
        items: [(id: String, text: String)]
    ) async throws -> [(clientId: String?, sourceText: String, targetText: String)] {
        let requests = items.map {
            TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id)
        }
        let responses = try await session.translations(from: requests)
        return responses.map {
            (clientId: $0.clientIdentifier, sourceText: $0.sourceText, targetText: $0.targetText)
        }
    }

    /// Applies completed translation responses on MainActor
    public func applyTranslationResults(
        items: [(clientId: String?, sourceText: String, targetText: String)],
        initialCached: [UUID: String]
    ) {
        var updatedMap = initialCached
        for item in items {
            if let idStr = item.clientId,
               let uuid = UUID(uuidString: idStr) {
                updatedMap[uuid] = item.targetText
                let key = "\(targetLanguage.rawValue)::\(item.sourceText)"
                translationCache[key] = item.targetText
            }
        }
        self.translatedParagraphs = updatedMap
        self.isTranslating = false
    }

    public func handleTranslationError(_ message: String) {
        self.isTranslating = false
        self.translationError = message
    }

    private static func detectSourceLocaleLanguage(
        for text: String,
        avoiding target: TranslationTargetLanguage
    ) -> Locale.Language? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        if let dominant = recognizer.dominantLanguage {
            let rawCode = dominant.rawValue
            // Avoid source == target which causes TranslationSession error
            if rawCode.hasPrefix("zh") && (target == .zhHans || target == .zhHant) {
                return Locale.Language(identifier: "en")
            }
            if rawCode == target.rawValue {
                return target == .en ? Locale.Language(identifier: "zh-Hans") : Locale.Language(identifier: "en")
            }
            return Locale.Language(identifier: rawCode)
        }
        return nil
    }

    /// Recursively extracts the hierarchical outline (Table of Contents) from a PDFDocument
    public static func extractOutline(from doc: PDFDocument) -> [DocumentOutlineItem] {
        guard let root = doc.outlineRoot else { return [] }
        var items: [DocumentOutlineItem] = []

        func traverse(node: PDFOutline, depth: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                let rawTitle = child.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                var pageIdx: Int? = nil
                if let dest = child.destination, let page = dest.page {
                    pageIdx = doc.index(for: page)
                } else if let action = child.action as? PDFActionGoTo, let page = action.destination.page {
                    pageIdx = doc.index(for: page)
                }
                if !rawTitle.isEmpty, let idx = pageIdx, idx >= 0, idx < doc.pageCount {
                    items.append(DocumentOutlineItem(
                        id: "\(depth)_\(i)_\(idx)_\(rawTitle)",
                        title: rawTitle,
                        pageIndex: idx,
                        depth: depth
                    ))
                }
                if child.numberOfChildren > 0 {
                    traverse(node: child, depth: depth + 1)
                }
            }
        }

        traverse(node: root, depth: 0)
        return items
    }
}
