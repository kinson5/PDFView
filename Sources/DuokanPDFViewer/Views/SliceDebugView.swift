import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct SliceDebugView: View {
    @ObservedObject var viewModel: PDFReaderViewModel

    public init(viewModel: PDFReaderViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if let result = viewModel.currentReflowResult {
            #if os(macOS)
            HSplitView {
                debugCanvas(result: result)
                debugSidebar(result: result)
            }
            #else
            VStack(spacing: 0) {
                debugCanvas(result: result)
                Divider()
                debugSidebar(result: result)
                    .frame(maxHeight: 260)
            }
            #endif
        } else {
            VStack {
                Text("暂无诊断数据，请先加载文档并重排")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func debugCanvas(result: PageReflowResult) -> some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: result.originalImage)
                    .interpolation(.high)

                // 1. Content bounds (Green box)
                Path { path in
                    path.addRect(result.contentBounds)
                }
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))

                // 2. Macro Structural Zones (Dashed colored boxes with zone badges)
                ForEach(result.zones) { zone in
                    let zoneColor = Color(nsColor: zone.type.badgeColor)
                    Path { path in
                        path.addRect(zone.rect)
                    }
                    .stroke(zoneColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))

                    // Zone label pill
                    Text(zone.type.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(zoneColor.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(3)
                        .offset(x: zone.rect.minX + 4, y: zone.rect.minY + 4)
                }

                // 3. Column bounds (Blue box)
                ForEach(result.columns.indices, id: \.self) { idx in
                    let col = result.columns[idx]
                    Path { path in
                        path.addRect(col.rect)
                    }
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }

                // 4. Slice bounds (Orange for lines, Purple for figures)
                ForEach(result.allSlices) { slice in
                    let rect = slice.originalRect
                    Path { path in
                        path.addRect(rect)
                    }
                    .stroke(slice.isFigure ? Color.purple : Color.orange, lineWidth: 1.5)

                    // Slice badge label
                    Text("#\(slice.sliceIndex + 1)\(slice.isFigure ? " 图" : "")")
                        .font(.system(size: 9, weight: .bold))
                        .padding(2)
                        .background(slice.isFigure ? Color.purple.opacity(0.8) : Color.orange.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(3)
                        .offset(x: rect.minX + 2, y: rect.minY + 2)
                }
            }
            .padding(20)
        }
        .background(Color.secondary.opacity(0.08))
    }

    @ViewBuilder
    private func debugSidebar(result: PageReflowResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("切片算法诊断数据")
                .font(.headline)
                .padding(.top, 16)

                    Divider()

                    Group {
                        DataRow(title: "原图分辨率", value: "\(Int(result.originalImage.size.width)) × \(Int(result.originalImage.size.height))")
                        DataRow(title: "裁切后内容区", value: "\(Int(result.contentBounds.width)) × \(Int(result.contentBounds.height))")
                        DataRow(title: "宏观分区数", value: "\(result.zones.count) 区 (\(result.zones.map { $0.type.rawValue }.joined(separator: ", ")))")
                        DataRow(title: "检测到分栏数", value: "\(result.columns.count) 栏")
                        DataRow(title: "切片总数", value: "\(result.allSlices.count) 块")
                        DataRow(title: "插图/图表块", value: "\(result.allSlices.filter { $0.isFigure }.count) 个")
                        DataRow(title: "纯文本行切片", value: "\(result.allSlices.filter { !$0.isFigure }.count) 行")
                    }

                    Divider()

                    Text("切片序列预览")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    List(result.allSlices) { slice in
                        HStack(spacing: 8) {
                            Text("[\(slice.columnIndex + 1)栏-\(slice.sliceIndex + 1)]")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)

                            Image(nsImage: slice.image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 28)
                                .border(Color.gray.opacity(0.3), width: 0.5)

                            Spacer()

                            Text("\(Int(slice.originalRect.width))×\(Int(slice.originalRect.height))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 260, maxWidth: 340)
                #endif
                .padding(.horizontal, 12)
    }
}

private struct DataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .fontWeight(.medium)
        }
    }
}
