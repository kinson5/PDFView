# 多看式扫描版 PDF 智能重排阅读器 (Duokan PDF Viewer for macOS)

本项目基于**“路线 A：经典图像切片流式重排（Image-based Reflow）”**方案构建，专为 macOS 设计，百分之百还原当年“多看阅读”的核心体验：**不依赖 OCR 字符识别，零错别字，完美保留原版笔画质感、数学公式与复杂插图，并在小屏或窄窗口中实现自适应流式排版**。

---

## 一、 核心算法技术链路 (路线 A 实现)

```
┌─────────────────┐
│ 扫描版 PDF 页面  │
└────────┬────────┘
         ▼
┌─────────────────┐
│ 高精度位图渲染   │  CGContext 200~300 DPI 离线栅格化
└────────┬────────┘
         ▼
┌─────────────────┐
│ 大津法 (Otsu)   │  自动分析墨迹与纸张底色，分离有效笔画
└────────┬────────┘
         ▼
┌─────────────────┐
│ 边缘自动裁剪     │  水平/垂直累积投影 (Projection Profiling)，切除大面积白边与装订黑边
└────────┬────────┘
         ▼
┌─────────────────┐
│ 智能多栏分析     │  自适应纵向波谷检测 (Valley Detection)，自动拆分双栏/多栏版面
└────────┬────────┘
         ▼
┌─────────────────┐
│ 视觉图表智能检测 │  VisualBlockDetector：网格线检测表格、波谷深度识别插图、同行图文并排分析
└────────┬────────┘
         ▼
┌─────────────────┐
│ 行切片与插图保护 │  表格整表保护 (不切碎)；独立插图整块保留；同行图文分离为插图与并行文本
└────────┬────────┘
         ▼
┌─────────────────┐
│ 宽度自适应流排   │  在 ScrollView 中根据屏幕宽度等比缩放、紧凑排列，支持多种纸质主题
└─────────────────┘
```

---

## 二、 核心特性

1. **图表与插图智能保护（彻底告别切碎乱码）**：
   * **表格整表检测与保护**：基于网格线（Ruling Lines）连通性分析，自动将表格作为不可分割的独立视觉块保留，绝不横向或纵向碎切单元格。
   * **同行图文混排自适应处理**：智能识别左图右文或左文右图的水平并排版式，将插图完整提取，右侧或左侧文本无缝拆入流式字流折行，在宽屏保持并排呈现，在小屏/大字号下自动优雅流式绕排。
   * **大幅插图与照片完整性**：波谷深度与连续度测试，自动识别插图与照片，按原始比例居中缩放。

2. **字词级流式段落重排 (多看核心精髓)**：
   * **窗口不变，段落自适应折行**：放大或缩小字号时，窗口和阅读容器宽度**严格保持不变**，文字按段落自适应折成更多或更少行，杜绝横向滚动条与溢出窗口。
   * **字块无损切片**：结合垂直投影与部首间距分析，将扫描行拆分为字词图块，保留段落自然首行缩进与段尾留白。

3. **四种阅读与对照模式**：
   * **智能重排模式 (多看流式字流)**：将多栏、宽边扫描件重排为自适应宽度的单流瀑布流，阅读畅快无阻。
   * **原始版面模式 (PDFKit)**：原生矢量与扫描版原汁原味预览。
   * **双屏对照模式**：左侧为原版 PDF，右侧为多看流式重排，方便比对排版效果。
   * **算法切片调试模式 (Debug Overlay)**：在原图上用彩色框线实时渲染白边裁剪框（绿色）、分栏边界（蓝色）、切片边界与图文标记（橙色/紫色），直观检验算法分割精度。

3. **多款质感纸张主题**：
   * **护眼暖阳**：柔和微黄色温，长时间阅读不累眼。
   * **经典羊皮纸**：多看阅读标志性复古纸感色调。
   * **纯白无暇** / **柔和冷灰**。
   * **夜间深色模式**：支持墨迹智能反白（深色底黑字自动转换为深色底白字，夜间阅读不刺眼）。

4. **微调与排版参数**：
   * 自由调节文字缩放比例（60% ~ 250%），窗口不变，段落自适应折行。
   * 自由调节行间距 (2pt ~ 28pt)、段间距 (4pt ~ 36pt)、字间距 (0pt ~ 8pt)。
   * 可开关“自动切白边”与“双栏检测”。
   * 图像去噪与对比度增强（stretch contrast / 大津法二值化）。

4. **内置开箱即用测试用例**：
   * 启动即自带双栏中英混排、含图表示例的扫描仿真 PDF，无需事先准备 PDF 文件即可直接体验；同时支持打开任意本地扫描版 PDF。

---

## 三、 运行与体验方式

### 方式 1：直接运行构建好的 macOS App Bundle
在 Finder 中双击 `DuokanPDFViewer.app`，或者在终端运行：
```bash
open DuokanPDFViewer.app
```

### 方式 2：使用 Swift 命令行运行
```bash
swift run
```

### 方式 3：运行测试用例
```bash
swift test
```

---

## 四、 核心代码架构

* `Sources/DuokanPDFViewer/Engine/`
  * [`PixelBuffer.swift`](file:///Users/mac/Downloads/pdfView/Sources/DuokanPDFViewer/Engine/PixelBuffer.swift): 高性能 8-bit 灰度像素矩阵与投影直方图计算
  * [`MarginDetector.swift`](file:///Users/mac/Downloads/pdfView/Sources/DuokanPDFViewer/Engine/MarginDetector.swift): 投影切边算法
  * [`ColumnDetector.swift`](file:///Users/mac/Downloads/pdfView/Sources/DuokanPDFViewer/Engine/ColumnDetector.swift): 自适应波谷双栏/多栏检测
  * [`LineSegmenter.swift`](file:///Users/mac/Downloads/pdfView/Sources/DuokanPDFViewer/Engine/LineSegmenter.swift): 水平投影行切片与插图识别
  * [`ImageEnhancer.swift`](file:///Users/mac/Downloads/pdfView/Sources/DuokanPDFViewer/Engine/ImageEnhancer.swift): 图像裁剪、对比度曲线与二值化增强
  * [`ReflowEngine.swift`](file:///Users/mac/Downloads/pdfView/Sources/DuokanPDFViewer/Engine/ReflowEngine.swift): 多线程异步重排管道与高速缓存
* `Sources/DuokanPDFViewer/Views/`
  * [`ReflowPageView.swift`](file:///Users/mac/Downloads/pdfView/Sources/DuokanPDFViewer/Views/ReflowPageView.swift): 多看式流式排版视图
  * [`SliceDebugView.swift`](file:///Users/mac/Downloads/pdfView/Sources/DuokanPDFViewer/Views/SliceDebugView.swift): 算法切片检测叠加诊断视图
  * [`MainReaderView.swift`](file:///Users/mac/Downloads/pdfView/Sources/DuokanPDFViewer/Views/MainReaderView.swift): 主界面与四模式切换
  * [`SettingsPanelView.swift`](file:///Users/mac/Downloads/pdfView/Sources/DuokanPDFViewer/Views/SettingsPanelView.swift): 交互式参数调优抽屉
* `Sources/DuokanPDFViewer/Utils/`
  * [`SamplePDFGenerator.swift`](file:///Users/mac/Downloads/pdfView/Sources/DuokanPDFViewer/Utils/SamplePDFGenerator.swift): 仿真双栏扫描版 PDF 测试文档生成器

---

## 五、 移植到 iOS / iPadOS 说明

由于本项目核心算法引擎 (`PixelBuffer`, `MarginDetector`, `ColumnDetector`, `LineSegmenter`, `ReflowEngine`) 仅依赖 `CoreGraphics` 与 `Foundation`（不含任何平台特定私有 API）：
* 移植至 iOS 时，只需将 `NSImage` 替换为 `UIImage`（或统一使用 `CGImage` 作为数据载体）。
* `SwiftUI` 视图代码可在 iPadOS / iOS 上几乎无缝复用，直接在 iPhone 上获得多看阅读经典的手机重排体验。
