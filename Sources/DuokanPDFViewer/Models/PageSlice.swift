import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum ReadingTheme: String, CaseIterable, Identifiable, Sendable {
    case eyeCare = "护眼暖阳"
    case sepia = "羊皮纸"
    case white = "纯白无暇"
    case gray = "柔和冷灰"
    case dark = "夜间深色"

    public var id: String { rawValue }

    public var backgroundColor: NSColor {
        switch self {
        case .eyeCare:
            return NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.88, alpha: 1.0)
        case .sepia:
            return NSColor(calibratedRed: 0.94, green: 0.90, blue: 0.82, alpha: 1.0)
        case .white:
            return NSColor.white
        case .gray:
            return NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.93, alpha: 1.0)
        case .dark:
            return NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)
        }
    }

    public var textColor: NSColor {
        switch self {
        case .dark:
            return NSColor(calibratedWhite: 0.9, alpha: 1.0)
        default:
            return NSColor(calibratedWhite: 0.15, alpha: 1.0)
        }
    }

    public var cardBackground: NSColor {
        switch self {
        case .dark:
            return NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.18, alpha: 1.0)
        default:
            return NSColor.white.withAlphaComponent(0.85)
        }
    }
}

public enum BinarizationMode: String, CaseIterable, Identifiable, Sendable {
    case original = "原图保留"
    case contrastEnhanced = "对比度增强"
    case adaptive = "自适应二值化"
    case otsu = "大津法(Otsu)"

    public var id: String { rawValue }
}

public enum LayoutProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "智能识别"
    case book = "单栏图书 (含注脚)"
    case academic = "双栏学术文献"
    case officialDoc = "公文通报/报告"
    case magazine = "报刊杂志画册"
    case verticalBook = "竖排图书 (转横排)"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .auto: return "sparkles"
        case .book: return "book"
        case .academic: return "newspaper"
        case .officialDoc: return "building.columns"
        case .magazine: return "photo.on.rectangle"
        case .verticalBook: return "book.pages"
        }
    }

    public var shortDescription: String {
        switch self {
        case .auto: return "根据页面特征自动匹配最优版式"
        case .book: return "单栏正文、首行缩进、注脚识别与分割线还原"
        case .academic: return "双栏智能切割、跨栏保护、紧凑排版"
        case .officialDoc: return "大标题居中、称谓冒号导语、落款对齐、大行距"
        case .magazine: return "图文同行绕排、插图图表高优先保全"
        case .verticalBook: return "古籍与港台竖排书籍，自右向左按列解构并自适应转现代横排流式"
        }
    }
}

public enum InkLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case normal = "自然原版"
    case enhanced = "清晰增强"
    case dark = "浓墨深黑"
    case deep = "极深重墨"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .normal: return "drop"
        case .enhanced: return "drop.fill"
        case .dark: return "paintbrush.pointed"
        case .deep: return "paintbrush.pointed.fill"
        }
    }

    public var contrast: Double {
        switch self {
        case .normal: return 1.05
        case .enhanced: return 1.35
        case .dark: return 1.65
        case .deep: return 2.10
        }
    }

    public var darkening: Double {
        switch self {
        case .normal: return 0.05
        case .enhanced: return 0.35
        case .dark: return 0.65
        case .deep: return 0.90
        }
    }

    public var strokeThickening: Int {
        switch self {
        case .normal: return 0
        case .enhanced: return 0
        case .dark: return 1
        case .deep: return 1
        }
    }

    public var sharpening: Double {
        switch self {
        case .normal: return 0.2
        case .enhanced: return 0.6
        case .dark: return 0.8
        case .deep: return 1.1
        }
    }
}

public enum ScanEnhanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case cleanBW = "黑白清爽 (纯正扫描件)"
    case magicColor = "魔术彩色 (高清去底灰)"
    case enhancedGray = "清晰灰度 (专业灰度稿)"
    case documentFilter = "苹果文稿滤镜 (系统原生)"
    case gentle = "原版温和微调"
    case off = "关闭优化"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .cleanBW: return "黑白扫描件"
        case .magicColor: return "魔术彩色"
        case .enhancedGray: return "清晰灰度"
        case .documentFilter: return "苹果滤镜"
        case .gentle: return "温和微调"
        case .off: return "关闭"
        }
    }

    public var iconName: String {
        switch self {
        case .cleanBW: return "doc.text.fill"
        case .magicColor: return "sparkles"
        case .enhancedGray: return "circle.lefthalf.filled"
        case .documentFilter: return "wand.and.stars"
        case .gentle: return "slider.horizontal.3"
        case .off: return "nosign"
        }
    }
}

public enum BleachLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case off = "关闭"
    case gentle = "温和漂白"
    case strong = "深度漂白"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .off: return "关闭"
        case .gentle: return "温和"
        case .strong: return "深度"
        }
    }
}

public enum ImageEnhancePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard = "standard"
    case deepBleach = "deepBleach"
    case natural = "natural"
    case raw = "raw"

    public var id: String { rawValue }

    public func title(in lang: AppLanguage) -> String {
        switch self {
        case .standard:
            switch lang {
            case .zhHans: return "标准清晰 (推荐)"
            case .zhHant: return "標準清晰 (推薦)"
            case .en: return "Standard Clarity"
            case .de: return "Standard"
            case .ja: return "標準補正（推奨）"
            }
        case .deepBleach:
            switch lang {
            case .zhHans: return "强力去底灰"
            case .zhHant: return "強力去底灰"
            case .en: return "Deep Bleach"
            case .de: return "Starke Bleichung"
            case .ja: return "強力漂白"
            }
        case .natural:
            switch lang {
            case .zhHans: return "轻度保真 (原色)"
            case .zhHant: return "輕度保真 (原色)"
            case .en: return "Gentle / Photo"
            case .de: return "Sanfte Farben"
            case .ja: return "原色保持"
            }
        case .raw:
            switch lang {
            case .zhHans: return "原图保留 (无滤镜)"
            case .zhHant: return "原圖保留 (無濾鏡)"
            case .en: return "Original (No Filter)"
            case .de: return "Original"
            case .ja: return "元画像"
            }
        }
    }

    public func subtitle(in lang: AppLanguage) -> String {
        switch self {
        case .standard:
            switch lang {
            case .zhHans: return "自动切除黑边、页面纠偏、智能去底灰与文字锐化"
            case .zhHant: return "自動切除黑邊、頁面糾偏、智慧去底灰與文字銳化"
            case .en: return "Auto crop borders, deskew, whiten background and sharpen"
            case .de: return "Ränder schneiden, ausrichten, Hintergrund aufhellen"
            case .ja: return "黒枠除去・傾き補正・背景漂白・文字強調"
            }
        case .deepBleach:
            switch lang {
            case .zhHans: return "深度消除扫描阴影与发黄底色，字迹高对比度加深"
            case .zhHant: return "深度消除掃描陰影與發黃底色，字跡高對比度加深"
            case .en: return "Remove heavy shadows and yellow tint, maximize ink contrast"
            case .de: return "Starke Schatten entfernen, hoher Kontrast"
            case .ja: return "濃い影や紙の黄ばみを強力除去、コントラスト最大化"
            }
        case .natural:
            switch lang {
            case .zhHans: return "纠偏并切除黑边，最大化保留原版插图与彩色纸张"
            case .zhHant: return "糾偏並切除黑邊，最大化保留原版插圖與彩色紙張"
            case .en: return "Deskew and crop borders while preserving colorful art"
            case .de: return "Ausrichten und Ränder entfernen, Farben beibehalten"
            case .ja: return "傾き補正と余白整理、カラーイラストを保持"
            }
        case .raw:
            switch lang {
            case .zhHans: return "不进行任何图像滤镜处理，完全按原始图像排版"
            case .zhHant: return "不進行任何圖像濾鏡處理，完全按原始圖像排版"
            case .en: return "Disable image enhancement filters completely"
            case .de: return "Keine Filter anwenden"
            case .ja: return "画像補正を適用せず、そのまま処理"
            }
        }
    }
}

public enum ReflowLayoutMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case horizontalGraphic = "图形文字横排 (默认)"
    case horizontalVector = "矢量文字横排"
    case verticalGraphic = "竖排图书 (图形切片)"
    case verticalVector = "竖排图书 (矢量文字)"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .horizontalGraphic: return "图形横排"
        case .horizontalVector: return "矢量横排"
        case .verticalGraphic: return "竖排 (图形)"
        case .verticalVector: return "竖排 (文字)"
        }
    }

    public var iconName: String {
        switch self {
        case .horizontalGraphic: return "photo.artframe"
        case .horizontalVector: return "character.textbox"
        case .verticalGraphic: return "book.pages"
        case .verticalVector: return "book.pages.fill"
        }
    }

    public var isVertical: Bool {
        self == .verticalGraphic || self == .verticalVector
    }

    public var isVectorText: Bool {
        self == .horizontalVector || self == .verticalVector
    }

    public static func mode(isVertical: Bool, isVector: Bool) -> ReflowLayoutMode {
        switch (isVertical, isVector) {
        case (false, false): return .horizontalGraphic
        case (false, true):  return .horizontalVector
        case (true, false):  return .verticalGraphic
        case (true, true):   return .verticalVector
        }
    }
}

public struct ReflowConfig: Equatable, Sendable {
    public var renderDPI: CGFloat = 200.0
    public var trimMargins: Bool = true
    public var detectColumns: Bool = true
    public var binarizationMode: BinarizationMode = .contrastEnhanced
    public var thresholdValue: Float = 0.85
    public var minColumnGapRatio: CGFloat = 0.018
    public var minLineHeight: Int = 10
    public var sliceSpacing: CGFloat = 8.0
    public var linePadding: Int = 4
    public var reflowMaxWidth: CGFloat = 720.0
    public var readingTheme: ReadingTheme = .white
    public var invertColorsInDarkTheme: Bool = true

    // Advanced Image Preprocessing & Page Optimization (扫描文稿化、透视拉伸、切边、装订钉/打孔痕迹擦除、纠偏、漂白、锐化)
    public var enablePageEnhancement: Bool = true
    public var scanEnhanceMode: ScanEnhanceMode = .cleanBW
    public var autoPerspectiveCorrection: Bool = true
    public var autoCropBlackBorders: Bool = true
    public var autoRemoveStaplesAndPunchHoles: Bool = true
    public var autoDeskew: Bool = true
    public var backgroundBleachLevel: BleachLevel = .strong
    public var pageSharpening: Double = 0.8
    public var originalViewEnhanced: Bool = false
    public var manualPageQuad: ManualCropQuad? = nil

    // Layout Profile & Human-AI Collaboration (默认横排单栏图书，竖排作为独立选项)
    public var layoutProfile: LayoutProfile = .book
    public var documentLayoutAffinity: LayoutProfile? = nil

    // Ink & Clarity: 对比度增强、字迹加深、笔画微加粗与抗锯齿
    public var inkLevel: InkLevel = .enhanced
    public var autoWhitenBackground: Bool = true
    public var textContrast: Double = 1.35          // 1.0 ... 2.5
    public var textDarkening: Double = 0.35         // 0.0 ... 1.0
    public var strokeThickening: Int = 0            // 0 = 保持原样, 1 = 笔画微加粗1px防断笔
    public var textSharpening: Double = 0.6         // 0.0 ... 1.5 边缘锐化

    // Text magnification / reflow settings (默认图形文字横排)
    public var textScale: CGFloat = 1.0
    public var paragraphSpacing: CGFloat = 14.0
    public var wordSpacing: CGFloat = 2.0
    public var enableWordReflow: Bool = true
    public var enableVisionOCR: Bool = true
    public var standardBodyLineHeight: CGFloat = 26.0
    public var enableSemanticScaling: Bool = true
    public var textRenderMode: TextReflowRenderMode = .imageSlices
    public var isImageDocument: Bool = false

    public var reflowLayoutMode: ReflowLayoutMode {
        get {
            if layoutProfile == .verticalBook {
                return textRenderMode == .vectorText ? .verticalVector : .verticalGraphic
            } else {
                return textRenderMode == .vectorText ? .horizontalVector : .horizontalGraphic
            }
        }
        set {
            switch newValue {
            case .horizontalGraphic:
                layoutProfile = .book
                textRenderMode = .imageSlices
                documentLayoutAffinity = nil
            case .horizontalVector:
                layoutProfile = .book
                textRenderMode = .vectorText
                documentLayoutAffinity = nil
            case .verticalGraphic:
                layoutProfile = .verticalBook
                textRenderMode = .imageSlices
                documentLayoutAffinity = .verticalBook
            case .verticalVector:
                layoutProfile = .verticalBook
                textRenderMode = .vectorText
                documentLayoutAffinity = .verticalBook
            }
        }
    }

    public init() {}

    public mutating func setInkLevel(_ level: InkLevel) {
        self.inkLevel = level
        self.textContrast = level.contrast
        self.textDarkening = level.darkening
        self.strokeThickening = level.strokeThickening
        self.textSharpening = level.sharpening
    }

    public mutating func applyEnhancePreset(_ preset: ImageEnhancePreset) {
        switch preset {
        case .standard:
            self.enablePageEnhancement = true
            self.scanEnhanceMode = .cleanBW
            self.backgroundBleachLevel = .strong
            self.autoPerspectiveCorrection = true
            self.autoDeskew = true
            self.autoCropBlackBorders = true
            self.autoRemoveStaplesAndPunchHoles = true
            self.pageSharpening = 0.8
        case .deepBleach:
            self.enablePageEnhancement = true
            self.scanEnhanceMode = .cleanBW
            self.backgroundBleachLevel = .strong
            self.autoPerspectiveCorrection = true
            self.autoDeskew = true
            self.autoCropBlackBorders = true
            self.autoRemoveStaplesAndPunchHoles = true
            self.pageSharpening = 1.0
            self.setInkLevel(.deep)
        case .natural:
            self.enablePageEnhancement = true
            self.scanEnhanceMode = .gentle
            self.backgroundBleachLevel = .gentle
            self.autoPerspectiveCorrection = false
            self.autoDeskew = true
            self.autoCropBlackBorders = true
            self.autoRemoveStaplesAndPunchHoles = false
            self.pageSharpening = 0.4
        case .raw:
            self.enablePageEnhancement = false
            self.scanEnhanceMode = .off
            self.backgroundBleachLevel = .off
            self.autoPerspectiveCorrection = false
            self.autoDeskew = false
            self.autoCropBlackBorders = false
            self.autoRemoveStaplesAndPunchHoles = false
            self.pageSharpening = 0.0
        }
    }

    public var currentEnhancePreset: ImageEnhancePreset {
        if !enablePageEnhancement || scanEnhanceMode == .off {
            return .raw
        }
        if scanEnhanceMode == .gentle || backgroundBleachLevel == .gentle {
            return .natural
        }
        if pageSharpening >= 0.95 || inkLevel == .deep {
            return .deepBleach
        }
        return .standard
    }
}

public struct WordSlice: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let originalRect: CGRect
    public let image: NSImage
    public let aspectRatio: CGFloat

    public init(
        id: UUID = UUID(),
        originalRect: CGRect,
        image: NSImage
    ) {
        self.id = id
        self.originalRect = originalRect
        self.image = image
        self.aspectRatio = originalRect.height > 0 ? (originalRect.width / originalRect.height) : 1.0
    }
}

public struct ParagraphBlock: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let paragraphIndex: Int
    public let columnIndex: Int
    public let hasIndent: Bool
    public let isTitle: Bool
    public let semanticLevel: SemanticLevel
    public let isFigure: Bool
    public let isTable: Bool
    public let isSideBySide: Bool
    public let figureOnRight: Bool
    public let figureSlice: PageSlice?
    public let sideFigure: PageSlice?
    public let words: [WordSlice]
    public let baseLineHeight: CGFloat
    public let recognizedText: String?

    public init(
        id: UUID = UUID(),
        paragraphIndex: Int,
        columnIndex: Int,
        hasIndent: Bool = false,
        isTitle: Bool = false,
        semanticLevel: SemanticLevel = .body,
        isFigure: Bool = false,
        isTable: Bool = false,
        isSideBySide: Bool = false,
        figureOnRight: Bool = true,
        figureSlice: PageSlice? = nil,
        sideFigure: PageSlice? = nil,
        words: [WordSlice] = [],
        baseLineHeight: CGFloat = 30.0,
        recognizedText: String? = nil
    ) {
        self.id = id
        self.paragraphIndex = paragraphIndex
        self.columnIndex = columnIndex
        self.hasIndent = hasIndent
        self.isTitle = isTitle
        self.semanticLevel = semanticLevel
        self.isFigure = isFigure
        self.isTable = isTable
        self.isSideBySide = isSideBySide
        self.figureOnRight = figureOnRight
        self.figureSlice = figureSlice
        self.sideFigure = sideFigure
        self.words = words
        self.baseLineHeight = baseLineHeight
        self.recognizedText = recognizedText
    }
}

public struct PageSlice: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let pageIndex: Int
    public let columnIndex: Int
    public let sliceIndex: Int
    public let originalRect: CGRect
    public let columnWidth: CGFloat
    public let image: NSImage
    public let isFigure: Bool
    public let isTable: Bool
    public let isSideBySide: Bool
    public let aspectRatio: CGFloat
    public let words: [WordSlice]
    public let recognizedText: String?

    public init(
        id: UUID = UUID(),
        pageIndex: Int,
        columnIndex: Int,
        sliceIndex: Int,
        originalRect: CGRect,
        columnWidth: CGFloat = 0,
        image: NSImage,
        isFigure: Bool,
        isTable: Bool = false,
        isSideBySide: Bool = false,
        words: [WordSlice] = [],
        recognizedText: String? = nil
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.columnIndex = columnIndex
        self.sliceIndex = sliceIndex
        self.originalRect = originalRect
        self.columnWidth = columnWidth > 0 ? columnWidth : originalRect.width
        self.image = image
        self.isFigure = isFigure
        self.isTable = isTable
        self.isSideBySide = isSideBySide
        self.aspectRatio = originalRect.height > 0 ? (originalRect.width / originalRect.height) : 1.0
        self.words = words
        self.recognizedText = recognizedText
    }
}

public enum PageZoneType: String, CaseIterable, Identifiable, Sendable {
    case header = "页眉区"
    case body = "正文区"
    case footnote = "注脚区"
    case footer = "页脚区"
    case figure = "插图区"
    case table = "表格区"

    public var id: String { rawValue }

    public var badgeColor: NSColor {
        switch self {
        case .header: return NSColor.systemOrange
        case .body: return NSColor.systemBlue
        case .footnote: return NSColor.systemGreen
        case .footer: return NSColor.systemPurple
        case .figure: return NSColor.systemPink
        case .table: return NSColor.systemBrown
        }
    }
}

public struct PageZone: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let type: PageZoneType
    public let rect: CGRect
    public let columnIndex: Int
    public var slices: [PageSlice]
    public var paragraphs: [ParagraphBlock]

    public init(
        id: UUID = UUID(),
        type: PageZoneType,
        rect: CGRect,
        columnIndex: Int = 0,
        slices: [PageSlice] = [],
        paragraphs: [ParagraphBlock] = []
    ) {
        self.id = id
        self.type = type
        self.rect = rect
        self.columnIndex = columnIndex
        self.slices = slices
        self.paragraphs = paragraphs
    }
}

public struct ColumnRegion: @unchecked Sendable {
    public let index: Int
    public let rect: CGRect
    public let slices: [PageSlice]

    public init(index: Int, rect: CGRect, slices: [PageSlice]) {
        self.index = index
        self.rect = rect
        self.slices = slices
    }
}

public struct PageReflowResult: @unchecked Sendable {
    public let pageIndex: Int
    public let originalImage: NSImage
    public let contentBounds: CGRect
    public let columns: [ColumnRegion]
    public let allSlices: [PageSlice]
    public let paragraphs: [ParagraphBlock]
    public let resolvedProfile: LayoutProfile
    public let zones: [PageZone]
    public let textSourceType: PDFTextSourceType
    public let isImageDocument: Bool

    public init(
        pageIndex: Int,
        originalImage: NSImage,
        contentBounds: CGRect,
        columns: [ColumnRegion],
        allSlices: [PageSlice],
        paragraphs: [ParagraphBlock] = [],
        resolvedProfile: LayoutProfile = .auto,
        zones: [PageZone] = [],
        textSourceType: PDFTextSourceType = .scannedImage,
        isImageDocument: Bool = false
    ) {
        self.pageIndex = pageIndex
        self.originalImage = originalImage
        self.contentBounds = contentBounds
        self.columns = columns
        self.allSlices = allSlices
        self.paragraphs = paragraphs
        self.resolvedProfile = resolvedProfile
        self.zones = zones
        self.textSourceType = textSourceType
        self.isImageDocument = isImageDocument
    }

    /// Determines whether ReflowPageView should directly render extracted vector text instead of bitmap word slices
    public func shouldUseVectorText(for config: ReflowConfig) -> Bool {
        switch config.textRenderMode {
        case .vectorText:
            return true
        case .imageSlices:
            return false
        case .auto:
            // 1. Vertical books (古籍/港台竖排书籍) strictly use original glyph slice reflow ("字形切片重排")!
            // Glyph slicing preserves authentic typography, calligraphy, woodblock texture, and punctuation orientation.
            if resolvedProfile == .verticalBook {
                return false
            }
            // 2. Camera photos and scanned images default to image slice reflow ("图片/字形重排")!
            if isImageDocument || config.isImageDocument || textSourceType == .scannedImage {
                return false
            }
            // 3. Structured text PDFs (native vector text or OCR recognized PDF) use crisp vector typography!
            return textSourceType == .nativeVectorText || textSourceType == .ocrRecognizedText
        }
    }
}

// MARK: - Reader Typography Presets (Discrete 4~5 Level Controls)

/// Preset fixed options for reader typography to avoid fussy continuous sliders without preview
public enum FontSizeOption: CGFloat, CaseIterable, Identifiable {
    case small = 0.85     // 85%
    case standard = 1.0   // 100%
    case large = 1.25     // 125%
    case xlarge = 1.50    // 150%
    case huge = 1.80      // 180%

    public var id: CGFloat { rawValue }

    public func title(in lang: AppLanguage) -> String {
        switch lang {
        case .zhHans:
            switch self {
            case .small: return "小"
            case .standard: return "标准"
            case .large: return "大"
            case .xlarge: return "特大"
            case .huge: return "极大"
            }
        case .zhHant:
            switch self {
            case .small: return "小"
            case .standard: return "標準"
            case .large: return "大"
            case .xlarge: return "特大"
            case .huge: return "極大"
            }
        case .en:
            switch self {
            case .small: return "S"
            case .standard: return "M"
            case .large: return "L"
            case .xlarge: return "XL"
            case .huge: return "XXL"
            }
        case .de:
            switch self {
            case .small: return "S"
            case .standard: return "M"
            case .large: return "L"
            case .xlarge: return "XL"
            case .huge: return "XXL"
            }
        case .ja:
            switch self {
            case .small: return "小"
            case .standard: return "標準"
            case .large: return "大"
            case .xlarge: return "特大"
            case .huge: return "極大"
            }
        }
    }

    public var percentageText: String {
        "\(Int(round(rawValue * 100)))%"
    }

    public static func closest(to value: CGFloat) -> FontSizeOption {
        allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .standard
    }
}

/// Preset fixed options for line spacing in pt
public enum LineSpacingOption: CGFloat, CaseIterable, Identifiable {
    case tight = 6.0      // 极紧
    case compact = 12.0   // 紧凑
    case standard = 18.0  // 标准
    case loose = 28.0     // 宽松
    case spacious = 40.0  // 疏朗

    public var id: CGFloat { rawValue }

    public func title(in lang: AppLanguage) -> String {
        switch lang {
        case .zhHans:
            switch self {
            case .tight: return "极紧"
            case .compact: return "紧凑"
            case .standard: return "标准"
            case .loose: return "宽松"
            case .spacious: return "疏朗"
            }
        case .zhHant:
            switch self {
            case .tight: return "極緊"
            case .compact: return "緊湊"
            case .standard: return "標準"
            case .loose: return "寬鬆"
            case .spacious: return "疏朗"
            }
        case .en:
            switch self {
            case .tight: return "Tight"
            case .compact: return "Compact"
            case .standard: return "Normal"
            case .loose: return "Loose"
            case .spacious: return "Wide"
            }
        case .de:
            switch self {
            case .tight: return "Eng"
            case .compact: return "Kompakt"
            case .standard: return "Normal"
            case .loose: return "Locker"
            case .spacious: return "Weit"
            }
        case .ja:
            switch self {
            case .tight: return "極狭"
            case .compact: return "狭い"
            case .standard: return "標準"
            case .loose: return "広い"
            case .spacious: return "極広"
            }
        }
    }

    public var ptText: String {
        "\(Int(rawValue)) pt"
    }

    public static func closest(to value: CGFloat) -> LineSpacingOption {
        allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .standard
    }
}

/// Preset fixed options for reflow reading max column width
public enum ReadingWidthOption: CGFloat, CaseIterable, Identifiable {
    case narrow = 500.0    // 窄版
    case medium = 660.0    // 适中
    case standard = 820.0  // 标准
    case wide = 1000.0     // 较宽
    case full = 1400.0     // 铺满

    public var id: CGFloat { rawValue }

    public func title(in lang: AppLanguage) -> String {
        switch lang {
        case .zhHans:
            switch self {
            case .narrow: return "窄版"
            case .medium: return "适中"
            case .standard: return "标准"
            case .wide: return "较宽"
            case .full: return "铺满"
            }
        case .zhHant:
            switch self {
            case .narrow: return "窄版"
            case .medium: return "適中"
            case .standard: return "標準"
            case .wide: return "較寬"
            case .full: return "鋪滿"
            }
        case .en:
            switch self {
            case .narrow: return "Narrow"
            case .medium: return "Medium"
            case .standard: return "Normal"
            case .wide: return "Wide"
            case .full: return "Full"
            }
        case .de:
            switch self {
            case .narrow: return "Schmal"
            case .medium: return "Mittel"
            case .standard: return "Normal"
            case .wide: return "Breit"
            case .full: return "Voll"
            }
        case .ja:
            switch self {
            case .narrow: return "スリム"
            case .medium: return "適中"
            case .standard: return "標準"
            case .wide: return "広め"
            case .full: return "最大"
            }
        }
    }

    public func description(in lang: AppLanguage) -> String {
        if self == .full {
            switch lang {
            case .zhHans: return "铺满屏幕"
            case .zhHant: return "鋪滿螢幕"
            case .en: return "Full Screen"
            case .de: return "Volle Breite"
            case .ja: return "全幅"
            }
        }
        return "\(Int(rawValue)) pt"
    }

    public static func closest(to value: CGFloat) -> ReadingWidthOption {
        allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .standard
    }
}

