import Foundation
import CoreGraphics
import PDFKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public final class ReflowEngine: @unchecked Sendable {
    public static let shared = ReflowEngine()

    private let cache = NSCache<NSString, ReflowResultBox>()

    private final class ReflowResultBox: @unchecked Sendable {
        let result: PageReflowResult
        init(_ result: PageReflowResult) { self.result = result }
    }

    public init() {
        cache.countLimit = 50
    }

    public func clearCache() {
        cache.removeAllObjects()
    }

    /// Renders a PDFPage to a high-resolution CGImage with crisp typography,
    /// correctly respecting cropBox bounds and physical page rotation.
    public static func renderPageToCGImage(page: PDFPage, dpi: CGFloat = 200.0) -> CGImage? {
        let cropBox = page.bounds(for: .cropBox)
        let rot = ((page.rotation % 360) + 360) % 360
        let isRotated = (rot == 90 || rot == 270)
        let logicalSize = isRotated ? CGSize(width: cropBox.height, height: cropBox.width) : cropBox.size
        var scale = dpi / 72.0 // PDF default resolution is 72 dpi
        let maxDim = max(logicalSize.width * scale, logicalSize.height * scale)
        if maxDim > 8192.0 {
            scale = 8192.0 / max(logicalSize.width, logicalSize.height)
        }
        let pixelWidth = Int(ceil(logicalSize.width * scale))
        let pixelHeight = Int(ceil(logicalSize.height * scale))

        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Fill white background for scanned document
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // PDFKit handles cropBox and rotation correctly when drawn to scaled context
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()

        return context.makeImage()
    }

    /// Convenience helper to render and process a PDFPage from MainActor,
    /// automatically detecting native vector text layers vs scanned images,
    /// and providing Retina-grade supersampled backing crops for standard-size pages.
    @MainActor
    public func processPage(
        page: PDFPage,
        pageIndex: Int,
        config: ReflowConfig
    ) async -> PageReflowResult? {
        var effectiveConfig = config
        if page.document?.documentAttributes?[PDFDocumentAttribute(rawValue: "IsImageDocument")] != nil {
            effectiveConfig.isImageDocument = true
        }

        guard let rawCG = Self.renderPageToCGImage(page: page, dpi: effectiveConfig.renderDPI) else {
            return nil
        }

        // Apply Intelligent Preprocessing (Deskew, Crop Black Borders, Bleach, Sharpen)
        let cgImage: CGImage
        if effectiveConfig.enablePageEnhancement {
            let pre = PagePreprocessEngine.shared.processCGImage(rawCG, config: effectiveConfig)
            cgImage = pre.processedImage
        } else {
            cgImage = rawCG
        }

        let textLayerResult = PDFTextLayerAnalyzer.analyze(
            page: page,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            cgImage: cgImage
        )

        // For standard-sized pages (A4/B5 <= 950pt), render a 320 DPI Retina backing image
        // so cropped figures, tables, and glyph slices remain razor-sharp when magnified.
        // Oversized cropBox pages (e.g. 1440x1861pt) already produce 4000px+ images and do not need extra supersampling.
        let cropBox = page.bounds(for: .cropBox)
        let maxLogicalDim = max(cropBox.width, cropBox.height)
        let highResCG: CGImage?
        if maxLogicalDim <= 950.0 && effectiveConfig.renderDPI < 300.0 {
            let targetDPI = min(320.0, max(280.0, effectiveConfig.renderDPI * 1.5))
            let rawHiCG = Self.renderPageToCGImage(page: page, dpi: targetDPI)
            if let rawHi = rawHiCG, effectiveConfig.enablePageEnhancement {
                let preHi = PagePreprocessEngine.shared.processCGImage(rawHi, config: effectiveConfig)
                highResCG = preHi.processedImage
            } else {
                highResCG = rawHiCG
            }
        } else {
            highResCG = nil
        }

        guard let baseResult = await processRenderedImage(
            cgImage: cgImage,
            pageIndex: pageIndex,
            config: effectiveConfig,
            preExtractedTextLayer: textLayerResult
        ) else {
            return nil
        }

        if let hiCG = highResCG, hiCG.width > cgImage.width {
            return Self.upgradeResultWithHighResBacking(
                result: baseResult,
                highResImage: hiCG,
                baseWidth: cgImage.width,
                baseHeight: cgImage.height,
                config: config
            )
        }
        return baseResult
    }

    /// Replaces slice and figure NSImages with Retina-supersampled crops while preserving exact logical coordinates
    private static func upgradeResultWithHighResBacking(
        result: PageReflowResult,
        highResImage: CGImage,
        baseWidth: Int,
        baseHeight: Int,
        config: ReflowConfig
    ) -> PageReflowResult {
        // Vertical book glyph slices are specially segmented with character pitch,
        // punctuation orientation (CCW rotation) and adaptive thresholds; preserve them intact.
        if result.resolvedProfile == .verticalBook {
            return result
        }

        let scaleX = CGFloat(highResImage.width) / CGFloat(max(1, baseWidth))
        let scaleY = CGFloat(highResImage.height) / CGFloat(max(1, baseHeight))
        let isVectorTextPage = result.textSourceType == .nativeVectorText || result.textSourceType == .ocrRecognizedText

        func upgradeSlice(_ slice: PageSlice) -> PageSlice {
            let hiRect = CGRect(
                x: slice.originalRect.minX * scaleX,
                y: slice.originalRect.minY * scaleY,
                width: slice.originalRect.width * scaleX,
                height: slice.originalRect.height * scaleY
            )
            let isGraphic = slice.isFigure || slice.isTable
            let hiNSImage: NSImage
            if let cropped = ImageEnhancer.crop(image: highResImage, to: hiRect) {
                let finalCG = (isGraphic || isVectorTextPage)
                    ? cropped
                    : ImageEnhancer.enhance(image: cropped, mode: config.binarizationMode, threshold: 200, config: config, isGraphic: false)
                hiNSImage = NSImage(cgImage: finalCG, size: NSSize(width: slice.originalRect.width, height: slice.originalRect.height))
            } else {
                hiNSImage = slice.image
            }

            // Upgrade word slices only when image-slice rendering is active or for non-vector pages
            let shouldUpgradeWords = !isVectorTextPage || config.textRenderMode == .imageSlices
            let hiWords: [WordSlice]
            if shouldUpgradeWords {
                hiWords = slice.words.map { w -> WordSlice in
                    let wRect = CGRect(
                        x: w.originalRect.minX * scaleX,
                        y: w.originalRect.minY * scaleY,
                        width: w.originalRect.width * scaleX,
                        height: w.originalRect.height * scaleY
                    )
                    guard let wCrop = ImageEnhancer.crop(image: highResImage, to: wRect) else { return w }
                    let finalWCG = isVectorTextPage
                        ? wCrop
                        : ImageEnhancer.enhance(image: wCrop, mode: config.binarizationMode, threshold: 200, config: config, isGraphic: false)
                    let wImg = NSImage(cgImage: finalWCG, size: NSSize(width: w.originalRect.width, height: w.originalRect.height))
                    return WordSlice(id: w.id, originalRect: w.originalRect, image: wImg)
                }
            } else {
                hiWords = slice.words
            }

            return PageSlice(
                id: slice.id,
                pageIndex: slice.pageIndex,
                columnIndex: slice.columnIndex,
                sliceIndex: slice.sliceIndex,
                originalRect: slice.originalRect,
                columnWidth: slice.columnWidth,
                image: hiNSImage,
                isFigure: slice.isFigure,
                isTable: slice.isTable,
                isSideBySide: slice.isSideBySide,
                words: hiWords,
                recognizedText: slice.recognizedText
            )
        }

        let shouldUpgradeWords = !isVectorTextPage || config.textRenderMode == .imageSlices
        let upgradedSlices = result.allSlices.map(upgradeSlice)
        let upgradedParagraphs = result.paragraphs.map { p -> ParagraphBlock in
            let hiFig = p.figureSlice.map(upgradeSlice)
            let hiSideFig = p.sideFigure.map(upgradeSlice)
            let hiWords: [WordSlice]
            if shouldUpgradeWords {
                hiWords = p.words.map { w -> WordSlice in
                    let wRect = CGRect(
                        x: w.originalRect.minX * scaleX,
                        y: w.originalRect.minY * scaleY,
                        width: w.originalRect.width * scaleX,
                        height: w.originalRect.height * scaleY
                    )
                    guard let wCrop = ImageEnhancer.crop(image: highResImage, to: wRect) else { return w }
                    let finalWCG = isVectorTextPage
                        ? wCrop
                        : ImageEnhancer.enhance(image: wCrop, mode: config.binarizationMode, threshold: 200, config: config, isGraphic: false)
                    let wImg = NSImage(cgImage: finalWCG, size: NSSize(width: w.originalRect.width, height: w.originalRect.height))
                    return WordSlice(id: w.id, originalRect: w.originalRect, image: wImg)
                }
            } else {
                hiWords = p.words
            }
            return ParagraphBlock(
                id: p.id,
                paragraphIndex: p.paragraphIndex,
                columnIndex: p.columnIndex,
                hasIndent: p.hasIndent,
                isTitle: p.isTitle,
                semanticLevel: p.semanticLevel,
                isFigure: p.isFigure,
                isTable: p.isTable,
                isSideBySide: p.isSideBySide,
                figureOnRight: p.figureOnRight,
                figureSlice: hiFig,
                sideFigure: hiSideFig,
                words: hiWords,
                baseLineHeight: p.baseLineHeight,
                recognizedText: p.recognizedText
            )
        }

        return PageReflowResult(
            pageIndex: result.pageIndex,
            originalImage: result.originalImage,
            contentBounds: result.contentBounds,
            columns: result.columns,
            allSlices: upgradedSlices,
            paragraphs: upgradedParagraphs,
            resolvedProfile: result.resolvedProfile,
            zones: result.zones,
            textSourceType: result.textSourceType,
            isImageDocument: result.isImageDocument
        )
    }

    /// Processes a rendered page image into reflowed slices
    public func processRenderedImage(
        cgImage: CGImage,
        pageIndex: Int,
        config: ReflowConfig,
        preExtractedTextLayer: PDFTextLayerAnalysisResult? = nil
    ) async -> PageReflowResult? {
        let sampleBytes: Int
        if let data = cgImage.dataProvider?.data, CFDataGetLength(data) >= 64 {
            let ptr = CFDataGetBytePtr(data)
            let mid = CFDataGetLength(data) / 2
            sampleBytes = Int(ptr?[mid] ?? 0) ^ (Int(ptr?[mid + 16] ?? 0) << 8) ^ (Int(ptr?[mid + 32] ?? 0) << 16)
        } else {
            sampleBytes = 0
        }
        let textSourceType = preExtractedTextLayer?.sourceType ?? .scannedImage
        let affinityKey = config.documentLayoutAffinity?.rawValue ?? "none"
        let cacheKey = NSString(string: "\(cgImage.width)x\(cgImage.height)_\(sampleBytes)_\(pageIndex)_\(config.renderDPI)_\(config.trimMargins)_\(config.detectColumns)_\(config.binarizationMode.rawValue)_\(config.layoutProfile.rawValue)_\(config.inkLevel.rawValue)_\(config.textContrast)_\(config.textDarkening)_\(config.strokeThickening)_\(config.textSharpening)_\(textSourceType.rawValue)_\(config.isImageDocument)_\(affinityKey)")
        if let cached = cache.object(forKey: cacheKey) {
            return cached.result
        }

        return await Task.detached(priority: .userInitiated) { [weak self] () -> PageReflowResult? in
            guard let pixelBuffer = PixelBuffer(cgImage: cgImage) else {
                return nil
            }

            // Calculate adaptive Otsu threshold for robust layout segmentation (ink vs paper background)
            let layoutThreshold = pixelBuffer.calculateOtsuThreshold()

            // Determine visual rendering threshold for slice enhancement
            let visualThreshold: UInt8
            switch config.binarizationMode {
            case .otsu, .adaptive:
                visualThreshold = layoutThreshold
            case .contrastEnhanced, .original:
                visualThreshold = UInt8(clamp(Double(config.thresholdValue * 255.0), min: 50.0, max: 240.0))
            }

            // Margin Detection (Auto-crop white edges)
            let contentBounds: CGRect
            if config.trimMargins {
                contentBounds = MarginDetector.detectContentBounds(
                    pixelBuffer: pixelBuffer,
                    threshold: layoutThreshold
                )
            } else {
                contentBounds = CGRect(x: 0, y: 0, width: pixelBuffer.width, height: pixelBuffer.height)
            }

            // Preliminary column detection
            let detectedColumns = ColumnDetector.detectColumns(
                pixelBuffer: pixelBuffer,
                contentBounds: contentBounds,
                threshold: layoutThreshold,
                minGapRatio: config.minColumnGapRatio
            )

            // 🌟 Upfront Vertical Book Check:
            // 竖排作为独立选项，避免智能识别误将横排文字误判为竖排
            let isVerticalBook = (config.layoutProfile == .verticalBook)

            let resolvedProfile: LayoutProfile
            let visionAnalysis: VisionPageAnalysis?

            if isVerticalBook {
                resolvedProfile = .verticalBook
                visionAnalysis = preExtractedTextLayer?.visionAnalysis
                // For vertical books, we strictly DO NOT run full-page horizontal VisionTextRecognizer!
                // Column decomposition and glyph segmentation are handled natively by VerticalTextSegmenter.
            } else {
                // Semantic guidance & text layer for horizontal layouts:
                // Priority 1: If the PDF page has a true Native Vector Text Layer, use its 100% exact text & geometry directly!
                // Priority 2: Otherwise, run Apple Vision OCR (and fall back to embedded OCR layer if Vision returns empty).
                if textSourceType == .nativeVectorText, let nativeVision = preExtractedTextLayer?.visionAnalysis, !nativeVision.lines.isEmpty {
                    visionAnalysis = nativeVision
                } else if config.enableVisionOCR {
                    if let ocrResult = VisionTextRecognizer.recognize(cgImage: cgImage), !ocrResult.lines.isEmpty {
                        visionAnalysis = ocrResult
                    } else {
                        visionAnalysis = preExtractedTextLayer?.visionAnalysis
                    }
                } else {
                    visionAnalysis = preExtractedTextLayer?.visionAnalysis
                }

                // Determine effective LayoutProfile (Human-AI Collaboration / 4th Layer)
                if config.layoutProfile != .auto {
                    resolvedProfile = config.layoutProfile
                } else {
                    resolvedProfile = LayoutClassifier.classify(
                        detectedColumns: detectedColumns,
                        contentBounds: contentBounds,
                        visionAnalysis: visionAnalysis,
                        pixelBuffer: pixelBuffer,
                        hasDocumentAffinity: false
                    )
                }
            }

            // Apply profile-driven strategies to reflow configuration
            var effectiveConfig = config
            effectiveConfig.layoutProfile = resolvedProfile
            if textSourceType == .nativeVectorText {
                // Native vector PDFs are already pristine vector renders without scan noise
                effectiveConfig.binarizationMode = .original
            }

            let columnRects: [CGRect]
            switch resolvedProfile {
            case .academic, .magazine:
                // Double or multi-column layout is prioritized
                effectiveConfig.detectColumns = true
                columnRects = detectedColumns.isEmpty ? [contentBounds] : detectedColumns
            case .book, .officialDoc, .auto, .verticalBook:
                // Single-column flow is strictly preserved; prevent accidental column slicing
                effectiveConfig.detectColumns = false
                columnRects = [contentBounds]
            }

            // 🌟 Vertical Book Route: 古籍/港台竖排书籍自适应解构并转为现代横排流式
            if resolvedProfile == .verticalBook {
                let (vSlices, vParagraphs, vCols) = VerticalTextSegmenter.segmentVerticalPage(
                    pixelBuffer: pixelBuffer,
                    originalImage: cgImage,
                    contentBounds: contentBounds,
                    threshold: layoutThreshold,
                    visualThreshold: visualThreshold,
                    pageIndex: pageIndex,
                    config: effectiveConfig,
                    visionAnalysis: visionAnalysis
                )

                let fullImage = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )

                let result = PageReflowResult(
                    pageIndex: pageIndex,
                    originalImage: fullImage,
                    contentBounds: contentBounds,
                    columns: vCols,
                    allSlices: vSlices,
                    paragraphs: vParagraphs,
                    resolvedProfile: resolvedProfile,
                    zones: [PageZone(type: .body, rect: contentBounds, slices: vSlices, paragraphs: vParagraphs)],
                    textSourceType: textSourceType,
                    isImageDocument: effectiveConfig.isImageDocument
                )

                self?.cache.setObject(ReflowResultBox(result), forKey: cacheKey)
                return result
            }

            // Macro Whitespace Partitioning: Divide page into physical zones
            // (Header, Body columns, Footnote, Footer) based on whitespace distribution
            let macroZones = PageZoneDetector.detectZones(
                pixelBuffer: pixelBuffer,
                contentBounds: contentBounds,
                layoutThreshold: layoutThreshold,
                visionAnalysis: visionAnalysis,
                resolvedProfile: resolvedProfile,
                detectedColumns: columnRects
            )

            var segmentedZones: [(zone: PageZone, slices: [PageSlice])] = []
            for zone in macroZones.allZones {
                let zoneSlices = LineSegmenter.segmentLines(
                    pixelBuffer: pixelBuffer,
                    originalImage: cgImage,
                    columnRect: zone.rect,
                    threshold: layoutThreshold,
                    visualThreshold: visualThreshold,
                    pageIndex: pageIndex,
                    columnIndex: zone.columnIndex,
                    config: effectiveConfig,
                    visionAnalysis: visionAnalysis
                )
                segmentedZones.append((zone: zone, slices: zoneSlices))
            }

            // Compute page-wide median body line height across all body text slices so all columns and
            // spanning title/caption zones share a single unified reference height
            let allPageTextHeights = segmentedZones
                .filter { $0.zone.type == .body }
                .flatMap { $0.slices }
                .filter { !$0.isFigure && !$0.isTable && !$0.isSideBySide && !$0.words.isEmpty }
                .map { $0.originalRect.height }
                .sorted()
            let globalBodyHeight: CGFloat? = allPageTextHeights.isEmpty ? nil : allPageTextHeights[allPageTextHeights.count / 2]

            var populatedZones: [PageZone] = []
            var allSlices: [PageSlice] = []
            var allParagraphs: [ParagraphBlock] = []

            for item in segmentedZones {
                var zone = item.zone
                let zoneSlices = item.slices

                let zonePars = WordSegmenter.clusterIntoParagraphs(
                    slices: zoneSlices,
                    columnIndex: zone.columnIndex,
                    columnRect: zone.rect,
                    visionAnalysis: visionAnalysis,
                    config: effectiveConfig,
                    zoneType: zone.type,
                    globalBodyHeight: globalBodyHeight,
                    pageHeight: contentBounds.maxY
                )

                zone.slices = zoneSlices
                zone.paragraphs = zonePars
                populatedZones.append(zone)

                allSlices.append(contentsOf: zoneSlices)
                allParagraphs.append(contentsOf: zonePars)
            }

            // Group slices by body zone / columnIndex to maintain columns compatibility
            var columns: [ColumnRegion] = []
            let effectiveColRects = macroZones.bodyZones.count > columnRects.count ? macroZones.bodyZones.map { $0.rect } : columnRects
            for (colIdx, colRect) in effectiveColRects.enumerated() {
                let colSlices = allSlices.filter { $0.columnIndex == colIdx }
                columns.append(ColumnRegion(index: colIdx, rect: colRect, slices: colSlices))
            }

            let fullImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )

            // Determine resolved textSourceType:
            // 1. If native vector text or embedded OCR layer was found by PDFTextLayerAnalyzer, keep it.
            // 2. If it's a PDF document (not an imported camera photo image) and Vision OCR extracted structured text (>= 20 chars), upgrade to .ocrRecognizedText!
            let totalOcrChars = allParagraphs.compactMap { $0.recognizedText }.reduce(0) { $0 + $1.count }
            let resolvedSourceType: PDFTextSourceType
            if textSourceType == .nativeVectorText {
                resolvedSourceType = .nativeVectorText
            } else if textSourceType == .embeddedOCRLayer {
                resolvedSourceType = .embeddedOCRLayer
            } else if !config.isImageDocument && totalOcrChars >= 20 {
                resolvedSourceType = .ocrRecognizedText
            } else {
                resolvedSourceType = .scannedImage
            }

            let result = PageReflowResult(
                pageIndex: pageIndex,
                originalImage: fullImage,
                contentBounds: contentBounds,
                columns: columns,
                allSlices: allSlices,
                paragraphs: allParagraphs,
                resolvedProfile: resolvedProfile,
                zones: populatedZones,
                textSourceType: resolvedSourceType,
                isImageDocument: config.isImageDocument
            )

            self?.cache.setObject(ReflowResultBox(result), forKey: cacheKey)
            return result
        }.value
    }
}

private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
    if value < min { return min }
    if value > max { return max }
    return value
}
