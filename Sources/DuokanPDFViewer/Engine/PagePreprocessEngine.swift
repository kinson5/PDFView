import Foundation
import CoreGraphics
import CoreImage
import Vision
import PDFKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Result of preprocessing and optimizing a page image
public struct PagePreprocessResult: @unchecked Sendable {
    public let processedImage: CGImage
    public let originalSize: CGSize
    public let deskewAngle: CGFloat // Angle in degrees (e.g. -1.2°)
    public let cropRect: CGRect // Effective content bounds in pixel coordinates
    public let isPerspectiveCorrected: Bool
    public let isDeskewed: Bool
    public let isCropApplied: Bool
    public let isStaplesRemoved: Bool
    public let isBleached: Bool
    public let isSharpened: Bool
    public let enhanceMode: ScanEnhanceMode

    public init(
        processedImage: CGImage,
        originalSize: CGSize,
        deskewAngle: CGFloat = 0.0,
        cropRect: CGRect = .zero,
        isPerspectiveCorrected: Bool = false,
        isDeskewed: Bool = false,
        isCropApplied: Bool = false,
        isStaplesRemoved: Bool = false,
        isBleached: Bool = false,
        isSharpened: Bool = false,
        enhanceMode: ScanEnhanceMode = .cleanBW
    ) {
        self.processedImage = processedImage
        self.originalSize = originalSize
        self.deskewAngle = deskewAngle
        self.cropRect = cropRect
        self.isPerspectiveCorrected = isPerspectiveCorrected
        self.isDeskewed = isDeskewed
        self.isCropApplied = isCropApplied
        self.isStaplesRemoved = isStaplesRemoved
        self.isBleached = isBleached
        self.isSharpened = isSharpened
        self.enhanceMode = enhanceMode
    }
}

/// GPU & Vision-powered Document Scanner Preprocessing Engine:
/// 1. Quad Detection & Perspective Stretch Unwarping (拉伸纠正 / 梯形矫正)
/// 2. Auto Page Border Cropping & Scanner Black Frame Removal (切除黑边与杂色)
/// 3. Fast Text Baseline Deskew Tilt Correction (文本行倾斜摆正)
/// 4. Illumination Flattening via GPU Morphology Division (光照阴影抹平 / 底灰彻底清除)
/// 5. True Document Scan Modes (黑白清爽扫描稿 / 魔术彩色 / 专业灰度 / 苹果文稿滤镜)
/// 6. High-Frequency Luminance Edge Sharpening & Ink Darkening (字迹浓黑锐化)
public final class PagePreprocessEngine: @unchecked Sendable {
    public static let shared = PagePreprocessEngine()

    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .priorityRequestLow: false
    ])

    private let cache = NSCache<NSString, PagePreprocessResultBox>()

    private final class PagePreprocessResultBox: @unchecked Sendable {
        let result: PagePreprocessResult
        init(_ result: PagePreprocessResult) { self.result = result }
    }

    public init() {
        cache.countLimit = 40
    }

    public func clearCache() {
        cache.removeAllObjects()
    }

    /// Preprocesses a PDFPage to an optimized high-resolution CGImage with optional caching
    @MainActor
    public func preprocessPage(
        page: PDFPage,
        pageIndex: Int,
        docIdentifier: String,
        config: ReflowConfig
    ) async -> PagePreprocessResult? {
        guard let rawCG = ReflowEngine.renderPageToCGImage(page: page, dpi: config.renderDPI) else {
            return nil
        }

        let manualQuadKey = config.manualPageQuad.map { "\($0.topLeft)_\($0.topRight)_\($0.bottomRight)_\($0.bottomLeft)" } ?? "none"
        let cacheKey = NSString(string: "\(docIdentifier)_p\(pageIndex)_r\(page.rotation)_\(config.renderDPI)_\(config.enablePageEnhancement)_\(config.scanEnhanceMode.rawValue)_\(config.autoPerspectiveCorrection)_\(config.autoDeskew)_\(config.autoCropBlackBorders)_\(config.autoRemoveStaplesAndPunchHoles)_\(config.backgroundBleachLevel.rawValue)_\(config.pageSharpening)_mq\(manualQuadKey)")
        if let cached = cache.object(forKey: cacheKey) {
            return cached.result
        }

        let result = await Task.detached(priority: .userInitiated) { [weak self, ciContext] in
            guard let self = self else {
                return PagePreprocessResult(processedImage: rawCG, originalSize: CGSize(width: rawCG.width, height: rawCG.height))
            }
            return self.processCGImage(rawCG, config: config, ciContext: ciContext)
        }.value

        cache.setObject(PagePreprocessResultBox(result), forKey: cacheKey)
        return result
    }

    /// Preprocesses a raw CGImage directly through the 4-stage pipeline
    public func processCGImage(
        _ rawCG: CGImage,
        config: ReflowConfig,
        ciContext: CIContext? = nil
    ) -> PagePreprocessResult {
        let width = rawCG.width
        let height = rawCG.height
        let originalSize = CGSize(width: width, height: height)

        guard config.enablePageEnhancement, width > 50, height > 50 else {
            return PagePreprocessResult(
                processedImage: rawCG,
                originalSize: originalSize,
                deskewAngle: 0,
                cropRect: CGRect(x: 0, y: 0, width: width, height: height),
                enhanceMode: .off
            )
        }

        let context = ciContext ?? self.ciContext

        var currentCG = rawCG
        var currentDeskewAngle: CGFloat = 0.0
        var isPerspectiveCorrected = false
        var isDeskewed = false
        var finalCropRect = CGRect(x: 0, y: 0, width: currentCG.width, height: currentCG.height)
        var isCropApplied = false

        // ==========================================
        // 0. Manual Quad Perspective & Crop (手动切边与纠偏)
        // If the user has manually defined crop/skew corners, apply precise perspective unwarping
        // and skip automatic border detection/deskewing.
        // ==========================================
        if let manualQuad = config.manualPageQuad, !manualQuad.isFullImage {
            if let corrected = applyPerspectiveCorrection(image: currentCG, quad: manualQuad, context: context) {
                currentCG = corrected
                isPerspectiveCorrected = true
                isCropApplied = true
                finalCropRect = CGRect(x: 0, y: 0, width: corrected.width, height: corrected.height)
            }
        } else {
            // ==========================================
            // 1. Perspective Stretch & Quad Unwarping (四角拉伸透视纠正)
            // Only applicable to camera photos of paper documents (isImageDocument == true)
            // ==========================================
            if config.autoPerspectiveCorrection && config.isImageDocument {
                if let unwarped = detectAndCorrectPerspective(image: currentCG, context: context) {
                    currentCG = unwarped
                    isPerspectiveCorrected = true
                }
            }

            // ==========================================
            // 2. Automatic Deskew & Tilt Correction (文本行旋转摆正)
            // ==========================================
            if config.autoDeskew && config.isImageDocument && !isPerspectiveCorrected {
                let angle = detectDeskewAngle(image: currentCG)
                if abs(angle) >= 0.25 {
                    currentDeskewAngle = angle
                    if let rotated = rotateImage(currentCG, byDegrees: -angle, context: context) {
                        currentCG = rotated
                        isDeskewed = true
                    }
                }
            }

            // ==========================================
            // 3. Black Border Removal & Content Cropping (智能切除黑边与杂色)
            // ==========================================
            if config.autoCropBlackBorders && config.isImageDocument {
                let detectedCrop = detectCleanContentBounds(image: currentCG)
                if detectedCrop.width < CGFloat(currentCG.width - 10) || detectedCrop.height < CGFloat(currentCG.height - 10) {
                    if let cropped = currentCG.cropping(to: detectedCrop) {
                        currentCG = cropped
                        finalCropRect = detectedCrop
                        isCropApplied = true
                    }
                }
            }
        }

        // ==========================================
        // 3b. Staples, Punch Holes & Margin Frame Cleaning (装订钉痕迹/打孔痕/黑边擦除)
        // ==========================================
        var isStaplesRemoved = false
        if config.autoRemoveStaplesAndPunchHoles {
            let (cleanedImage, removedCount) = removeStaplesAndMarginArtifacts(image: currentCG)
            if removedCount > 0 {
                currentCG = cleanedImage
                isStaplesRemoved = true
            }
        }

        // ==========================================
        // 4. True Document Scan Transformation (核心扫描文稿引擎)
        // ==========================================
        let curW = currentCG.width
        let curH = currentCG.height
        let ciImage = CIImage(cgImage: currentCG)

        let (enhancedCI, isBleached, isSharpened) = applyDocumentScanFilter(
            ciImage,
            mode: config.scanEnhanceMode,
            bleachLevel: config.backgroundBleachLevel,
            sharpening: config.pageSharpening,
            width: curW,
            height: curH
        )

        let finalCG = context.createCGImage(enhancedCI, from: CGRect(x: 0, y: 0, width: curW, height: curH)) ?? currentCG

        return PagePreprocessResult(
            processedImage: finalCG,
            originalSize: originalSize,
            deskewAngle: currentDeskewAngle,
            cropRect: finalCropRect,
            isPerspectiveCorrected: isPerspectiveCorrected,
            isDeskewed: isDeskewed,
            isCropApplied: isCropApplied,
            isStaplesRemoved: isStaplesRemoved,
            isBleached: isBleached,
            isSharpened: isSharpened,
            enhanceMode: config.scanEnhanceMode
        )
    }

    // MARK: - Sub-Algorithms

    /// Applies manual or detected quadrilateral perspective correction unwarping
    public func applyPerspectiveCorrection(
        image: CGImage,
        quad: ManualCropQuad,
        context: CIContext? = nil
    ) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 10, height > 10 else { return nil }

        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }

        let vectors = quad.ciVectors(imageWidth: width, imageHeight: height)
        filter.setValue(ciImage, forKey: "inputImage")
        filter.setValue(vectors.topLeft, forKey: "inputTopLeft")
        filter.setValue(vectors.topRight, forKey: "inputTopRight")
        filter.setValue(vectors.bottomLeft, forKey: "inputBottomLeft")
        filter.setValue(vectors.bottomRight, forKey: "inputBottomRight")

        guard let outputCI = filter.outputImage else { return nil }
        let ctx = context ?? self.ciContext
        return ctx.createCGImage(outputCI, from: outputCI.extent)
    }

    /// Detects candidate document quadrilateral via Vision for auto-initialization or smart snap
    public func detectDocumentQuad(image: CGImage) -> ManualCropQuad? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 100, height > 100 else { return nil }

        let req = VNDetectRectanglesRequest()
        req.minimumConfidence = 0.50
        req.minimumAspectRatio = 0.20
        req.maximumAspectRatio = 1.0
        req.minimumSize = 0.30
        req.maximumObservations = 1

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([req])
        } catch {
            return nil
        }

        guard let obs = req.results?.first else { return nil }
        return ManualCropQuad.fromVision(
            topLeft: obs.topLeft,
            topRight: obs.topRight,
            bottomRight: obs.bottomRight,
            bottomLeft: obs.bottomLeft
        )
    }

    /// Detects document quadrilateral via Vision and corrects perspective distortion
    private func detectAndCorrectPerspective(image: CGImage, context: CIContext) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 200, height > 200 else { return nil }

        // Elongated images (aspect ratio > 1.80 or < 0.55) are long screenshots, scrolled captures,
        // or multi-column tall banners, NOT single-page paper photos on a table.
        // Never apply perspective distortion warping to long images!
        let aspect = max(width, height) / max(1.0, min(width, height))
        if aspect > 1.80 {
            return nil
        }

        let req = VNDetectRectanglesRequest()
        req.minimumConfidence = 0.70
        req.minimumAspectRatio = 0.40
        req.maximumAspectRatio = 1.0
        req.minimumSize = 0.50 // Document must cover at least 50% of the camera frame
        req.maximumObservations = 1

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([req])
        } catch {
            return nil
        }

        guard let obs = req.results?.first else { return nil }

        let tl = obs.topLeft
        let tr = obs.topRight
        let bl = obs.bottomLeft
        let br = obs.bottomRight

        // Calculate approximate quadrilateral area in normalized coordinates
        let quadArea = 0.5 * abs((bl.x * br.y - br.x * bl.y) + (br.x * tr.y - tr.x * br.y) + (tr.x * tl.y - tl.x * tr.y) + (tl.x * bl.y - bl.x * tl.y))
        guard quadArea >= 0.55 else {
            // The detected rectangle is only an internal box/table inside the page, not the page perimeter
            return nil
        }

        // If the rectangle is already essentially flat and fills the image, skip unwarping
        let isAlreadyFlat = (tl.x < 0.04 && tl.y > 0.96) &&
                            (tr.x > 0.96 && tr.y > 0.96) &&
                            (bl.x < 0.04 && bl.y < 0.04) &&
                            (br.x > 0.96 && br.y < 0.04)
        if isAlreadyFlat {
            return nil
        }

        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: "inputImage")
        filter.setValue(CIVector(x: tl.x * width, y: tl.y * height), forKey: "inputTopLeft")
        filter.setValue(CIVector(x: tr.x * width, y: tr.y * height), forKey: "inputTopRight")
        filter.setValue(CIVector(x: bl.x * width, y: bl.y * height), forKey: "inputBottomLeft")
        filter.setValue(CIVector(x: br.x * width, y: br.y * height), forKey: "inputBottomRight")

        guard let outputCI = filter.outputImage else { return nil }
        return context.createCGImage(outputCI, from: outputCI.extent)
    }

    /// Transforms the input CIImage into a true scanned document
    private func applyDocumentScanFilter(
        _ inputCI: CIImage,
        mode: ScanEnhanceMode,
        bleachLevel: BleachLevel,
        sharpening: Double,
        width: Int,
        height: Int
    ) -> (CIImage, Bool, Bool) {
        guard mode != .off else { return (inputCI, false, false) }

        var currentCI = inputCI
        var isBleached = false
        var isSharpened = false

        // Adaptive morphology radius based on image size (~0.6% of image width)
        let morphRadius = CGFloat(max(12.0, min(28.0, Double(width) * 0.0065)))

        switch mode {
        case .cleanBW:
            // 1. Illumination background extraction & division (eliminates shadows, creases, yellowed paper)
            if let divided = applyIlluminationDivision(currentCI, radius: morphRadius) {
                currentCI = divided
                isBleached = true
            }

            // 2. Grayscale desaturation & High Document Contrast
            if let grayFilter = CIFilter(name: "CIColorControls") {
                grayFilter.setValue(currentCI, forKey: kCIInputImageKey)
                grayFilter.setValue(0.0, forKey: kCIInputSaturationKey)
                let contrastVal: Float = bleachLevel == .gentle ? 1.95 : 2.40
                let brightnessVal: Float = bleachLevel == .gentle ? 0.08 : 0.12
                grayFilter.setValue(contrastVal, forKey: kCIInputContrastKey)
                grayFilter.setValue(brightnessVal, forKey: kCIInputBrightnessKey)
                if let out = grayFilter.outputImage {
                    currentCI = out
                }
            }

            // 3. Crisp luminance edge sharpening
            let sharpVal = Float(max(0.6, sharpening * 1.5))
            if let sharpFilter = CIFilter(name: "CISharpenLuminance") {
                sharpFilter.setValue(currentCI, forKey: kCIInputImageKey)
                sharpFilter.setValue(sharpVal, forKey: kCIInputSharpnessKey)
                if let out = sharpFilter.outputImage {
                    currentCI = out
                    isSharpened = true
                }
            }

        case .magicColor:
            // 1. Illumination background extraction & division (keeps RGB channels normalized)
            if let divided = applyIlluminationDivision(currentCI, radius: morphRadius) {
                currentCI = divided
                isBleached = true
            }

            // 2. Contrast & brightness with vibrant saturation boost for colored stamps/figures
            if let colorCtrl = CIFilter(name: "CIColorControls") {
                colorCtrl.setValue(currentCI, forKey: kCIInputImageKey)
                let contrastVal: Float = bleachLevel == .gentle ? 1.35 : 1.55
                let brightnessVal: Float = bleachLevel == .gentle ? 0.05 : 0.08
                colorCtrl.setValue(contrastVal, forKey: kCIInputContrastKey)
                colorCtrl.setValue(brightnessVal, forKey: kCIInputBrightnessKey)
                colorCtrl.setValue(1.15, forKey: kCIInputSaturationKey)
                if let out = colorCtrl.outputImage {
                    currentCI = out
                }
            }

            // 3. Sharpening
            if sharpening > 0.05 {
                let sharpVal = Float(sharpening * 1.3)
                if let sharpFilter = CIFilter(name: "CISharpenLuminance") {
                    sharpFilter.setValue(currentCI, forKey: kCIInputImageKey)
                    sharpFilter.setValue(sharpVal, forKey: kCIInputSharpnessKey)
                    if let out = sharpFilter.outputImage {
                        currentCI = out
                        isSharpened = true
                    }
                }
            }

        case .enhancedGray:
            // 1. Illumination division
            if let divided = applyIlluminationDivision(currentCI, radius: morphRadius) {
                currentCI = divided
                isBleached = true
            }

            // 2. Grayscale with moderate contrast
            if let grayFilter = CIFilter(name: "CIColorControls") {
                grayFilter.setValue(currentCI, forKey: kCIInputImageKey)
                grayFilter.setValue(0.0, forKey: kCIInputSaturationKey)
                let contrastVal: Float = bleachLevel == .gentle ? 1.45 : 1.65
                let brightnessVal: Float = bleachLevel == .gentle ? 0.05 : 0.08
                grayFilter.setValue(contrastVal, forKey: kCIInputContrastKey)
                grayFilter.setValue(brightnessVal, forKey: kCIInputBrightnessKey)
                if let out = grayFilter.outputImage {
                    currentCI = out
                }
            }

            if sharpening > 0.05 {
                if let sharpFilter = CIFilter(name: "CISharpenLuminance") {
                    sharpFilter.setValue(currentCI, forKey: kCIInputImageKey)
                    sharpFilter.setValue(Float(sharpening * 1.2), forKey: kCIInputSharpnessKey)
                    if let out = sharpFilter.outputImage {
                        currentCI = out
                        isSharpened = true
                    }
                }
            }

        case .documentFilter:
            if let docFilter = CIFilter(name: "CIDocumentEnhancer") {
                docFilter.setValue(currentCI, forKey: kCIInputImageKey)
                docFilter.setValue(2.0, forKey: "inputAmount")
                if let out = docFilter.outputImage {
                    currentCI = out
                    isBleached = true
                }
            }
            if sharpening > 0.05 {
                if let sharpFilter = CIFilter(name: "CISharpenLuminance") {
                    sharpFilter.setValue(currentCI, forKey: kCIInputImageKey)
                    sharpFilter.setValue(Float(sharpening), forKey: kCIInputSharpnessKey)
                    if let out = sharpFilter.outputImage {
                        currentCI = out
                        isSharpened = true
                    }
                }
            }

        case .gentle:
            if let colorFilter = CIFilter(name: "CIColorControls") {
                colorFilter.setValue(currentCI, forKey: kCIInputImageKey)
                colorFilter.setValue(1.30, forKey: kCIInputContrastKey)
                colorFilter.setValue(0.06, forKey: kCIInputBrightnessKey)
                if let out = colorFilter.outputImage {
                    currentCI = out
                    isBleached = true
                }
            }
            if sharpening > 0.05 {
                if let sharpFilter = CIFilter(name: "CISharpenLuminance") {
                    sharpFilter.setValue(currentCI, forKey: kCIInputImageKey)
                    sharpFilter.setValue(Float(sharpening), forKey: kCIInputSharpnessKey)
                    if let out = sharpFilter.outputImage {
                        currentCI = out
                        isSharpened = true
                    }
                }
            }

        case .off:
            break
        }

        return (currentCI, isBleached, isSharpened)
    }

    /// Extracts low-frequency background illumination via GPU morphology and divides input
    private func applyIlluminationDivision(_ inputCI: CIImage, radius: CGFloat) -> CIImage? {
        guard let maxFilter = CIFilter(name: "CIMorphologyMaximum"),
              let blurFilter = CIFilter(name: "CIBoxBlur"),
              let divFilter = CIFilter(name: "CIDivideBlendMode") else {
            return nil
        }

        maxFilter.setValue(inputCI, forKey: "inputImage")
        maxFilter.setValue(radius, forKey: "inputRadius")
        guard let maxOut = maxFilter.outputImage else { return nil }

        blurFilter.setValue(maxOut, forKey: "inputImage")
        blurFilter.setValue(radius * 0.65, forKey: "inputRadius")
        guard let bgOut = blurFilter.outputImage else { return nil }

        divFilter.setValue(bgOut, forKey: "inputImage")
        divFilter.setValue(inputCI, forKey: "inputBackgroundImage")
        return divFilter.outputImage
    }

    /// Detects page skew angle via Vision text line orientation (Fast & Accurate)
    private func detectDeskewAngle(image: CGImage) -> CGFloat {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 100, height > 100 else { return 0.0 }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return 0.0
        }

        guard let observations = request.results, !observations.isEmpty else {
            return 0.0
        }

        var angles: [Double] = []
        for obs in observations {
            // Sample lines that span at least 10% page width to ensure reliable angle baseline
            if obs.boundingBox.width >= 0.10 {
                let dx = Double(obs.topRight.x - obs.topLeft.x) * Double(width)
                let dy = Double(obs.topRight.y - obs.topLeft.y) * Double(height)
                let angleDeg = atan2(dy, dx) * 180.0 / .pi
                if abs(angleDeg) <= 12.0 {
                    angles.append(angleDeg)
                }
            }
        }

        guard angles.count >= 3 else { return 0.0 }
        angles.sort()
        let median = angles[angles.count / 2]
        return CGFloat(median)
    }

    /// Rotates CGImage by given degree with white background padding
    private func rotateImage(_ image: CGImage, byDegrees degrees: CGFloat, context: CIContext) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let radians = degrees * .pi / 180.0

        // Create rotation transform centered on the image
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let center = CGPoint(x: w / 2.0, y: h / 2.0)

        var transform = CGAffineTransform(translationX: center.x, y: center.y)
        transform = transform.rotated(by: radians)
        transform = transform.translatedBy(x: -center.x, y: -center.y)

        let rotatedCI = ciImage.transformed(by: transform)

        // Pad background with pure white color
        let whiteBg = CIImage(color: CIColor.white).cropped(to: rotatedCI.extent)
        let composited = rotatedCI.composited(over: whiteBg)

        // Render back to CGImage preserving natural extent
        return context.createCGImage(composited, from: CGRect(x: 0, y: 0, width: w, height: h))
    }

    /// Detects scanner black borders, frame artifacts, and page bounds
    private func detectCleanContentBounds(image: CGImage) -> CGRect {
        let width = image.width
        let height = image.height
        guard width > 100, height > 100 else {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }

        // Extract grayscale buffer to inspect outer perimeter
        guard let pixelBuffer = PixelBuffer(cgImage: image) else {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }

        let isElongated = (Double(height) / Double(max(1, width))) > 1.80
        let maxCropX = Int(Double(width) * 0.25)
        let maxCropY = isElongated ? min(120, Int(Double(height) * 0.025)) : Int(Double(height) * 0.25)

        // Dark threshold for scanner black borders & desk background (luminance < 100 out of 255)
        let darkBorderThreshold: UInt8 = 100

        var top = 0
        var bottom = height - 1
        var left = 0
        var right = width - 1

        let stepX = max(1, width / 60)
        let sampleCountX = width / stepX
        let stepY = max(1, height / 60)
        let sampleCountY = height / stepY

        // Top black/desk border check
        while top < maxCropY {
            var darkCount = 0
            for x in stride(from: 0, to: width, by: stepX) {
                if pixelBuffer.pixel(atX: x, y: top) < darkBorderThreshold {
                    darkCount += 1
                }
            }
            if Double(darkCount) / Double(max(1, sampleCountX)) >= 0.28 {
                top += 1
            } else {
                break
            }
        }

        // Bottom black/desk border check
        while bottom > (height - 1 - maxCropY) {
            var darkCount = 0
            for x in stride(from: 0, to: width, by: stepX) {
                if pixelBuffer.pixel(atX: x, y: bottom) < darkBorderThreshold {
                    darkCount += 1
                }
            }
            if Double(darkCount) / Double(max(1, sampleCountX)) >= 0.28 {
                bottom -= 1
            } else {
                break
            }
        }

        // Left black/desk border check
        while left < maxCropX {
            var darkCount = 0
            for y in stride(from: top, to: bottom, by: stepY) {
                if pixelBuffer.pixel(atX: left, y: y) < darkBorderThreshold {
                    darkCount += 1
                }
            }
            if Double(darkCount) / Double(max(1, sampleCountY)) >= 0.28 {
                left += 1
            } else {
                break
            }
        }

        // Right black/desk border check
        while right > (width - 1 - maxCropX) {
            var darkCount = 0
            for y in stride(from: top, to: bottom, by: stepY) {
                if pixelBuffer.pixel(atX: right, y: y) < darkBorderThreshold {
                    darkCount += 1
                }
            }
            if Double(darkCount) / Double(max(1, sampleCountY)) >= 0.28 {
                right -= 1
            } else {
                break
            }
        }

        // Add 4px breathing safety margin
        let pad = 4
        let finalLeft = max(0, left > 0 ? left + pad : 0)
        let finalTop = max(0, top > 0 ? top + pad : 0)
        let finalRight = min(width, right < width - 1 ? right - pad : width)
        let finalBottom = min(height, bottom < height - 1 ? bottom - pad : height)

        guard finalRight > finalLeft + 50, finalBottom > finalTop + 50 else {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }

        return CGRect(
            x: finalLeft,
            y: finalTop,
            width: finalRight - finalLeft,
            height: finalBottom - finalTop
        )
    }

    /// Method A: Content Boundary Detection & Four-Margin Clearing (版心检测与四边缘强制清空)
    /// Preserves the standard document page aspect ratio & dimensions, establishes the true
    /// core content boundary (text, tables, headers, footers), and floods all four outer
    /// perimeter margins outside the safe breathing padding with pure white (#FFFFFF),
    /// completely and cleanly eliminating scanner black edges, staples, punch holes, and shadow lines.
    private func removeStaplesAndMarginArtifacts(image: CGImage) -> (CGImage, Int) {
        let width = image.width
        let height = image.height
        guard width > 120, height > 120 else { return (image, 0) }

        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 255, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (image, 0)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 1. Density projection profiling to establish text & content bounds
        let binSize = 8
        let numBinsX = (width + binSize - 1) / binSize
        let numBinsY = (height + binSize - 1) / binSize
        var binDarkX = [Int](repeating: 0, count: numBinsX)
        var binDarkY = [Int](repeating: 0, count: numBinsY)

        for y in stride(from: 0, to: height, by: 2) {
            let by = y / binSize
            for x in stride(from: 0, to: width, by: 2) {
                let offset = y * bytesPerRow + x * 4
                let r = Int(buffer[offset]), g = Int(buffer[offset+1]), b = Int(buffer[offset+2])
                if (r * 299 + g * 587 + b * 114) < 165000 {
                    binDarkX[x / binSize] += 1
                    binDarkY[by] += 1
                }
            }
        }

        // Establish the main body columns (requires sustained density across consecutive bins)
        var coreLeft = 0
        for bx in 0..<numBinsX {
            if binDarkX[bx] > 40 && bx + 2 < numBinsX && binDarkX[bx+1] > 20 && binDarkX[bx+2] > 20 {
                coreLeft = bx * binSize
                break
            }
        }

        var coreRight = width
        for bx in stride(from: numBinsX - 1, through: 0, by: -1) {
            if binDarkX[bx] > 40 && bx - 2 >= 0 && binDarkX[bx-1] > 20 && binDarkX[bx-2] > 20 {
                coreRight = (bx + 1) * binSize
                break
            }
        }

        var coreBottom = 0
        for by in 0..<numBinsY {
            if binDarkY[by] > 30 && by + 2 < numBinsY && binDarkY[by+1] > 20 && binDarkY[by+2] > 20 {
                coreBottom = by * binSize
                break
            }
        }

        var coreTop = height
        for by in stride(from: numBinsY - 1, through: 0, by: -1) {
            if binDarkY[by] > 30 && by - 2 >= 0 && binDarkY[by-1] > 20 && binDarkY[by-2] > 20 {
                coreTop = (by + 1) * binSize
                break
            }
        }

        // 2. Expand vertically to include isolated page numbers or chapter headers
        var finalBottom = coreBottom
        if coreBottom > 0 {
            for by in stride(from: (coreBottom / binSize) - 1, through: 0, by: -1) {
                let byY = by * binSize
                if byY < Int(Double(height) * 0.03) { break }
                var centerDark = 0, sideDark = 0
                for x in stride(from: 0, to: width, by: 4) {
                    let offset = byY * bytesPerRow + x * 4
                    let r = Int(buffer[offset]), g = Int(buffer[offset+1]), b = Int(buffer[offset+2])
                    if (r * 299 + g * 587 + b * 114) < 165000 {
                        if x >= width / 4 && x <= 3 * width / 4 { centerDark += 1 }
                        else { sideDark += 1 }
                    }
                }
                if centerDark >= 2 && sideDark == 0 {
                    finalBottom = byY
                }
            }
        }

        var finalTop = coreTop
        if coreTop < height {
            for by in (coreTop / binSize)..<numBinsY {
                let byY = by * binSize
                if byY > Int(Double(height) * 0.97) { break }
                var centerDark = 0, sideDark = 0
                for x in stride(from: 0, to: width, by: 4) {
                    let offset = byY * bytesPerRow + x * 4
                    let r = Int(buffer[offset]), g = Int(buffer[offset+1]), b = Int(buffer[offset+2])
                    if (r * 299 + g * 587 + b * 114) < 165000 {
                        if x >= width / 4 && x <= 3 * width / 4 { centerDark += 1 }
                        else { sideDark += 1 }
                    }
                }
                if centerDark >= 2 && sideDark == 0 {
                    finalTop = (by + 1) * binSize
                }
            }
        }

        // Safety sanity check: content box must contain reasonable document proportions
        guard coreRight > coreLeft + 80, finalTop > finalBottom + 80 else {
            return (image, 0)
        }

        // 3. Add safety breathing padding (20px) around content box
        let padX = 20
        let padY = 20
        let safeLeft = max(0, coreLeft - padX)
        let safeRight = min(width - 1, coreRight + padX)
        let safeBottom = max(0, finalBottom - padY)
        let safeTop = min(height - 1, finalTop + padY)

        // 4. Method A: Flood all four margin regions outside the safe content box with pure white (#FFFFFF)
        var clearedPixelCount = 0

        // Left margin (0 ..< safeLeft)
        if safeLeft > 0 {
            for y in 0..<height {
                for x in 0..<min(width, safeLeft) {
                    let offset = y * bytesPerRow + x * 4
                    if buffer[offset] != 255 || buffer[offset+1] != 255 || buffer[offset+2] != 255 {
                        clearedPixelCount += 1
                        buffer[offset] = 255
                        buffer[offset+1] = 255
                        buffer[offset+2] = 255
                        buffer[offset+3] = 255
                    }
                }
            }
        }

        // Right margin ((safeRight + 1) ..< width)
        if safeRight + 1 < width {
            for y in 0..<height {
                for x in (safeRight + 1)..<width {
                    let offset = y * bytesPerRow + x * 4
                    if buffer[offset] != 255 || buffer[offset+1] != 255 || buffer[offset+2] != 255 {
                        clearedPixelCount += 1
                        buffer[offset] = 255
                        buffer[offset+1] = 255
                        buffer[offset+2] = 255
                        buffer[offset+3] = 255
                    }
                }
            }
        }

        if safeLeft <= safeRight && safeLeft < width {
            let clampedRight = min(width - 1, safeRight)

            // Bottom margin (0 ..< safeBottom) between safeLeft and safeRight
            if safeBottom > 0 {
                for y in 0..<min(height, safeBottom) {
                    for x in safeLeft...clampedRight {
                        let offset = y * bytesPerRow + x * 4
                        if buffer[offset] != 255 || buffer[offset+1] != 255 || buffer[offset+2] != 255 {
                            clearedPixelCount += 1
                            buffer[offset] = 255
                            buffer[offset+1] = 255
                            buffer[offset+2] = 255
                            buffer[offset+3] = 255
                        }
                    }
                }
            }

            // Top margin ((safeTop + 1) ..< height) between safeLeft and safeRight
            if safeTop + 1 < height {
                for y in (safeTop + 1)..<height {
                    for x in safeLeft...clampedRight {
                        let offset = y * bytesPerRow + x * 4
                        if buffer[offset] != 255 || buffer[offset+1] != 255 || buffer[offset+2] != 255 {
                            clearedPixelCount += 1
                            buffer[offset] = 255
                            buffer[offset+1] = 255
                            buffer[offset+2] = 255
                            buffer[offset+3] = 255
                        }
                    }
                }
            }
        }

        guard clearedPixelCount > 0, let cleanCG = ctx.makeImage() else {
            return (image, 0)
        }
        return (cleanCG, clearedPixelCount)
    }
}
