import Foundation
import SwiftUI

/// Supported Interface Languages (中简、中繁、英、德、日)
public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"
    case de = "de"
    case ja = "ja"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .de: return "Deutsch"
        case .ja: return "日本語"
        }
    }

    public var shortBadge: String {
        switch self {
        case .zhHans: return "简"
        case .zhHant: return "繁"
        case .en: return "EN"
        case .de: return "DE"
        case .ja: return "日"
        }
    }

    public static func detectSystemDefault() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
        if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") {
            return .zhHant
        } else if preferred.hasPrefix("zh") {
            return .zhHans
        } else if preferred.hasPrefix("de") {
            return .de
        } else if preferred.hasPrefix("ja") {
            return .ja
        } else if preferred.hasPrefix("en") {
            return .en
        }
        return .zhHans
    }
}

/// Reading Translation Display Mode (原文 / 译文 / 双语对照)
public enum TranslationDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case original = "original"
    case translated = "translated"
    case bilingual = "bilingual"

    public var id: String { rawValue }

    public func title(in lang: AppLanguage) -> String {
        switch self {
        case .original:
            switch lang {
            case .zhHans: return "原文"
            case .zhHant: return "原文"
            case .en: return "Original"
            case .de: return "Original"
            case .ja: return "原文"
            }
        case .translated:
            switch lang {
            case .zhHans: return "译文"
            case .zhHant: return "譯文"
            case .en: return "Translated"
            case .de: return "Übersetzt"
            case .ja: return "翻訳"
            }
        case .bilingual:
            switch lang {
            case .zhHans: return "双语对照"
            case .zhHant: return "雙語對照"
            case .en: return "Bilingual"
            case .de: return "Zweisprachig"
            case .ja: return "二ヶ国語併記"
            }
        }
    }
}

/// Target Languages for Apple Built-in Translation Engine
public enum TranslationTargetLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"
    case de = "de"
    case ja = "ja"
    case fr = "fr"
    case es = "es"
    case ko = "ko"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zhHans: return "简体中文 (Chinese Simplified)"
        case .zhHant: return "繁體中文 (Chinese Traditional)"
        case .en: return "English (英语)"
        case .de: return "Deutsch (德语)"
        case .ja: return "日本語 (日语)"
        case .fr: return "Français (法语)"
        case .es: return "Español (西班牙语)"
        case .ko: return "한국어 (韩语)"
        }
    }

    public var shortName: String {
        switch self {
        case .zhHans: return "中简"
        case .zhHant: return "中繁"
        case .en: return "EN"
        case .de: return "DE"
        case .ja: return "JA"
        case .fr: return "FR"
        case .es: return "ES"
        case .ko: return "KO"
        }
    }

    public var localeLanguage: Locale.Language {
        Locale.Language(identifier: rawValue)
    }
}

/// Centralized Multi-Language Localization Dictionary for PDFview
public struct L10n {
    public let lang: AppLanguage

    public init(_ lang: AppLanguage) {
        self.lang = lang
    }

    // MARK: - App & General
    public var appName: String { "PDFview" }

    public var untitledDocument: String {
        switch lang {
        case .zhHans: return "未打开文件"
        case .zhHant: return "未開啟檔案"
        case .en: return "No File Open"
        case .de: return "Keine Datei geöffnet"
        case .ja: return "ファイル未選択"
        }
    }

    public var sampleDocumentTitle: String {
        switch lang {
        case .zhHans: return "PDFview 演示文档.pdf"
        case .zhHant: return "PDFview 展示文件.pdf"
        case .en: return "PDFview Demo.pdf"
        case .de: return "PDFview Demo.pdf"
        case .ja: return "PDFview デモ.pdf"
        }
    }

    // MARK: - Sidebar
    public var pageNavigation: String {
        switch lang {
        case .zhHans: return "页面导航"
        case .zhHant: return "頁面導覽"
        case .en: return "Pages"
        case .de: return "Seiten"
        case .ja: return "ページ一覧"
        }
    }

    public func totalPages(_ count: Int) -> String {
        switch lang {
        case .zhHans: return "共 \(count) 页"
        case .zhHant: return "共 \(count) 頁"
        case .en: return "\(count) Pages"
        case .de: return "\(count) Seiten"
        case .ja: return "全 \(count) ページ"
        }
    }

    public func pageNumber(_ num: Int) -> String {
        switch lang {
        case .zhHans: return "第 \(num) 页"
        case .zhHant: return "第 \(num) 頁"
        case .en: return "Page \(num)"
        case .de: return "Seite \(num)"
        case .ja: return "\(num) ページ"
        }
    }

    // MARK: - Toolbar & File Open
    public var openPDF: String {
        switch lang {
        case .zhHans: return "打开文件"
        case .zhHant: return "開啟檔案"
        case .en: return "Open"
        case .de: return "Öffnen"
        case .ja: return "開く"
        }
    }

    public var openPDFOrImage: String {
        switch lang {
        case .zhHans: return "打开 PDF / 图片"
        case .zhHant: return "開啟 PDF / 圖片"
        case .en: return "Open PDF / Image"
        case .de: return "PDF / Bild öffnen"
        case .ja: return "PDF・画像を開く"
        }
    }

    public var importFromPhotos: String {
        switch lang {
        case .zhHans: return "从相册导入图片"
        case .zhHant: return "從相簿匯入圖片"
        case .en: return "Import from Photos"
        case .de: return "Aus Fotos importieren"
        case .ja: return "写真から読み込む"
        }
    }

    public var openPDFHelp: String {
        switch lang {
        case .zhHans: return "打开本地 PDF 或图片文件（支持 PDF / PNG / JPG / HEIC / WebP 等）"
        case .zhHant: return "開啟本機 PDF 或圖片檔案（支援 PDF / PNG / JPG / HEIC / WebP 等）"
        case .en: return "Open a local PDF or image file (PDF, PNG, JPG, HEIC, WebP, etc.)"
        case .de: return "Lokale PDF- oder Bilddatei öffnen (PDF, PNG, JPG, HEIC, WebP usw.)"
        case .ja: return "ローカルのPDFまたは画像ファイルを開く（PDF / PNG / JPG / HEIC 等）"
        }
    }

    public var heroOpenCardTitle: String {
        switch lang {
        case .zhHans: return "打开文档开始阅读"
        case .zhHant: return "開啟檔案開始閱讀"
        case .en: return "Open Document to Start Reading"
        case .de: return "Dokument zum Lesen öffnen"
        case .ja: return "ドキュメントを開いて読書を開始"
        }
    }

    public var heroOpenCardSubtitle: String {
        switch lang {
        case .zhHans: return "支持 PDF 文档及 JPG、PNG、HEIC、WebP 等图片 · 快捷键 ⌘O"
        case .zhHant: return "支援 PDF 文件及 JPG、PNG、HEIC、WebP 等圖片 · 快捷鍵 ⌘O"
        case .en: return "Supports PDF and images (JPG, PNG, HEIC, WebP) · ⌘O"
        case .de: return "Unterstützt PDF und Bilder (JPG, PNG, HEIC, WebP) · ⌘O"
        case .ja: return "PDFおよび画像（JPG、PNG、HEIC）対応 · ⌘O"
        }
    }

    public var backgroundReflowing: String {
        switch lang {
        case .zhHans: return "后台正在智能重排..."
        case .zhHant: return "背景正在智慧重排..."
        case .en: return "Reflowing in background..."
        case .de: return "Umfluss im Hintergrund..."
        case .ja: return "バックグラウンドでリフロー中..."
        }
    }

    public var backgroundReflowReady: String {
        switch lang {
        case .zhHans: return "重排已就绪 · 点击切换"
        case .zhHant: return "重排已就緒 · 點擊切換"
        case .en: return "Reflow Ready · Tap to Switch"
        case .de: return "Umfluss bereit · Tippen"
        case .ja: return "リフロー完了・タップして切替"
        }
    }

    public var backToGuide: String {
        switch lang {
        case .zhHans: return "返回主界面"
        case .zhHant: return "返回主畫面"
        case .en: return "Back to Home"
        case .de: return "Zur Startseite"
        case .ja: return "ホームに戻る"
        }
    }

    public var backButtonTitle: String {
        switch lang {
        case .zhHans: return "返回"
        case .zhHant: return "返回"
        case .en: return "Back"
        case .de: return "Zurück"
        case .ja: return "戻る"
        }
    }

    public var readingMode: String {
        switch lang {
        case .zhHans: return "阅读模式"
        case .zhHant: return "閱讀模式"
        case .en: return "Mode"
        case .de: return "Modus"
        case .ja: return "表示モード"
        }
    }

    public func readerModeTitle(_ mode: ReaderMode) -> String {
        switch mode {
        case .reflow:
            switch lang {
            case .zhHans: return "智能重排"
            case .zhHant: return "智慧重排"
            case .en: return "Reflow"
            case .de: return "Umfluss"
            case .ja: return "リフロー"
            }
        case .ocrText:
            switch lang {
            case .zhHans: return "OCR文本"
            case .zhHant: return "OCR文字"
            case .en: return "OCR Text"
            case .de: return "OCR-Text"
            case .ja: return "OCRテキスト"
            }
        case .original:
            switch lang {
            case .zhHans: return "原始版面"
            case .zhHant: return "原始版面"
            case .en: return "Original"
            case .de: return "Original"
            case .ja: return "元ページ"
            }
        case .sideBySide:
            switch lang {
            case .zhHans: return "双屏对照"
            case .zhHant: return "雙屏對照"
            case .en: return "Split View"
            case .de: return "Geteilt"
            case .ja: return "見開き比較"
            }
        case .debug:
            switch lang {
            case .zhHans: return "版面调试"
            case .zhHant: return "版面除錯"
            case .en: return "Debug"
            case .de: return "Debug"
            case .ja: return "デバッグ"
            }
        }
    }

    // MARK: - Document Type Badges
    public func sourceTypeBadge(_ type: PDFTextSourceType) -> String {
        switch type {
        case .nativeVectorText, .ocrRecognizedText:
            switch lang {
            case .zhHans: return "文字版 PDF"
            case .zhHant: return "文字版 PDF"
            case .en: return "Text PDF"
            case .de: return "Text-PDF"
            case .ja: return "テキストPDF"
            }
        case .embeddedOCRLayer:
            switch lang {
            case .zhHans: return "双层文字 PDF"
            case .zhHant: return "雙層文字 PDF"
            case .en: return "OCR PDF"
            case .de: return "OCR-PDF"
            case .ja: return "OCR PDF"
            }
        case .scannedImage:
            switch lang {
            case .zhHans: return "图形扫描版"
            case .zhHant: return "圖形掃描版"
            case .en: return "Scanned PDF"
            case .de: return "Scan-PDF"
            case .ja: return "スキャンPDF"
            }
        }
    }

    // MARK: - Translation
    public var translateButton: String {
        switch lang {
        case .zhHans: return "翻译"
        case .zhHant: return "翻譯"
        case .en: return "Translate"
        case .de: return "Übersetzen"
        case .ja: return "翻訳"
        }
    }

    public var quickSwitchCNEN: String {
        switch lang {
        case .zhHans: return "中/英切换阅读"
        case .zhHant: return "中/英切換閱讀"
        case .en: return "CN ↔ EN Toggle"
        case .de: return "CN ↔ EN Wechsel"
        case .ja: return "中/英 切替"
        }
    }

    public var targetLanguageLabel: String {
        switch lang {
        case .zhHans: return "目标语言"
        case .zhHant: return "目標語言"
        case .en: return "Target Language"
        case .de: return "Zielsprache"
        case .ja: return "翻訳先の言語"
        }
    }

    public var translatingProgress: String {
        switch lang {
        case .zhHans: return "正在调用 Apple 翻译引擎..."
        case .zhHant: return "正在呼叫 Apple 翻譯引擎..."
        case .en: return "Translating with Apple Translation..."
        case .de: return "Übersetze mit Apple Übersetzung..."
        case .ja: return "Apple翻訳エンジンで翻訳中..."
        }
    }

    // MARK: - Theme & Ink
    public var paperTheme: String {
        switch lang {
        case .zhHans: return "阅读主题"
        case .zhHant: return "閱讀主題"
        case .en: return "Theme"
        case .de: return "Thema"
        case .ja: return "テーマ"
        }
    }

    public func themeTitle(_ theme: ReadingTheme) -> String {
        switch theme {
        case .white:
            switch lang {
            case .zhHans: return "纯白无瑕"
            case .zhHant: return "純白無瑕"
            case .en: return "Pure White"
            case .de: return "Reinweiß"
            case .ja: return "ホワイト"
            }
        case .eyeCare:
            switch lang {
            case .zhHans: return "护眼暖阳"
            case .zhHant: return "護眼暖陽"
            case .en: return "Eye Care"
            case .de: return "Augenschonend"
            case .ja: return "アイケア"
            }
        case .sepia:
            switch lang {
            case .zhHans: return "羊皮纸"
            case .zhHant: return "羊皮紙"
            case .en: return "Warm Sepia"
            case .de: return "Sepia"
            case .ja: return "セピア"
            }
        case .gray:
            switch lang {
            case .zhHans: return "柔和冷灰"
            case .zhHant: return "柔和冷灰"
            case .en: return "Soft Gray"
            case .de: return "Sanftgrau"
            case .ja: return "ソフトグレー"
            }
        case .dark:
            switch lang {
            case .zhHans: return "夜间深色"
            case .zhHant: return "夜間深色"
            case .en: return "Night Dark"
            case .de: return "Dunkelmodus"
            case .ja: return "ダーク"
            }
        }
    }

    public func inkLevelTitle(_ level: InkLevel) -> String {
        switch level {
        case .normal:
            switch lang {
            case .zhHans: return "自然原版"
            case .zhHant: return "自然原版"
            case .en: return "Natural"
            case .de: return "Natürlich"
            case .ja: return "ナチュラル"
            }
        case .enhanced:
            switch lang {
            case .zhHans: return "清晰增强"
            case .zhHant: return "清晰增強"
            case .en: return "Enhanced"
            case .de: return "Verstärkt"
            case .ja: return "くっきり"
            }
        case .dark:
            switch lang {
            case .zhHans: return "浓墨深黑"
            case .zhHant: return "濃墨深黑"
            case .en: return "Bold Ink"
            case .de: return "Kräftig"
            case .ja: return "濃墨"
            }
        case .deep:
            switch lang {
            case .zhHans: return "极深重墨"
            case .zhHant: return "極深重墨"
            case .en: return "Heavy Ink"
            case .de: return "Tiefschwarz"
            case .ja: return "極濃"
            }
        }
    }

    // MARK: - Typography Controls
    public var quickAppearanceTitle: String {
        switch lang {
        case .zhHans: return "阅读外观"
        case .zhHant: return "閱讀外觀"
        case .en: return "Appearance"
        case .de: return "Erscheinungsbild"
        case .ja: return "外観設定"
        }
    }

    public var fontSizeLabel: String {
        switch lang {
        case .zhHans: return "文字字号"
        case .zhHant: return "文字字級"
        case .en: return "Font Size"
        case .de: return "Schriftgröße"
        case .ja: return "フォントサイズ"
        }
    }

    public var lineSpacingShort: String {
        switch lang {
        case .zhHans: return "行距"
        case .zhHant: return "行距"
        case .en: return "Line"
        case .de: return "Zeilen"
        case .ja: return "行間"
        }
    }

    public var lineSpacingCompact: String {
        switch lang {
        case .zhHans: return "紧凑"
        case .zhHant: return "緊湊"
        case .en: return "Compact"
        case .de: return "Kompakt"
        case .ja: return "狭い"
        }
    }

    public var lineSpacingStandard: String {
        switch lang {
        case .zhHans: return "适中"
        case .zhHant: return "適中"
        case .en: return "Normal"
        case .de: return "Standard"
        case .ja: return "標準"
        }
    }

    public var lineSpacingLoose: String {
        switch lang {
        case .zhHans: return "宽松"
        case .zhHant: return "寬鬆"
        case .en: return "Loose"
        case .de: return "Locker"
        case .ja: return "広い"
        }
    }

    public var moreSettings: String {
        switch lang {
        case .zhHans: return "更多排版与墨水设置..."
        case .zhHant: return "更多排版與墨水設定..."
        case .en: return "More Typography Settings..."
        case .de: return "Weitere Einstellungen..."
        case .ja: return "その他の排版設定..."
        }
    }

    public var settingsTitle: String {
        switch lang {
        case .zhHans: return "页面设置"
        case .zhHant: return "頁面設定"
        case .en: return "Page Settings"
        case .de: return "Seiteneinstellungen"
        case .ja: return "ページ設定"
        }
    }

    public var textRenderModeLabel: String {
        switch lang {
        case .zhHans: return "文字排版渲染方式"
        case .zhHant: return "文字排版渲染方式"
        case .en: return "Text Render Mode"
        case .de: return "Text-Rendering-Modus"
        case .ja: return "テキスト描画モード"
        }
    }

    public var userGuideTitle: String {
        switch lang {
        case .zhHans: return "使用指南"
        case .zhHant: return "使用指南"
        case .en: return "User Guide"
        case .de: return "Handbuch"
        case .ja: return "使い方ガイド"
        }
    }

    public var interfaceLanguageTitle: String {
        switch lang {
        case .zhHans: return "界面语言"
        case .zhHant: return "介面語言"
        case .en: return "UI Language"
        case .de: return "Sprache"
        case .ja: return "表示言語"
        }
    }

    public var processingPage: String {
        switch lang {
        case .zhHans: return "正在智能重排当前页..."
        case .zhHant: return "正在智慧重排目前頁面..."
        case .en: return "Reflowing current page..."
        case .de: return "Seite wird neu angeordnet..."
        case .ja: return "ページをリフロー処理中..."
        }
    }

    public var copyParagraph: String {
        switch lang {
        case .zhHans: return "复制本段文字"
        case .zhHant: return "複製本段文字"
        case .en: return "Copy Paragraph"
        case .de: return "Absatz kopieren"
        case .ja: return "段落テキストをコピー"
        }
    }

    public var prevPageLabel: String {
        switch lang {
        case .zhHans: return "上一页"
        case .zhHant: return "上一頁"
        case .en: return "Previous Page"
        case .de: return "Vorherige Seite"
        case .ja: return "前のページ"
        }
    }

    public var nextPageLabel: String {
        switch lang {
        case .zhHans: return "下一页"
        case .zhHant: return "下一頁"
        case .en: return "Next Page"
        case .de: return "Nächste Seite"
        case .ja: return "次のページ"
        }
    }

    // MARK: - Recent Documents History & Clean Home
    public var recentDocumentsTitle: String {
        switch lang {
        case .zhHans: return "最近阅读"
        case .zhHant: return "最近閱讀"
        case .en: return "Recent Documents"
        case .de: return "Zuletzt geöffnet"
        case .ja: return "最近開いたファイル"
        }
    }

    public var clearRecentHistory: String {
        switch lang {
        case .zhHans: return "清空记录"
        case .zhHant: return "清除紀錄"
        case .en: return "Clear History"
        case .de: return "Verlauf löschen"
        case .ja: return "履歴を消去"
        }
    }

    public var noRecentDocuments: String {
        switch lang {
        case .zhHans: return "暂无最近阅读记录，点击右上角【打开 PDF / 图片】即可开始阅读"
        case .zhHant: return "暫無最近閱讀紀錄，點擊右上角【開啟 PDF / 圖片】即可開始閱讀"
        case .en: return "No recent documents. Click 'Open PDF / Image' above to start reading."
        case .de: return "Keine Dokumente. Klicken Sie oben auf 'PDF / Bild öffnen', um zu beginnen."
        case .ja: return "最近開いたファイルはありません。右上の「PDF・画像を開く」から開始できます。"
        }
    }

    public func lastReadProgress(page: Int, total: Int) -> String {
        switch lang {
        case .zhHans: return "读至第 \(page) 页 / 共 \(total) 页"
        case .zhHant: return "讀至第 \(page) 頁 / 共 \(total) 頁"
        case .en: return "Page \(page) of \(total)"
        case .de: return "Seite \(page) von \(total)"
        case .ja: return "\(page) / \(total) ページ"
        }
    }

    public var quickFeaturesGuide: String {
        switch lang {
        case .zhHans: return "快速使用指南"
        case .zhHant: return "快速使用指南"
        case .en: return "Quick Feature Guide"
        case .de: return "Kurzanleitung"
        case .ja: return "クイックガイド"
        }
    }

    public var settingsLanguageTip: String {
        switch lang {
        case .zhHans: return "提示：可在偏好设置中随时切换界面语言、排版主题及字号"
        case .zhHant: return "提示：可在偏好設定中隨時切換介面語言、排版主題及字型大小"
        case .en: return "Tip: You can change UI language, paper themes, and font size in Settings anytime."
        case .de: return "Tipp: Sie können Sprache, Design und Schriftgröße jederzeit in den Einstellungen ändern."
        case .ja: return "ヒント：設定画面から表示言語・テーマ・文字サイズをいつでも変更できます。"
        }
    }

    public var fileNotFoundOrMoved: String {
        switch lang {
        case .zhHans: return "原文件已被移动或删除"
        case .zhHant: return "原始檔案已被移動或刪除"
        case .en: return "File has been moved or deleted"
        case .de: return "Datei wurde verschoben oder gelöscht"
        case .ja: return "ファイルが移動または削除されました"
        }
    }

    // MARK: - Copy Current Page Text
    public var copyPageText: String {
        switch lang {
        case .zhHans: return "复制当前页文字"
        case .zhHant: return "複製當前頁文字"
        case .en: return "Copy Page Text"
        case .de: return "Seitentext kopieren"
        case .ja: return "ページ文字をコピー"
        }
    }

    public var copyPageTextHelp: String {
        switch lang {
        case .zhHans: return "将当前页面提取或重排的文字复制到剪贴板 (⌘⇧C)"
        case .zhHant: return "將當前頁面擷取或重排的文字複製到剪貼簿 (⌘⇧C)"
        case .en: return "Copy current page text to clipboard (⌘⇧C)"
        case .de: return "Seitentext in die Zwischenablage kopieren (⌘⇧C)"
        case .ja: return "現在のページのテキストをクリップボードにコピー (⌘⇧C)"
        }
    }

    public var copiedPageTextSuccess: String {
        switch lang {
        case .zhHans: return "已复制当前页面文字到剪贴板"
        case .zhHant: return "已複製當前頁面文字至剪貼簿"
        case .en: return "Copied current page text to clipboard"
        case .de: return "Seitentext in die Zwischenablage kopiert"
        case .ja: return "現在のページのテキストをコピーしました"
        }
    }

    public var noCopyableText: String {
        switch lang {
        case .zhHans: return "当前页面无可复制的文字"
        case .zhHant: return "當前頁面無可複製的文字"
        case .en: return "No text available on current page"
        case .de: return "Kein Text auf aktueller Seite verfügbar"
        case .ja: return "コピー可能なテキストがありません"
        }
    }

    // MARK: - Home Promotional Slogans (精炼广告词与突出特点)
    public var homeHeroSlogan: String {
        switch lang {
        case .zhHans: return "小屏幕畅读大文件 · 复杂版面自由重排"
        case .zhHant: return "小螢幕暢讀大檔案 · 複雜版面自由重排"
        case .en: return "Read Big Documents Smoothly on Small Screens"
        case .de: return "Große Dokumente flüssig auf kleinen Bildschirmen lesen"
        case .ja: return "小さな画面でも大判ファイルを快適に読める"
        }
    }

    public var homeHeroSubSlogan: String {
        switch lang {
        case .zhHans: return "小屏幕畅读大文件 · 动态图文重排 · 实时识别复制 · 竖排转横排 · 双语对照"
        case .zhHant: return "小螢幕暢讀大檔案 · 動態圖文重排 · 即時識別複製 · 豎排轉橫排 · 雙語對照"
        case .en: return "Read Big Documents Smoothly on Small Screens · Dynamic Reflow · Real-time OCR · Native Translation"
        case .de: return "Große Dokumente flüssig auf kleinen Bildschirmen lesen · Dynamischer Umfluss · Live-OCR"
        case .ja: return "小さな画面でも大判ファイルを快適に読める · 動的リフロー · リアルタイムOCR＆コピー · 日英対訳"
        }
    }

    // 1. 文字和图形动态重排和缩放
    public var homeFeature1Title: String {
        switch lang {
        case .zhHans: return "图形切片与矢量文字 · 随心切换"
        case .zhHant: return "圖形切片與向量文字 · 隨心切換"
        case .en: return "Graphic Slices & Vector Text · Free Switch"
        case .de: return "Bildschnitte & Vektortext · Frei wählbar"
        case .ja: return "画像スライス＆ベクター文字・自在に切替"
        }
    }

    public var homeFeature1Desc: String {
        switch lang {
        case .zhHans: return "默认启用原汁原味的图形文字横排，完好保留原版印刷字体与插图排版；顶栏轻触即可直切矢量文字横排，享受零失真自由缩放与长按划词。"
        case .zhHant: return "預設啟用原汁原味的圖形文字橫排，完好保留原版印刷字體與插圖排版；頂列輕觸即可直切向量文字橫排，享受零失真自由縮放與長按劃詞。"
        case .en: return "Defaults to faithful image-slice horizontal reflow to preserve authentic typography and illustrations; switch to vector text with 1 tap for lossless scaling and text selection."
        case .de: return "Standardmäßig originalgetreuer Bildschnitt-Umfluss für authentische Typografie; mit 1 Klick zu Vektortext für verlustfreien Zoom und Textauswahl."
        case .ja: return "デフォルトで原本の活字や図版配置を美しく保つ画像スライス横書きリフローを適用。1タップで拡大縮小・選択自在なベクター文字に切り替えられます。"
        }
    }

    // 2. 页面文字实时光学识别和复制
    public var homeFeature2Title: String {
        switch lang {
        case .zhHans: return "极速 OCR 识别 · 一键直观复制"
        case .zhHant: return "極速 OCR 識別 · 一鍵直觀複製"
        case .en: return "High-Speed OCR · 1-Tap Copy"
        case .de: return "Schnelle OCR · 1-Klick-Kopie"
        case .ja: return "高速OCR認識＆ワンタップコピー"
        }
    }

    public var homeFeature2Desc: String {
        switch lang {
        case .zhHans: return "多核视觉引擎毫秒级识别扫描件与图像文字，顶栏常驻一键复制整页文本；可在重排中长按划词选句与双语翻译。"
        case .zhHant: return "多核心視覺引擎毫秒級識別掃描檔與圖像文字，頂列常駐一鍵複製整頁文字；可在重排中長按劃詞選句與雙語翻譯。"
        case .en: return "High-speed OCR instantly recognizes scanned text with permanent toolbar copy button; long-press to select text or translate in reflow."
        case .de: return "Erkennt gescannten Text blitzschnell mit 1-Klick-Kopie in der Leiste; langes Drücken zur Textauswahl und Übersetzung im Umfluss."
        case .ja: return "高速OCRがスキャン文字を瞬時に認識し、ツールバーからワンタップで全文コピー可能。リフロー中も長押し選択や二ヶ国語翻訳に対応。"
        }
    }

    // 3. 竖排文字转成横排阅读
    public var homeFeature3Title: String {
        switch lang {
        case .zhHans: return "竖排独立复选框 · 古籍流式畅读"
        case .zhHant: return "直排獨立核取方塊 · 古籍流式暢讀"
        case .en: return "Dedicated Vertical Checkbox · Flowing Reading"
        case .de: return "Vertikal-Checkbox · Nahtloser Lesefluss"
        case .ja: return "専用の縦書きチェックボックス＆流暢な読書"
        }
    }

    public var homeFeature3Desc: String {
        switch lang {
        case .zhHans: return "顶栏专设独立「竖排」复选框，一触直接切换，拒绝复杂菜单；自适应将古籍由右至左按列解构，重排为最适合手机屏幕的舒适排版。"
        case .zhHant: return "頂列專設獨立「直排」核取方塊，一觸直接切換，拒絕複雜選單；自適應將古籍由右至左按列解構，重排為最適合手機螢幕的舒適排版。"
        case .en: return "A dedicated checkbox instantly toggles vertical layout without nested menus; intelligently deconstructs RTL vertical columns into comfortable mobile reading."
        case .de: return "Eigene Checkbox schaltet vertikalen Text sofort ohne Untermenüs um; wandelt klassische Spalten in optimalen Lesefluss für Mobilgeräte um."
        case .ja: return "ツールバー専用のチェックボックスで迷わず縦書きを切替可能。伝統的な右起きの縦書き文書をスマホ画面に最適化されたリフローで読めます。"
        }
    }

    // 4. 触屏手势与目录大纲导航
    public var homeFeature4Title: String {
        switch lang {
        case .zhHans: return "左右滑动手势翻页 · 目录大纲导航"
        case .zhHant: return "左右滑動作手勢翻頁 · 目錄大綱導覽"
        case .en: return "Swipe Gestures · Outline & Bookmarks TOC"
        case .de: return "Wischgesten zum Blättern · Inhaltsverzeichnis"
        case .ja: return "スワイプでページ送り＆目次・しおり連動"
        }
    }

    public var homeFeature4Desc: String {
        switch lang {
        case .zhHans: return "屏幕左右轻扫即刻顺滑切页，横排/竖排自动顺应翻页流向；点击底栏页码一键展开多级章节目录大纲与精准滑块，百页长书秒达目标。"
        case .zhHant: return "螢幕左右輕掃即刻順滑切頁，橫排/直排自動順應翻頁流向；點擊底列頁碼一鍵展開多級章節目錄大綱與精準滑桿，百頁長書秒達目標。"
        case .en: return "Swipe left/right anywhere to turn pages smoothly; tap the bottom page badge to open hierarchical table of contents and precision slider for instant navigation."
        case .de: return "Wischen Sie nach links/rechts zum Blättern; tippen Sie auf die Seitenzahl für ein mehrstufiges Inhaltsverzeichnis und schnellen Kapitelsprung."
        case .ja: return "画面を左右にスワイプするだけで軽快にページ送り。下のページ番号をタップすれば階層付き目次やスライダーが開き、長編書物も一瞬で目的地へ。"
        }
    }

    // 5. 支持 PDF 和各种图片格式
    public var homeFeature5Title: String {
        switch lang {
        case .zhHans: return "支持 PDF 与全图 · 设置集成双语翻译"
        case .zhHant: return "支援 PDF 與全圖 · 設定整合雙語翻譯"
        case .en: return "All PDFs & Images · Integrated Translation"
        case .de: return "Alle PDFs & Bilder · Integrierte Übersetzung"
        case .ja: return "全PDF＆画像対応・設定でバイリンガル翻訳"
        }
    }

    public var homeFeature5Desc: String {
        switch lang {
        case .zhHans: return "全面支持各类文字/扫描版 PDF 以及手机相册拍摄图片；设置弹窗集成 Apple 原生离线双语对照翻译，主界面清爽极简无下拉菜单。"
        case .zhHant: return "全面支援各類文字/掃描版 PDF 以及手機相簿拍攝圖片；設定彈窗整合 Apple 原生離線雙語對照翻譯，主介面清爽極簡無下拉選單。"
        case .en: return "Full support for PDFs and camera photos; Settings panel seamlessly integrates Apple offline bilingual translation while keeping the reader free of dropdowns."
        case .de: return "Unterstützt PDFs und Fotos; die Einstellungen bieten integrierte Apple-Offline-Übersetzung, während die Leseansicht frei von störenden Menüs bleibt."
        case .ja: return "あらゆるPDFや写真画像に対応。設定画面にAppleオフライン二ヶ国語翻訳を統合し、読書画面はドロップダウンのない極めてシンプルな構成です。"
        }
    }

    public var viewFullGuideLink: String {
        switch lang {
        case .zhHans: return "使用指南与功能详解"
        case .zhHant: return "使用指南與功能詳解"
        case .en: return "User Guide & Features"
        case .de: return "Anleitung & Funktionen"
        case .ja: return "ユーザーガイド・機能説明"
        }
    }
}

