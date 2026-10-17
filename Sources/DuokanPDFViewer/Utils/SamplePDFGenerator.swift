import Foundation
import CoreGraphics
import PDFKit
#if canImport(AppKit)
import AppKit
#endif

public struct SamplePDFGenerator {
    /// Generates a test PDF document for unit tests on macOS
    public static func generateSampleDocument() -> PDFDocument? {
        #if !canImport(AppKit)
        return nil
        #else
        let pdfData = NSMutableData()
        let pageSize = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }

        // --- Page 1: Double-column scanned book layout ---
        var pageRect = pageSize
        context.beginPage(mediaBox: &pageRect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        // Draw background (light warm paper texture tone)
        context.setFillColor(CGColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1.0))
        context.fill(pageRect)

        // Title
        let title = "PDFview 智能重排演示文档：文字与扫描双引擎阅读"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 22),
            .foregroundColor: NSColor.black
        ]
        let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
        titleStr.draw(at: CGPoint(x: 70, y: 760))

        // Subtitle / Page header
        let subtitle = "—— 自动识别原生文字版与图形扫描版 · 支持 Apple 原生多语种翻译"
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.darkGray
        ]
        NSAttributedString(string: subtitle, attributes: subAttrs).draw(at: CGPoint(x: 70, y: 735))

        // Divider
        context.setStrokeColor(CGColor(gray: 0.6, alpha: 1.0))
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: 70, y: 720))
        context.addLine(to: CGPoint(x: 525, y: 720))
        context.strokePath()

        // Column 1 (Left)
        let col1Rect = CGRect(x: 70, y: 320, width: 215, height: 380)
        let col1Text = """
        【第一章：图像切片重排的精妙之处】

        很多读者在小屏幕手机或狭长窗口中阅读扫描版 PDF 时，常常饱受“字太小看不清”、“放大后需要频繁左右拖拽”的折磨。

        当年多看阅读最受赞誉的功能，便是扫描版重排。与生硬的 OCR 文字识别相比，图像切片重排有不可替代的三大绝技：

        1. 零错别字：直接从原始扫描页上裁剪墨迹片段，不经过字符识别，百分之百还原原版排版与原书字体；

        2. 保留复杂公式与图表：遇到生僻字、数学符号、乐谱或插图时，传统 OCR 往往乱码，而切片重排能原貌呈现；

        3. 自适应流动排版：将双栏、多栏或带宽白边的页面切片后，按照屏幕宽度重新等比排列，一目十行顺畅翻页。
        """
        drawJustifiedText(col1Text, in: col1Rect, fontSize: 11.5)

        // Column 2 (Right)
        let col2Rect = CGRect(x: 310, y: 460, width: 215, height: 240)
        let col2Text = """
        【第二章：核心算法技术链路】

        本阅读器采用路线 A 的原生算法链路：

        ● 白边自动切除 (Auto-Crop)：
          利用水平与垂直累积像素投影柱状图，计算页面墨迹分布，剔除扫描产生的大面积留白与装订暗边。

        ● 多栏智能分析 (Column Split)：
          扫描双栏版面中间的贯穿性纵向波谷，自动将页面解构为左栏与右栏，遵循自然阅读顺序重组。

        ● 行切片与间距重构 (Line Slicing)：
          定位行间距波谷，细化裁剪每一文本行，并智能识别插图区块，实现流式自适应呈现。
        """
        drawJustifiedText(col2Text, in: col2Rect, fontSize: 11.5)

        // Diagram in Column 2 (Bottom right)
        let diagramRect = CGRect(x: 310, y: 320, width: 215, height: 125)
        context.setFillColor(CGColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1.0))
        context.fill(diagramRect)
        context.setStrokeColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1.0))
        context.setLineWidth(1.5)
        context.stroke(diagramRect)

        let diagTitle = "【图 1.1：重排切片示意图】"
        NSAttributedString(string: diagTitle, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.blue
        ]).draw(at: CGPoint(x: 320, y: 420))

        let diagContent = """
        ┌─────────────┐
        │ 扫描双栏原稿 │ ──> 投影检测分栏
        └──────┬──────┘
               ▼
        ┌──────┴──────┐
        │ 行切片拆分   │ ──> 宽度自适应流排
        └─────────────┘
        """
        drawJustifiedText(diagContent, in: CGRect(x: 320, y: 325, width: 195, height: 90), fontSize: 10)

        // Page footer
        let footerStr = NSAttributedString(string: "— 1 —", attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.gray
        ])
        footerStr.draw(at: CGPoint(x: 285, y: 50))

        NSGraphicsContext.restoreGraphicsState()
        context.endPage()

        // --- Page 2: Single-column with wide margins and illustrations ---
        var page2Rect = pageSize
        context.beginPage(mediaBox: &page2Rect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        context.setFillColor(CGColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1.0))
        context.fill(page2Rect)

        let p2Title = "第三章：护眼与自定义排版体验"
        NSAttributedString(string: p2Title, attributes: titleAttrs).draw(at: CGPoint(x: 90, y: 760))

        let p2Rect = CGRect(x: 90, y: 450, width: 415, height: 280)
        let p2Text = """
        在数字化阅读时代，读者的阅读环境千变万化。

        通过图表与图文智能检测引擎，不仅解决了文字大小与排版流动的难题，更攻克了传统扫描重排中“图片与表格被碎尸万段”的严重痛点：

        1. 完整表格保护：检测网格线与框架，整表保持 100% 连贯，绝不切断单元格；
        2. 同行图文智能混排：文字与侧边插图并排呈现，放大字号时文字优雅自适应绕排；
        3. 零错别字原图质感：完全保留公式、生僻字、图解与书法笔触。
        """
        drawJustifiedText(p2Text, in: p2Rect, fontSize: 12.5)

        // Draw Table (Ruling lines and cells)
        let tableRect = CGRect(x: 90, y: 280, width: 415, height: 130)
        context.setFillColor(CGColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0))
        context.fill(tableRect)
        context.setStrokeColor(CGColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1.0))
        context.setLineWidth(1.5)
        context.stroke(tableRect)

        // Table horizontal lines
        context.move(to: CGPoint(x: 90, y: 375))
        context.addLine(to: CGPoint(x: 505, y: 375))
        context.move(to: CGPoint(x: 90, y: 330))
        context.addLine(to: CGPoint(x: 505, y: 330))
        context.strokePath()

        // Table vertical lines
        context.move(to: CGPoint(x: 220, y: 410))
        context.addLine(to: CGPoint(x: 220, y: 280))
        context.move(to: CGPoint(x: 360, y: 410))
        context.addLine(to: CGPoint(x: 360, y: 280))
        context.strokePath()

        // Table text
        drawJustifiedText("【重排技术路线】\n经典多看切片 A\n现代文本 OCR B", in: CGRect(x: 100, y: 290, width: 110, height: 110), fontSize: 10)
        drawJustifiedText("【核心优势】\n零错字·公式保真·原图质感\n字号自由调·易转 Markdown", in: CGRect(x: 230, y: 290, width: 120, height: 110), fontSize: 10)
        drawJustifiedText("【图表与复杂版面】\n整表整图保护·图文同行绕排\nOCR 图表易乱码丢失结构", in: CGRect(x: 370, y: 290, width: 125, height: 110), fontSize: 10)

        // Side-by-Side: Left Figure + Right Text in Page 2
        let sideFigRect = CGRect(x: 90, y: 130, width: 120, height: 110)
        context.setFillColor(CGColor(red: 0.92, green: 0.94, blue: 0.96, alpha: 1.0))
        context.fill(sideFigRect)
        context.stroke(sideFigRect)
        drawJustifiedText("【同行插图】\n\n[示例图标/图表]\n侧边插图块\n整图完美保留", in: CGRect(x: 95, y: 140, width: 110, height: 90), fontSize: 10)

        let sideTextRect = CGRect(x: 225, y: 130, width: 280, height: 110)
        let sideText = """
        【同行图文混排演示】：
        左侧为插图，右侧为文字说明。
        在阅读器中，它们处于同一水平高度。
        算法会智能识别左图右文并排关系，
        保证左图不被横切碎成条状，
        右侧文字仍能享受自适应流式排版！
        """
        drawJustifiedText(sideText, in: sideTextRect, fontSize: 11)

        let footer2Str = NSAttributedString(string: "— 2 —", attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.gray
        ])
        footer2Str.draw(at: CGPoint(x: 285, y: 50))

        NSGraphicsContext.restoreGraphicsState()
        context.endPage()

        // --- Page 3: 古籍经典竖排版面 (Vertical Text Classic Chinese Layout) ---
        var page3Rect = pageSize
        context.beginPage(mediaBox: &page3Rect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        // Antique cream paper background
        context.setFillColor(CGColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1.0))
        context.fill(page3Rect)

        // Vintage book border frame
        let frameRect = CGRect(x: 50, y: 70, width: 495.2, height: 701.8)
        context.setStrokeColor(CGColor(red: 0.5, green: 0.2, blue: 0.2, alpha: 0.8))
        context.setLineWidth(2.0)
        context.stroke(frameRect)

        let innerFrame = CGRect(x: 55, y: 75, width: 485.2, height: 691.8)
        context.setLineWidth(0.8)
        context.stroke(innerFrame)

        // Vertical columns drawn from RIGHT to LEFT
        // Column 0 is the Title ("桃花源记"), drawn vertically with top space
        let verticalColumns = [
            "桃花源记",
            "晋太元中武陵人捕鱼为业缘溪行忘路之远近忽逢桃花林",
            "夹岸数百步中无杂树芳草鲜美落英缤纷渔人甚异之",
            "复前行欲穷其林林尽水源便得一山山有小口仿佛若有光",
            "便舍船从口入初极狭才通人复行数十步豁然开朗",
            "土地平旷屋舍俨然有良田美池桑竹之属阡陌交通鸡犬相闻",
            "其中往来种作男女衣着悉如外人黄发垂髫并怡然自乐",
            "见渔人乃大惊问所从来具答之便要还家设酒杀鸡作食",
            "村中闻有此人咸来问讯自云先世避秦时乱率妻子邑人来此绝境",
            "不复出焉遂与外人间隔问今是何世乃不知有汉无论魏晋",
            "此人一一为具言所闻皆叹惋余人各复延至其家皆出酒食",
            "停数日辞去此中人语云不足为外人道也"
        ]

        let rightMargin: CGFloat = 500.0
        let colSpacing: CGFloat = 36.0
        let charSize: CGFloat = 16.0
        let charSpacing: CGFloat = 7.0

        for (idx, colText) in verticalColumns.enumerated() {
            let colX = rightMargin - CGFloat(idx) * colSpacing
            var startY = CGFloat(690)
            let cSize = (idx == 0) ? 20.0 : charSize // Title has larger font
            if idx == 0 {
                // Title indented by 3 characters from top
                startY -= (cSize + charSpacing) * 3
            } else if idx == 1 {
                // Paragraph 1 indented by 2 characters
                startY -= (charSize + charSpacing) * 2
            } else if idx == 7 {
                // Paragraph 2 indented by 2 characters
                startY -= (charSize + charSpacing) * 2
            }

            drawVerticalColumn(
                colText,
                at: CGPoint(x: colX, y: startY),
                charSize: cSize,
                spacing: charSpacing
            )
        }

        let footer3Str = NSAttributedString(string: "— 3 —", attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.gray
        ])
        footer3Str.draw(at: CGPoint(x: 285, y: 50))

        NSGraphicsContext.restoreGraphicsState()
        context.endPage()
        context.closePDF()

        return PDFDocument(data: pdfData as Data)
        #endif
    }

    #if canImport(AppKit)
    private static func drawJustifiedText(_ text: String, in rect: CGRect, fontSize: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5.0
        style.paragraphSpacing = 8.0

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black,
            .paragraphStyle: style
        ]

        let attrStr = NSAttributedString(string: text, attributes: attrs)
        attrStr.draw(in: rect)
    }

    private static func drawVerticalColumn(
        _ text: String,
        at startPoint: CGPoint,
        charSize: CGFloat,
        spacing: CGFloat
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: charSize),
            .foregroundColor: NSColor.black
        ]
        var currentY = startPoint.y
        for char in text {
            let s = String(char)
            let attrStr = NSAttributedString(string: s, attributes: attrs)
            attrStr.draw(at: CGPoint(x: startPoint.x, y: currentY))
            currentY -= (charSize + spacing)
        }
    }
    #endif
}
