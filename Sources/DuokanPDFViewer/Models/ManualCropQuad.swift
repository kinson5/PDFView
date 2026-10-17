import Foundation
import CoreGraphics
import CoreImage

/// Represents an arbitrary 4-point quadrilateral in normalized [0, 1] coordinate space
/// used for manual document cropping and perspective de-skewing.
///
/// In this coordinate system:
/// - (0, 0) is the TOP-LEFT corner of the image
/// - (1, 1) is the BOTTOM-RIGHT corner of the image
/// - Y increases downwards (matching SwiftUI / standard touch gesture coordinates)
public struct ManualCropQuad: Codable, Equatable, Sendable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint

    public init(
        topLeft: CGPoint = CGPoint(x: 0.04, y: 0.04),
        topRight: CGPoint = CGPoint(x: 0.96, y: 0.04),
        bottomRight: CGPoint = CGPoint(x: 0.96, y: 0.96),
        bottomLeft: CGPoint = CGPoint(x: 0.04, y: 0.96)
    ) {
        self.topLeft = Self.clamp(topLeft)
        self.topRight = Self.clamp(topRight)
        self.bottomRight = Self.clamp(bottomRight)
        self.bottomLeft = Self.clamp(bottomLeft)
    }

    /// Full image covering (0,0) to (1,1)
    public static var fullImage: ManualCropQuad {
        ManualCropQuad(
            topLeft: CGPoint(x: 0, y: 0),
            topRight: CGPoint(x: 1, y: 0),
            bottomRight: CGPoint(x: 1, y: 1),
            bottomLeft: CGPoint(x: 0, y: 1)
        )
    }

    /// Standard document margin inset (5% margin)
    public static var standardInset: ManualCropQuad {
        ManualCropQuad(
            topLeft: CGPoint(x: 0.05, y: 0.05),
            topRight: CGPoint(x: 0.95, y: 0.05),
            bottomRight: CGPoint(x: 0.95, y: 0.95),
            bottomLeft: CGPoint(x: 0.05, y: 0.95)
        )
    }

    /// Creates a quad from Vision's VNDetectRectanglesRequest observation
    /// Note: Vision coordinates have Y=0 at the bottom and Y=1 at the top!
    public static func fromVision(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) -> ManualCropQuad {
        ManualCropQuad(
            topLeft: CGPoint(x: topLeft.x, y: 1.0 - topLeft.y),
            topRight: CGPoint(x: topRight.x, y: 1.0 - topRight.y),
            bottomRight: CGPoint(x: bottomRight.x, y: 1.0 - bottomRight.y),
            bottomLeft: CGPoint(x: bottomLeft.x, y: 1.0 - bottomLeft.y)
        )
    }

    /// Converts normalized points to CoreImage CIVector coordinates.
    /// In CoreImage, Y=0 is at the bottom, so CI_Y = (1.0 - UI_Y) * height.
    public func ciVectors(
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> (topLeft: CIVector, topRight: CIVector, bottomLeft: CIVector, bottomRight: CIVector) {
        let ciTL = CIVector(x: topLeft.x * imageWidth, y: (1.0 - topLeft.y) * imageHeight)
        let ciTR = CIVector(x: topRight.x * imageWidth, y: (1.0 - topRight.y) * imageHeight)
        let ciBL = CIVector(x: bottomLeft.x * imageWidth, y: (1.0 - bottomLeft.y) * imageHeight)
        let ciBR = CIVector(x: bottomRight.x * imageWidth, y: (1.0 - bottomRight.y) * imageHeight)
        return (topLeft: ciTL, topRight: ciTR, bottomLeft: ciBL, bottomRight: ciBR)
    }

    /// Returns estimated unwarped output dimensions based on average edge lengths
    public func estimatedOutputSize(sourceWidth: CGFloat, sourceHeight: CGFloat) -> CGSize {
        let topLength = hypot((topRight.x - topLeft.x) * sourceWidth, (topRight.y - topLeft.y) * sourceHeight)
        let bottomLength = hypot((bottomRight.x - bottomLeft.x) * sourceWidth, (bottomRight.y - bottomLeft.y) * sourceHeight)
        let leftLength = hypot((bottomLeft.x - topLeft.x) * sourceWidth, (bottomLeft.y - topLeft.y) * sourceHeight)
        let rightLength = hypot((bottomRight.x - topRight.x) * sourceWidth, (bottomRight.y - topRight.y) * sourceHeight)

        let avgWidth = max(50.0, (topLength + bottomLength) * 0.5)
        let avgHeight = max(50.0, (leftLength + rightLength) * 0.5)
        return CGSize(width: round(avgWidth), height: round(avgHeight))
    }

    /// Approximate quadrilateral area in normalized [0, 1] space
    public var normalizedArea: CGFloat {
        0.5 * abs(
            (bottomLeft.x * bottomRight.y - bottomRight.x * bottomLeft.y) +
            (bottomRight.x * topRight.y - topRight.x * bottomRight.y) +
            (topRight.x * topLeft.y - topLeft.x * topRight.y) +
            (topLeft.x * bottomLeft.y - bottomLeft.x * topLeft.y)
        )
    }

    /// True if quad is essentially the whole uncropped image
    public var isFullImage: Bool {
        topLeft.x <= 0.01 && topLeft.y <= 0.01 &&
        topRight.x >= 0.99 && topRight.y <= 0.01 &&
        bottomRight.x >= 0.99 && bottomRight.y >= 0.99 &&
        bottomLeft.x <= 0.01 && bottomLeft.y >= 0.99
    }

    private static func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0.0, min(1.0, p.x)),
            y: max(0.0, min(1.0, p.y))
        )
    }
}
