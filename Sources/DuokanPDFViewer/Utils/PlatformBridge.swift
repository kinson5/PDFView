import Foundation
import SwiftUI
import CoreGraphics
import ImageIO
import PDFKit

#if canImport(AppKit)
import AppKit

extension NSImage {
    public var platformCGImage: CGImage? {
        self.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
#elseif canImport(UIKit)
import UIKit

public typealias NSImage = UIImage
public typealias NSColor = UIColor
public typealias NSSize = CGSize

extension UIImage {
    public var platformCGImage: CGImage? {
        self.cgImage
    }

    public convenience init(cgImage: CGImage, size: CGSize) {
        let scale = size.width > 0 ? (CGFloat(cgImage.width) / size.width) : 1.0
        self.init(cgImage: cgImage, scale: max(1.0, scale), orientation: .up)
    }

    public convenience init(size: CGSize) {
        let safeW = max(1.0, size.width)
        let safeH = max(1.0, size.height)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: safeW, height: safeH))
        let img = renderer.image { _ in }
        if let cg = img.cgImage {
            self.init(cgImage: cg)
        } else {
            self.init()
        }
    }
}

extension UIColor {
    public convenience init(calibratedRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    public convenience init(calibratedWhite white: CGFloat, alpha: CGFloat) {
        self.init(white: white, alpha: alpha)
    }

    public static var windowBackgroundColor: UIColor {
        UIColor.systemBackground
    }

    public static var controlBackgroundColor: UIColor {
        UIColor.secondarySystemBackground
    }
}

extension Image {
    public init(nsImage: UIImage) {
        self.init(uiImage: nsImage)
    }
}

extension Color {
    public init(nsColor: UIColor) {
        self.init(uiColor: nsColor)
    }
}
#endif

/// Mobile-optimized haptic feedback utility
public enum UIImpactFeedbackStyle {
    case light
    case medium
    case heavy

    #if os(iOS)
    var nativeStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light: return .light
        case .medium: return .medium
        case .heavy: return .heavy
        }
    }
    #endif
}

public enum PlatformHaptics {
    @MainActor
    public static func impact(_ style: UIImpactFeedbackStyle = .light) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style.nativeStyle)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    @MainActor
    public static func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }

    @MainActor
    public static func notificationSuccess() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }
}

/// Cross-platform clipboard utility
public enum PlatformClipboard {
    public static func copy(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

/// Converts standalone image files (.png, .jpg, .heic, .tiff, .webp) into a standard PDFDocument
/// so they can be viewed in Original mode and reflowed/translated through the exact same engine.
public enum PlatformImageDocumentLoader {
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "webp", "bmp", "gif"
    ]

    public static func isImageFile(url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    public static func createPDFDocument(fromImageURL url: URL) -> PDFDocument? {
        // 1. Coordinate reading via NSFileCoordinator to safely access iCloud ubiquitous files and avoid sandbox locks
        var fileData: Data? = nil
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { safeURL in
            fileData = try? Data(contentsOf: safeURL)
        }
        if fileData == nil {
            fileData = try? Data(contentsOf: url)
        }
        if let data = fileData, let doc = createPDFDocument(fromImageData: data) {
            return doc
        }

        // 2. Direct CGImageSource fallback
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return createPDFDocument(fromImageSource: source)
    }

    public static func createPDFDocument(fromImageData data: Data) -> PDFDocument? {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data), uiImage.size.width > 0, uiImage.size.height > 0 {
            let pageWidth: CGFloat = 595.2
            let aspect = uiImage.size.height / uiImage.size.width
            let pageHeight = max(200.0, pageWidth * aspect)
            let pageBounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

            let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
            let pdfData = renderer.pdfData { context in
                context.beginPage()
                UIColor.white.setFill()
                UIRectFill(pageBounds)
                uiImage.draw(in: pageBounds)
            }
            if let doc = PDFDocument(data: pdfData), doc.pageCount > 0 {
                var attrs = doc.documentAttributes ?? [:]
                attrs[PDFDocumentAttribute(rawValue: "IsImageDocument")] = true
                attrs[PDFDocumentAttribute(rawValue: "SourceFileType")] = "ImageFile"
                doc.documentAttributes = attrs
                return doc
            }
        }
        #endif

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return createPDFDocument(fromImageSource: source)
    }

    private static func createPDFDocument(fromImageSource source: CGImageSource) -> PDFDocument? {
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }

        var addedPages = 0
        let transformOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true
        ]

        for index in 0..<count {
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, transformOptions as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, index, nil)
            guard let validImage = cgImage, validImage.width > 0, validImage.height > 0 else {
                continue
            }

            // Normalize page width to standard A4 points (595.2 pt) while preserving exact aspect ratio
            // so ReflowEngine renders at crisp 200-320 DPI without runaway pixel dimensions
            let pageWidth: CGFloat = 595.2
            let aspect = CGFloat(validImage.height) / CGFloat(validImage.width)
            let pageHeight = max(200.0, pageWidth * aspect)
            var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

            context.beginPage(mediaBox: &mediaBox)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(mediaBox)
            context.interpolationQuality = .high
            context.draw(validImage, in: mediaBox)
            context.endPage()
            addedPages += 1
        }

        context.closePDF()
        guard addedPages > 0 else { return nil }
        guard let doc = PDFDocument(data: pdfData as Data) else { return nil }
        var attrs = doc.documentAttributes ?? [:]
        attrs[PDFDocumentAttribute(rawValue: "IsImageDocument")] = true
        attrs[PDFDocumentAttribute(rawValue: "SourceFileType")] = "ImageFile"
        doc.documentAttributes = attrs
        return doc
    }
}
