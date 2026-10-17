import SwiftUI
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Interactive View for Manual Document Cropping and Perspective De-skewing:
/// - Drag 4 corners with live magnifying loupe
/// - Drag 4 edges for parallel margin trimming
/// - Smart document edge auto-detection
/// - Inverted dark mask showing exact crop area
/// - Rule-of-thirds grid for baseline alignment check
/// - Live Before/After deskew preview
public struct ManualCropDeskewView: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var quad: ManualCropQuad
    @State private var dragInitialQuad: ManualCropQuad? = nil
    @State private var rawImage: CGImage? = nil
    @State private var imageRotation: Int = 0
    @State private var activeHandle: CornerHandle? = nil
    @State private var isShowingPreview: Bool = false
    @State private var previewImage: CGImage? = nil
    @State private var isDetecting: Bool = false

    private enum CornerHandle: Hashable {
        case topLeft
        case topRight
        case bottomRight
        case bottomLeft
        case edgeTop
        case edgeRight
        case edgeBottom
        case edgeLeft
    }

    public init(viewModel: PDFReaderViewModel) {
        self.viewModel = viewModel
        let currentQuad = viewModel.manualPageQuads[viewModel.currentPageIndex] ?? .standardInset
        _quad = State(initialValue: currentQuad)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main Interactive Canvas
                GeometryReader { geo in
                    let canvasSize = geo.size
                    if let cgImg = rawImage {
                        let fittedRect = calculateAspectFitRect(
                            imageSize: CGSize(width: cgImg.width, height: cgImg.height),
                            boundingSize: canvasSize
                        )

                        ZStack {
                            Color(white: 0.12).ignoresSafeArea()

                            if isShowingPreview, let prev = previewImage {
                                // Live Deskew Preview Mode
                                let prevRect = calculateAspectFitRect(
                                    imageSize: CGSize(width: prev.width, height: prev.height),
                                    boundingSize: canvasSize
                                )
                                Image(decorative: prev, scale: 1.0)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: prevRect.width, height: prevRect.height)
                                    .shadow(color: .black.opacity(0.35), radius: 10)
                                    .overlay(
                                        Text("已纠偏预览")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color.accentColor))
                                            .padding(10),
                                        alignment: .topLeading
                                    )
                            } else {
                                // 1. Base Raw Document Image
                                Image(decorative: cgImg, scale: 1.0)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: fittedRect.width, height: fittedRect.height)
                                    .position(x: fittedRect.midX, y: fittedRect.midY)

                                // 2. Darkened Semi-Transparent Mask Outside the Quad
                                QuadMaskOverlay(
                                    quad: quad,
                                    bounds: fittedRect
                                )
                                .allowsHitTesting(false)

                                // 3. 3x3 Text Baseline Alignment Grid Lines
                                QuadGridLines(
                                    quad: quad,
                                    bounds: fittedRect
                                )
                                .allowsHitTesting(false)

                                // 4. Quad Outline Stroke
                                QuadOutline(
                                    quad: quad,
                                    bounds: fittedRect
                                )
                                .allowsHitTesting(false)

                                // 5. Interactive Edge Handles
                                edgeHandlesView(bounds: fittedRect)

                                // 6. Interactive Corner Handles
                                cornerHandlesView(bounds: fittedRect)

                                // 7. Floating Magnifying Loupe while dragging
                                if let handle = activeHandle, case .topLeft = handle {
                                    magnifierLoupe(for: quad.topLeft, in: fittedRect, title: "左上角")
                                } else if let handle = activeHandle, case .topRight = handle {
                                    magnifierLoupe(for: quad.topRight, in: fittedRect, title: "右上角")
                                } else if let handle = activeHandle, case .bottomRight = handle {
                                    magnifierLoupe(for: quad.bottomRight, in: fittedRect, title: "右下角")
                                } else if let handle = activeHandle, case .bottomLeft = handle {
                                    magnifierLoupe(for: quad.bottomLeft, in: fittedRect, title: "左下角")
                                }
                            }
                        }
                    } else {
                        ZStack {
                            Color(white: 0.12).ignoresSafeArea()
                            ProgressView("正在载入原图...")
                                .foregroundColor(.white)
                        }
                    }
                }

                // Bottom Tool Bar with Smart Actions
                bottomControlBar
            }
            .navigationTitle("手动切边与纠偏")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: applyAndDismiss) {
                        Text("应用并重排")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onAppear {
                guard viewModel.config.isImageDocument else {
                    dismiss()
                    return
                }
                loadRawImage()
            }
        }
    }

    // MARK: - Interactive Handles Views (Buttery Smooth Linear Drag Tracking)

    @ViewBuilder
    private func cornerHandlesView(bounds: CGRect) -> some View {
        let tlPoint = toViewPoint(quad.topLeft, bounds: bounds)
        let trPoint = toViewPoint(quad.topRight, bounds: bounds)
        let brPoint = toViewPoint(quad.bottomRight, bounds: bounds)
        let blPoint = toViewPoint(quad.bottomLeft, bounds: bounds)

        cornerHandleItem(point: tlPoint, handle: .topLeft, bounds: bounds)
        cornerHandleItem(point: trPoint, handle: .topRight, bounds: bounds)
        cornerHandleItem(point: brPoint, handle: .bottomRight, bounds: bounds)
        cornerHandleItem(point: blPoint, handle: .bottomLeft, bounds: bounds)
    }

    @ViewBuilder
    private func cornerHandleItem(
        point: CGPoint,
        handle: CornerHandle,
        bounds: CGRect
    ) -> some View {
        let isFocused = activeHandle == handle
        ZStack {
            // Expanded hit box (48x48 pt) with contentShape so finger never slips
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 48, height: 48)
                .contentShape(Circle())

            // Outer Glow Ring
            Circle()
                .stroke(Color.white, lineWidth: isFocused ? 3 : 2)
                .background(Circle().fill(Color.accentColor))
                .frame(width: isFocused ? 26 : 20, height: isFocused ? 26 : 20)
                .shadow(color: .black.opacity(0.4), radius: 4)

            // Inner Center Dot
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
        }
        .position(point)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if activeHandle != handle {
                        activeHandle = handle
                        dragInitialQuad = quad
                        #if os(iOS)
                        PlatformHaptics.selection()
                        #endif
                    }
                    guard let initial = dragInitialQuad else { return }
                    let normDeltaX = value.translation.width / bounds.width
                    let normDeltaY = value.translation.height / bounds.height

                    switch handle {
                    case .topLeft:
                        let newX = min(max(0.0, initial.topLeft.x + normDeltaX), quad.topRight.x - 0.05)
                        let newY = min(max(0.0, initial.topLeft.y + normDeltaY), quad.bottomLeft.y - 0.05)
                        quad.topLeft = CGPoint(x: newX, y: newY)

                    case .topRight:
                        let newX = max(min(1.0, initial.topRight.x + normDeltaX), quad.topLeft.x + 0.05)
                        let newY = min(max(0.0, initial.topRight.y + normDeltaY), quad.bottomRight.y - 0.05)
                        quad.topRight = CGPoint(x: newX, y: newY)

                    case .bottomRight:
                        let newX = max(min(1.0, initial.bottomRight.x + normDeltaX), quad.bottomLeft.x + 0.05)
                        let newY = max(min(1.0, initial.bottomRight.y + normDeltaY), quad.topRight.y + 0.05)
                        quad.bottomRight = CGPoint(x: newX, y: newY)

                    case .bottomLeft:
                        let newX = min(max(0.0, initial.bottomLeft.x + normDeltaX), quad.bottomRight.x - 0.05)
                        let newY = max(min(1.0, initial.bottomLeft.y + normDeltaY), quad.topLeft.y + 0.05)
                        quad.bottomLeft = CGPoint(x: newX, y: newY)

                    default:
                        break
                    }
                }
                .onEnded { _ in
                    activeHandle = nil
                    dragInitialQuad = nil
                    updatePreviewIfActive()
                }
        )
    }

    @ViewBuilder
    private func edgeHandlesView(bounds: CGRect) -> some View {
        let tlPoint = toViewPoint(quad.topLeft, bounds: bounds)
        let trPoint = toViewPoint(quad.topRight, bounds: bounds)
        let brPoint = toViewPoint(quad.bottomRight, bounds: bounds)
        let blPoint = toViewPoint(quad.bottomLeft, bounds: bounds)

        // Top Edge Midpoint
        let topMid = CGPoint(x: (tlPoint.x + trPoint.x) * 0.5, y: (tlPoint.y + trPoint.y) * 0.5)
        edgePillHandle(point: topMid, handle: .edgeTop, isVertical: false, bounds: bounds)

        // Bottom Edge Midpoint
        let botMid = CGPoint(x: (blPoint.x + brPoint.x) * 0.5, y: (blPoint.y + brPoint.y) * 0.5)
        edgePillHandle(point: botMid, handle: .edgeBottom, isVertical: false, bounds: bounds)

        // Left Edge Midpoint
        let leftMid = CGPoint(x: (tlPoint.x + blPoint.x) * 0.5, y: (tlPoint.y + blPoint.y) * 0.5)
        edgePillHandle(point: leftMid, handle: .edgeLeft, isVertical: true, bounds: bounds)

        // Right Edge Midpoint
        let rightMid = CGPoint(x: (trPoint.x + brPoint.x) * 0.5, y: (trPoint.y + brPoint.y) * 0.5)
        edgePillHandle(point: rightMid, handle: .edgeRight, isVertical: true, bounds: bounds)
    }

    @ViewBuilder
    private func edgePillHandle(
        point: CGPoint,
        handle: CornerHandle,
        isVertical: Bool,
        bounds: CGRect
    ) -> some View {
        let isFocused = activeHandle == handle
        ZStack {
            // Expanded hit box (48x36 pt) with contentShape for easy finger grabbing
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.001))
                .frame(width: isVertical ? 36 : 48, height: isVertical ? 48 : 36)
                .contentShape(Rectangle())

            Capsule()
                .fill(isFocused ? Color.accentColor : Color.white.opacity(0.92))
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1.5))
                .frame(width: isVertical ? 6 : 26, height: isVertical ? 26 : 6)
                .shadow(color: .black.opacity(0.35), radius: 3)
        }
        .position(point)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if activeHandle != handle {
                        activeHandle = handle
                        dragInitialQuad = quad
                        #if os(iOS)
                        PlatformHaptics.selection()
                        #endif
                    }
                    guard let initial = dragInitialQuad else { return }

                    switch handle {
                    case .edgeTop:
                        let normDeltaY = value.translation.height / bounds.height
                        let maxAllowed = min(quad.bottomLeft.y - 0.08, quad.bottomRight.y - 0.08)
                        let targetY = max(0.0, min(maxAllowed, initial.topLeft.y + normDeltaY))
                        let deltaY = targetY - initial.topLeft.y
                        quad.topLeft.y = initial.topLeft.y + deltaY
                        quad.topRight.y = max(0.0, min(maxAllowed, initial.topRight.y + deltaY))

                    case .edgeBottom:
                        let normDeltaY = value.translation.height / bounds.height
                        let minAllowed = max(quad.topLeft.y + 0.08, quad.topRight.y + 0.08)
                        let targetY = min(1.0, max(minAllowed, initial.bottomLeft.y + normDeltaY))
                        let deltaY = targetY - initial.bottomLeft.y
                        quad.bottomLeft.y = initial.bottomLeft.y + deltaY
                        quad.bottomRight.y = min(1.0, max(minAllowed, initial.bottomRight.y + deltaY))

                    case .edgeLeft:
                        let normDeltaX = value.translation.width / bounds.width
                        let maxAllowed = min(quad.topRight.x - 0.08, quad.bottomRight.x - 0.08)
                        let targetX = max(0.0, min(maxAllowed, initial.topLeft.x + normDeltaX))
                        let deltaX = targetX - initial.topLeft.x
                        quad.topLeft.x = initial.topLeft.x + deltaX
                        quad.bottomLeft.x = max(0.0, min(maxAllowed, initial.bottomLeft.x + deltaX))

                    case .edgeRight:
                        let normDeltaX = value.translation.width / bounds.width
                        let minAllowed = max(quad.topLeft.x + 0.08, quad.bottomLeft.x + 0.08)
                        let targetX = min(1.0, max(minAllowed, initial.topRight.x + normDeltaX))
                        let deltaX = targetX - initial.topRight.x
                        quad.topRight.x = initial.topRight.x + deltaX
                        quad.bottomRight.x = min(1.0, max(minAllowed, initial.bottomRight.x + deltaX))

                    default:
                        break
                    }
                }
                .onEnded { _ in
                    activeHandle = nil
                    dragInitialQuad = nil
                    updatePreviewIfActive()
                }
        )
    }

    // MARK: - Magnifier Loupe Overlay

    @ViewBuilder
    private func magnifierLoupe(for normPoint: CGPoint, in bounds: CGRect, title: String) -> some View {
        let viewPoint = toViewPoint(normPoint, bounds: bounds)
        // Offset loupe above the finger so it's not obscured
        let loupeY = max(60, viewPoint.y - 70)
        let loupeX = min(max(60, viewPoint.x), bounds.width - 60)

        ZStack {
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 80, height: 80)
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.5), radius: 8)

            // Zoomed Crosshair
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(.accentColor)

            VStack {
                Spacer()
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 6)
            }
        }
        .position(x: loupeX, y: loupeY)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Bottom Control Bar

    @ViewBuilder
    private var bottomControlBar: some View {
        HStack(spacing: 8) {
            // 1. Smart AI Rectangle Detection
            Button(action: runSmartDetection) {
                VStack(spacing: 3) {
                    if isDetecting {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16))
                    }
                    Text("智能识别")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(isDetecting)

            // 2. Select Full Image
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    quad = .fullImage
                }
                updatePreviewIfActive()
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16))
                    Text("整页全选")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            // 3. Standard Inset (5% margin)
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    quad = .standardInset
                }
                updatePreviewIfActive()
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "crop")
                        .font(.system(size: 16))
                    Text("边距内缩")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            // 4. Rotate 90°
            Button(action: rotateRawImage) {
                VStack(spacing: 3) {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 16))
                    Text("顺时针90°")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            // 5. Live Preview Deskew Toggle
            if isShowingPreview {
                Button(action: togglePreview) {
                    VStack(spacing: 3) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 16))
                        Text("查看原图")
                            .font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: togglePreview) {
                    VStack(spacing: 3) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 16))
                        Text("预览纠偏")
                            .font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.16))
    }

    // MARK: - Actions & Calculations

    private func loadRawImage() {
        if let raw = viewModel.currentRawPageCGImage() {
            self.rawImage = raw
        }
    }

    private func runSmartDetection() {
        guard let img = rawImage else { return }
        isDetecting = true
        Task {
            let detected = PagePreprocessEngine.shared.detectDocumentQuad(image: img)
            await MainActor.run {
                isDetecting = false
                if let d = detected {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        quad = d
                    }
                    viewModel.showToast(message: "已智能识别页面边界")
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        quad = .standardInset
                    }
                    viewModel.showToast(message: "未检测到显著边界，已应用标准边距")
                }
                updatePreviewIfActive()
            }
        }
    }

    private func rotateRawImage() {
        viewModel.rotateCurrentPage(by: 90)
        loadRawImage()
    }

    private func togglePreview() {
        if isShowingPreview {
            isShowingPreview = false
        } else {
            generatePreview()
            isShowingPreview = true
        }
    }

    private func updatePreviewIfActive() {
        if isShowingPreview {
            generatePreview()
        }
    }

    private func generatePreview() {
        guard let img = rawImage else { return }
        self.previewImage = PagePreprocessEngine.shared.applyPerspectiveCorrection(image: img, quad: quad)
    }

    private func applyAndDismiss() {
        viewModel.applyManualCrop(for: viewModel.currentPageIndex, quad: quad)
        dismiss()
    }

    private func calculateAspectFitRect(imageSize: CGSize, boundingSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let hScale = boundingSize.width / imageSize.width
        let vScale = boundingSize.height / imageSize.height
        let scale = min(hScale, vScale) * 0.94 // 6% padding for handles
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = (boundingSize.width - width) * 0.5
        let y = (boundingSize.height - height) * 0.5
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func toViewPoint(_ norm: CGPoint, bounds: CGRect) -> CGPoint {
        CGPoint(
            x: bounds.origin.x + norm.x * bounds.width,
            y: bounds.origin.y + norm.y * bounds.height
        )
    }

    private func toNormalizedPoint(_ pt: CGPoint, bounds: CGRect) -> CGPoint {
        let x = (pt.x - bounds.origin.x) / bounds.width
        let y = (pt.y - bounds.origin.y) / bounds.height
        return CGPoint(
            x: max(0.0, min(1.0, x)),
            y: max(0.0, min(1.0, y))
        )
    }
}

// MARK: - Shapes & Overlay Helpers

/// Inverted mask that dims the background outside the quadrilateral
private struct QuadMaskOverlay: View {
    let quad: ManualCropQuad
    let bounds: CGRect

    var body: some View {
        Canvas { context, size in
            let fullRect = CGRect(origin: .zero, size: size)
            let fullPath = Path(fullRect)

            let tl = toPt(quad.topLeft)
            let tr = toPt(quad.topRight)
            let br = toPt(quad.bottomRight)
            let bl = toPt(quad.bottomLeft)

            var quadPath = Path()
            quadPath.move(to: tl)
            quadPath.addLine(to: tr)
            quadPath.addLine(to: br)
            quadPath.addLine(to: bl)
            quadPath.closeSubpath()

            // Inverted clipping: fill full canvas then clear the quad interior
            context.fill(fullPath, with: .color(Color.black.opacity(0.55)))
            context.blendMode = .clear
            context.fill(quadPath, with: .color(.black))
        }
        .compositingGroup()
    }

    private func toPt(_ norm: CGPoint) -> CGPoint {
        CGPoint(x: bounds.origin.x + norm.x * bounds.width, y: bounds.origin.y + norm.y * bounds.height)
    }
}

/// Outline path stroke connecting the 4 corners
private struct QuadOutline: View {
    let quad: ManualCropQuad
    let bounds: CGRect

    var body: some View {
        Path { path in
            let tl = toPt(quad.topLeft)
            let tr = toPt(quad.topRight)
            let br = toPt(quad.bottomRight)
            let bl = toPt(quad.bottomLeft)
            path.move(to: tl)
            path.addLine(to: tr)
            path.addLine(to: br)
            path.addLine(to: bl)
            path.closeSubpath()
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
    }

    private func toPt(_ norm: CGPoint) -> CGPoint {
        CGPoint(x: bounds.origin.x + norm.x * bounds.width, y: bounds.origin.y + norm.y * bounds.height)
    }
}

/// 3x3 grid lines inside the quadrilateral for text baseline straightness check
private struct QuadGridLines: View {
    let quad: ManualCropQuad
    let bounds: CGRect

    var body: some View {
        Path { path in
            let tl = toPt(quad.topLeft)
            let tr = toPt(quad.topRight)
            let br = toPt(quad.bottomRight)
            let bl = toPt(quad.bottomLeft)

            // Horizontal grid lines (1/3 and 2/3)
            for frac in [0.333, 0.666] {
                let start = interpolate(p1: tl, p2: bl, fraction: frac)
                let end = interpolate(p1: tr, p2: br, fraction: frac)
                path.move(to: start)
                path.addLine(to: end)
            }

            // Vertical grid lines (1/3 and 2/3)
            for frac in [0.333, 0.666] {
                let start = interpolate(p1: tl, p2: tr, fraction: frac)
                let end = interpolate(p1: bl, p2: br, fraction: frac)
                path.move(to: start)
                path.addLine(to: end)
            }
        }
        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.0, dash: [4, 4]))
    }

    private func toPt(_ norm: CGPoint) -> CGPoint {
        CGPoint(x: bounds.origin.x + norm.x * bounds.width, y: bounds.origin.y + norm.y * bounds.height)
    }

    private func interpolate(p1: CGPoint, p2: CGPoint, fraction: CGFloat) -> CGPoint {
        CGPoint(
            x: p1.x + (p2.x - p1.x) * fraction,
            y: p1.y + (p2.y - p1.y) * fraction
        )
    }
}
