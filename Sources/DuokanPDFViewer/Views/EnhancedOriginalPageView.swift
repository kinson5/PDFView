import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct EnhancedOriginalPageView: View {
    @ObservedObject var viewModel: PDFReaderViewModel

    public init(viewModel: PDFReaderViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let theme = viewModel.config.readingTheme
        let bgColor = Color(nsColor: theme.backgroundColor)
        let textColor = Color(nsColor: theme.textColor)

        ZStack {
            bgColor.ignoresSafeArea()

            if viewModel.isEnhancingPage && viewModel.enhancedPageImage == nil {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在智能优化页面 (纠偏 / 切边 / 漂白 / 锐化)...")
                        .font(.headline)
                        .foregroundColor(textColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = viewModel.enhancedPageImage {
                GeometryReader { geo in
                    let isZoomed = viewModel.zoomScale > 1.05
                    ScrollView(isZoomed ? [.horizontal, .vertical] : .vertical, showsIndicators: isZoomed) {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)

                                Image(nsImage: image)
                                    .resizable()
                                    .interpolation(.high)
                                    .antialiased(true)
                                    .aspectRatio(contentMode: .fit)
                                    .scaleEffect(viewModel.zoomScale)
                                    .frame(
                                        maxWidth: isZoomed ? nil : max(geo.size.width - 32, 200),
                                        maxHeight: max(geo.size.height - 32, 200)
                                    )
                                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)

                                Spacer(minLength: 0)
                            }
                        }
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                        .padding(.vertical, 16)
                    }
                }
                .overlay(alignment: .bottom) {
                    bottomFloatingBadge(textColor: textColor)
                        .padding(.bottom, 16)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("无法加载页面优化图像")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("重试优化") {
                        viewModel.refreshEnhancedOriginalPage()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel.enhancedPageImage == nil {
                viewModel.refreshEnhancedOriginalPage()
            }
        }
    }

    @ViewBuilder
    private func bottomFloatingBadge(textColor: Color) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                    .font(.caption.bold())
                Text("画质优化生效中")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
            }

            if let prep = viewModel.currentPreprocessResult {
                Divider().frame(height: 12)

                if prep.isPerspectiveCorrected {
                    Text("透视拉伸纠正")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if prep.isDeskewed {
                    Text(String(format: "倾斜纠正 %.1f°", -prep.deskewAngle))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if prep.isCropApplied {
                    Text("已去黑边")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if prep.isStaplesRemoved {
                    Text("已除钉痕")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(prep.enhanceMode.shortLabel)
                    .font(.caption2.bold())
                    .foregroundColor(.accentColor)
                if prep.isSharpened {
                    Text("锐化")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.currentPageRotation != 0 {
                Divider().frame(height: 12)
                Text("旋转 \(viewModel.currentPageRotation)°")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider().frame(height: 12)

            Button(action: {
                viewModel.rotateCurrentPage(by: 90)
            }) {
                HStack(spacing: 2) {
                    Image(systemName: "rotate.right")
                        .font(.caption2)
                    Text("旋转")
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("顺时针旋转90°")

            Divider().frame(height: 12)

            Button(action: {
                viewModel.config.originalViewEnhanced = false
                viewModel.saveCurrentBookPreference()
            }) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption2)
                    Text("看原版")
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 5, x: 0, y: 2)
        )
    }
}
