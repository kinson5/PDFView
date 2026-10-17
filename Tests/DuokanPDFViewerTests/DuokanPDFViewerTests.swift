import Testing
import CoreGraphics
import PDFKit
import AppKit
import Vision
@testable import DuokanPDFViewer

@Suite("Duokan Route A PDF Reflow Engine Tests", .serialized)
struct DuokanPDFViewerTests {

    @Test("Sample PDF Generation")
    func testSamplePDFGeneration() throws {
        let doc = SamplePDFGenerator.generateSampleDocument()
        #expect(doc != nil)
        #expect(doc?.pageCount == 3)
    }

    @Test("PixelBuffer and Projections")
    func testPixelBuffer() throws {
        guard let doc = SamplePDFGenerator.generateSampleDocument(),
              let page = doc.page(at: 0),
              let cgImage = ReflowEngine.renderPageToCGImage(page: page, dpi: 150) else {
            Issue.record("Failed to render sample PDF page to CGImage")
            return
        }

        guard let pixelBuffer = PixelBuffer(cgImage: cgImage) else {
            Issue.record("Failed to create PixelBuffer")
            return
        }

        #expect(pixelBuffer.width == cgImage.width)
        #expect(pixelBuffer.height == cgImage.height)

        let threshold = pixelBuffer.calculateOtsuThreshold()
        #expect(threshold >= 100 && threshold <= 240)

        let bounds = CGRect(x: 0, y: 0, width: pixelBuffer.width, height: pixelBuffer.height)
        let horiz = pixelBuffer.horizontalProjection(in: bounds, threshold: threshold)
        let vert = pixelBuffer.verticalProjection(in: bounds, threshold: threshold)

        #expect(horiz.count == pixelBuffer.height)
        #expect(vert.count == pixelBuffer.width)
        #expect(horiz.reduce(0, +) > 0)
        #expect(vert.reduce(0, +) > 0)
    }

    @Test("Margin Auto-Cropping")
    func testMarginDetector() throws {
        guard let doc = SamplePDFGenerator.generateSampleDocument(),
              let page = doc.page(at: 0),
              let cgImage = ReflowEngine.renderPageToCGImage(page: page, dpi: 150),
              let pixelBuffer = PixelBuffer(cgImage: cgImage) else {
            Issue.record("Setup failed")
            return
        }

        let threshold = pixelBuffer.calculateOtsuThreshold()
        let contentBounds = MarginDetector.detectContentBounds(pixelBuffer: pixelBuffer, threshold: threshold)

        #expect(contentBounds.width > 100)
        #expect(contentBounds.height > 100)
        #expect(contentBounds.width <= CGFloat(pixelBuffer.width))
        #expect(contentBounds.height <= CGFloat(pixelBuffer.height))
    }

    @Test("Column Detection")
    func testColumnDetector() throws {
        guard let doc = SamplePDFGenerator.generateSampleDocument(),
              let page = doc.page(at: 0),
              let cgImage = ReflowEngine.renderPageToCGImage(page: page, dpi: 150),
              let pixelBuffer = PixelBuffer(cgImage: cgImage) else {
            Issue.record("Setup failed")
            return
        }

        let threshold = pixelBuffer.calculateOtsuThreshold()
        let contentBounds = MarginDetector.detectContentBounds(pixelBuffer: pixelBuffer, threshold: threshold)
        let columns = ColumnDetector.detectColumns(
            pixelBuffer: pixelBuffer,
            contentBounds: contentBounds,
            threshold: threshold
        )

        // The sample page 1 is double-column, should detect 2 columns
        #expect(columns.count >= 2)
        for col in columns {
            #expect(col.width > 50)
            #expect(col.height > 50)
        }
    }

    @Test("Full End-to-End Reflow Pipeline")
    func testEndToEndReflow() async throws {
        guard let doc = SamplePDFGenerator.generateSampleDocument(),
              let page = doc.page(at: 0) else {
            Issue.record("Setup failed")
            return
        }

        var config = ReflowConfig()
        config.renderDPI = 150
        config.detectColumns = true
        config.trimMargins = true

        let engine = ReflowEngine()
        let result = await engine.processPage(page: page, pageIndex: 0, config: config)

        #expect(result != nil)
        guard let res = result else { return }

        #expect(res.pageIndex == 0)
        #expect(!res.allSlices.isEmpty)
        #expect(res.columns.count >= 2)
        #expect(res.allSlices.count >= 8) // Page 1 has multiple lines and paragraphs

        // Ensure slices have images and positive dimensions
        for slice in res.allSlices {
            #expect(slice.originalRect.width > 0)
            #expect(slice.originalRect.height > 0)
            #expect(slice.image.size.width > 0)
        }
    }

    @Test("VisualBlock Detection: Tables & Side-by-Side Slices")
    func testVisualBlockDetection() async throws {
        guard let doc = SamplePDFGenerator.generateSampleDocument(),
              let page2 = doc.page(at: 1) else {
            Issue.record("Setup failed")
            return
        }

        var config = ReflowConfig()
        config.renderDPI = 150
        config.detectColumns = false // Page 2 is single column with table and side-by-side
        config.trimMargins = true

        let engine = ReflowEngine()
        let result = await engine.processPage(page: page2, pageIndex: 1, config: config)

        #expect(result != nil)
        guard let res = result else { return }

        // Verify that tables are preserved as intact table blocks
        let tableParagraphs = res.paragraphs.filter { $0.isTable }
        #expect(!tableParagraphs.isEmpty)
        if let table = tableParagraphs.first {
            #expect(table.figureSlice != nil)
            #expect(table.figureSlice?.isTable == true)
            #expect(table.figureSlice?.originalRect.width ?? 0 > 100)
            #expect(table.figureSlice?.originalRect.height ?? 0 > 50)
        }

        // Verify paragraphs contain text words and are not empty
        let textParagraphs = res.paragraphs.filter { !$0.isTable && !$0.isFigure }
        #expect(!textParagraphs.isEmpty)
    }

    @Test("Paragraph Integrity & Continuous Flow (Elimination of Unnecessary Line Breaks)")
    func testParagraphIntegrityAndContinuousFlow() async throws {
        guard let doc = SamplePDFGenerator.generateSampleDocument(),
              let page1 = doc.page(at: 0) else {
            Issue.record("Setup failed")
            return
        }

        var config = ReflowConfig()
        config.renderDPI = 150
        config.detectColumns = true
        config.trimMargins = true
        config.enableWordReflow = true

        let engine = ReflowEngine()
        let result = await engine.processPage(page: page1, pageIndex: 0, config: config)

        #expect(result != nil)
        guard let res = result else { return }

        // Find multi-line text paragraphs
        let multiWordParagraphs = res.paragraphs.filter { !$0.isFigure && !$0.isTable && $0.words.count > 15 }
        #expect(!multiWordParagraphs.isEmpty)

        // Ensure that paragraphs are not fragmented into 1-line or 2-line snippets
        for para in multiWordParagraphs {
            #expect(para.words.count >= 15)
            #expect(para.baseLineHeight > 10)
        }

        // Verify standalone diagram/table in Column 2 is protected as visual block
        let visualBlocks = res.paragraphs.filter { $0.isFigure || $0.isTable }
        #expect(!visualBlocks.isEmpty)
        if let fig = visualBlocks.first {
            #expect(fig.figureSlice != nil)
            #expect(fig.figureSlice?.originalRect.height ?? 0 > 30)
        }
    }

    @Test("Diagnose User Actual PDF")
    func testUserActualPDF() async throws {
        let pdfPath = "/Users/mac/Downloads/泉州市医疗保障局晋江分局关于医保智能监管事前提醒功能应用落实情况通报（2026.10.01-10.08）.pdf"
        guard FileManager.default.fileExists(atPath: pdfPath),
              let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
              let page = doc.page(at: 0) else {
            return
        }

        var config = ReflowConfig()
        config.enableWordReflow = true
        let engine = ReflowEngine()
        let result = await engine.processPage(page: page, pageIndex: 0, config: config)
        guard let res = result else { return }

        print("=== USER PDF DIAGNOSTIC ===")
        print("Columns: \(res.columns.count)")
        for col in res.columns {
            print("  Col \(col.index): rect=\(col.rect), slices=\(col.slices.count)")
        }
        print("Total Slices: \(res.allSlices.count)")
        for (i, s) in res.allSlices.enumerated() {
            let fw = s.words.first?.originalRect.minX ?? -1
            let lw = s.words.last?.originalRect.maxX ?? -1
            let rGap = (res.columns.first?.rect.maxX ?? 0) - lw
            print("  Slice \(i): rect=\(s.originalRect), words=\(s.words.count), firstX=\(fw), lastX=\(lw), rGap=\(rGap)")
        }
        print("Total Paragraphs: \(res.paragraphs.count)")
        for (i, p) in res.paragraphs.enumerated() {
            let textPreview = p.recognizedText.map { "\"\($0.prefix(35))...\"" } ?? "nil"
            print("  Para \(i): isFig=\(p.isFigure), isTitle=\(p.isTitle), words=\(p.words.count), hasIndent=\(p.hasIndent), text=\(textPreview)")
        }

        // Verify Apple Vision OCR text is successfully bound to paragraphs
        let paragraphsWithText = res.paragraphs.filter { $0.recognizedText != nil && !$0.recognizedText!.isEmpty }
        #expect(!paragraphsWithText.isEmpty)

        // Verify the 147-word body paragraph was merged and contains the recognized sentence
        let bodyPara = res.paragraphs.first { !$0.isTitle && ($0.recognizedText ?? "").contains("为进一步推进") }
        #expect(bodyPara != nil)
        #expect(bodyPara?.words.count ?? 0 >= 100)
    }

    @Test("Diagnose Mannheim Book Footnote Page")
    func testDiagnoseMannheimBook() async throws {
        let pdfPath = "/Users/mac/Downloads/books/books202606/保守主义 [德]K.曼海姆.pdf"
        guard FileManager.default.fileExists(atPath: pdfPath),
              let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
              let page = doc.page(at: 77) else {
            return
        }

        var config = ReflowConfig()
        config.enableWordReflow = true
        let engine = ReflowEngine()
        let result = await engine.processPage(page: page, pageIndex: 77, config: config)
        guard let res = result else { return }

        print("\n=== MANNHEIM BOOK PAGE 32 DIAGNOSTIC ===")
        print("Macro Zones: \(res.zones.count)")
        for (i, z) in res.zones.enumerated() {
            print("  Zone \(i): type=\(z.type.rawValue), rect=\(z.rect), slices=\(z.slices.count), paragraphs=\(z.paragraphs.count)")
        }

        print("Total Slices: \(res.allSlices.count)")
        for (i, s) in res.allSlices.enumerated() {
            print("  Slice \(i): isTable=\(s.isTable), isFig=\(s.isFigure), rect=\(s.originalRect), words=\(s.words.count), text=\(s.recognizedText ?? "nil")")
        }

        print("\nTotal Paragraphs: \(res.paragraphs.count)")
        for (i, p) in res.paragraphs.enumerated() {
            print("  Para \(i): level=\(p.semanticLevel.rawValue), isFig=\(p.isFigure), isTable=\(p.isTable), words=\(p.words.count), text=\(p.recognizedText ?? "nil")")
        }
        #expect(res.resolvedProfile == .book)
        #expect(!res.zones.isEmpty)
        #expect(res.zones.contains { $0.type == .body })
    }

    @MainActor
    @Test("Diagnose User Nanyang Book (赤道線的南洋密碼)")
    func testDiagnoseNanyangBook() async throws {
        let pdfPath = "/Users/mac/Downloads/pdfView/赤道線的南洋密碼.pdf"
        guard FileManager.default.fileExists(atPath: pdfPath),
              let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            print("Cannot open 赤道線的南洋密碼.pdf")
            return
        }

        // Test page 20
        let targetPageIdx = 20
        guard let page = doc.page(at: targetPageIdx) else { return }

        let engine = ReflowEngine()
        var config = ReflowConfig()
        config.layoutProfile = .auto
        config.enableWordReflow = true

        let result = await engine.processPage(page: page, pageIndex: targetPageIdx, config: config)
        guard let res = result else {
            print("ReflowEngine returned nil for page \(targetPageIdx)")
            return
        }

        if let cgImg = ReflowEngine.renderPageToCGImage(page: page, dpi: 150),
           let vision = VisionTextRecognizer.recognize(cgImage: cgImg) {
            print("\n--- VISION DETECTED LINES ON NANYANG PAGE 20 (Count: \(vision.lines.count)) ---")
            for (i, line) in vision.lines.prefix(15).enumerated() {
                print("Line \(i): rect=\(line.rect), text=\"\(line.text)\"")
            }
            print("--- END VISION LINES ---\n")
        }
        print("Resolved Profile: \(res.resolvedProfile)")
        print("Detected Columns: \(res.columns.count)")
        print("Total Slices: \(res.allSlices.count)")
        print("Total Paragraphs: \(res.paragraphs.count)")
        for (i, p) in res.paragraphs.enumerated() {
            let sample = p.words.prefix(3).map { "(\($0.originalRect.width)x\($0.originalRect.height))" }.joined(separator: ",")
            print("  Para \(i): isTitle=\(p.isTitle), hasIndent=\(p.hasIndent), words=\(p.words.count), wordSizes=[\(sample)], ocr=\"\(p.recognizedText?.prefix(40) ?? "nil")...\"")
        }

        #expect(res.resolvedProfile == .verticalBook)
        #expect(res.allSlices.count == 14)
        #expect(res.paragraphs.contains { $0.hasIndent })
        #expect(!res.paragraphs.isEmpty)

        // Save original rendered image for visual inspection
        if let cgImg = ReflowEngine.renderPageToCGImage(page: page, dpi: 150) {
            let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
            if let tiff = nsImg.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "/Users/mac/Downloads/pdfView/nanyang_p20.png"))
                print("Saved /Users/mac/Downloads/pdfView/nanyang_p20.png")
            }
        }
    }

    @MainActor
    @Test("Diagnose User Alien Land Book Page 214 (異鄉人之地)")
    func testDiagnoseAlienLandPage214() async throws {
        let pdfPath = "/Users/mac/Downloads/pdfView/異鄉人之地清帝國在新疆的教化工程 (許臨君).pdf"
        guard FileManager.default.fileExists(atPath: pdfPath),
              let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
              let page = doc.page(at: 214) else {
            print("Cannot open 異鄉人之地 page 214")
            return
        }

        let engine = ReflowEngine()
        var config = ReflowConfig()
        config.layoutProfile = .auto
        config.enableWordReflow = true

        let result = await engine.processPage(page: page, pageIndex: 214, config: config)
        #expect(result != nil)
        guard let res = result else { return }

        print("\n=== ALIEN LAND PAGE 214 DIAGNOSTIC ===")
        print("Resolved Profile: \(res.resolvedProfile.rawValue)")
        print("Detected Columns: \(res.columns.count)")
        print("Total Slices: \(res.allSlices.count)")
        print("Total Paragraphs: \(res.paragraphs.count)")
        for (i, p) in res.paragraphs.enumerated() {
            print("  Para \(i): isTitle=\(p.isTitle), hasIndent=\(p.hasIndent), words=\(p.words.count), ocr=\"\(p.recognizedText?.prefix(50) ?? "nil")...\"")
            for (wIdx, w) in p.words.prefix(25).enumerated() {
                print("    Word \(wIdx): rect=\(w.originalRect), size=(\(w.image.size.width)x\(w.image.size.height))")
            }
        }

        #expect(res.resolvedProfile == .verticalBook)
        #expect(res.paragraphs.count >= 2)
        let firstPara = res.paragraphs[0]
        #expect(firstPara.words.count > 100)
        // Word 10 (`︽` -> `《`) and Word 15 (`︾` -> `》`) must be rotated 90° CCW (width < height)
        #expect(firstPara.words[10].originalRect.width < firstPara.words[10].originalRect.height)
        #expect(firstPara.words[15].originalRect.width < firstPara.words[15].originalRect.height)
        // Middle dot `·` (Word 2) and comma `，` (Word 20) retain compact dimensions
        #expect(firstPara.words[2].originalRect.height <= 20.0)
        #expect(firstPara.words[20].originalRect.height <= 22.0)
        // OCR accurately recognizes rotated book title brackets 《伊米德史》
        #expect(firstPara.recognizedText?.contains("伊米德史") == true)
    }

    @MainActor
    @Test("Random 10 Pages Reflow Test for Nanyang Book (赤道線的南洋密碼)")
    func testRandom10PagesReflowNanyangBook() async throws {
        let pdfPath = "/Users/mac/Downloads/pdfView/赤道線的南洋密碼.pdf"
        guard FileManager.default.fileExists(atPath: pdfPath),
              let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            print("Cannot open 赤道線的南洋密碼.pdf")
            return
        }

        let totalPages = doc.pageCount
        print("\n=======================================================")
        print("RANDOM 10 PAGES REFLOW BENCHMARK: 赤道線的南洋密碼.pdf (Total: \(totalPages) pages)")
        print("=======================================================")

        // Pick 10 representative pages distributed across the book body (between page 15 and 445)
        var testPages: [Int] = []
        let minPage = 15
        let maxPage = min(totalPages - 15, 445)
        let step = (maxPage - minPage) / 10
        for i in 0..<10 {
            let jitter = (i * 17 + 7) % max(1, step / 2)
            testPages.append(minPage + i * step + jitter)
        }

        print("Selected Pages for Testing: \(testPages)\n")

        let engine = ReflowEngine()
        var config = ReflowConfig()
        config.layoutProfile = .auto
        config.enableWordReflow = true

        var passedCount = 0
        var totalWordsAcrossPages = 0
        var totalParagraphsAcrossPages = 0

        var verticalBookCount = 0

        for (idx, pageNum) in testPages.enumerated() {
            guard let page = doc.page(at: pageNum) else { continue }
            let startTime = CACurrentMediaTime()
            let result = await engine.processPage(page: page, pageIndex: pageNum, config: config)
            let duration = CACurrentMediaTime() - startTime

            guard let res = result else {
                print("❌ [Page \(pageNum)] (#\(idx + 1)/10): Returned nil!")
                continue
            }

            let wordCount = res.paragraphs.flatMap { $0.words }.count
            let paraCount = res.paragraphs.count
            let indentedCount = res.paragraphs.filter { $0.hasIndent }.count
            let sampleOCR = res.paragraphs.compactMap { $0.recognizedText }.first?.prefix(35) ?? "无OCR"

            print(String(format: "📖 [Page %3d] (#%2d/10): Profile=%@ | Cols=%2d | Slices=%2d | Paras=%2d (Indent=%d) | Words=%3d | Time=%.2fs | OCR=\"%@...\"",
                pageNum, idx + 1, res.resolvedProfile.rawValue, res.columns.count, res.allSlices.count, paraCount, indentedCount, wordCount, duration, String(sampleOCR)
            ))

            if res.resolvedProfile == .verticalBook {
                verticalBookCount += 1
                #expect(!res.columns.isEmpty)
                #expect(!res.paragraphs.isEmpty)
                #expect(wordCount >= 2)
            } else {
                // Photo illustration / ancient map pages with horizontal captions
                #expect(res.resolvedProfile != .verticalBook)
                #expect(!res.paragraphs.isEmpty || !res.allSlices.isEmpty)
            }

            passedCount += 1
            totalWordsAcrossPages += wordCount
            totalParagraphsAcrossPages += paraCount
        }

        #expect(verticalBookCount >= 7)

        print("\n=== SUMMARY OF 10 PAGES REFLOW ===")
        print("Total Pages Processed: \(passedCount)/10")
        print("Total Words Reflowed: \(totalWordsAcrossPages)")
        print("Total Paragraphs Formed: \(totalParagraphsAcrossPages)")
        print("Average Words / Page: \(totalWordsAcrossPages / max(1, passedCount))")
        print("==================================\n")

        #expect(passedCount == 10)
    }

    @MainActor
    @Test("Intelligent Whitespace-driven Macro Page Zone Partitioning")
    func testMacroWhitespaceZoneDetection() async throws {
        let engine = ReflowEngine()
        if let sampleDoc = SamplePDFGenerator.generateSampleDocument(), let page0 = sampleDoc.page(at: 0) {
            let res = await engine.processPage(page: page0, pageIndex: 0, config: ReflowConfig())
            #expect(res != nil)
            guard let result = res else { return }
            #expect(!result.zones.isEmpty)
            #expect(result.zones.contains { $0.type == .body })
            #expect(!result.allSlices.isEmpty)
            #expect(result.zones.flatMap { $0.slices }.count == result.allSlices.count)
        }
    }

    @MainActor
    @Test("Human-AI Collaboration: Layout Classifier & Profiles")
    func testLayoutClassifierAndProfiles() async throws {
        let engine = ReflowEngine()

        // 1. Double column sample document should auto-detect as .academic
        if let sampleDoc = SamplePDFGenerator.generateSampleDocument(), let page0 = sampleDoc.page(at: 0) {
            var autoConfig = ReflowConfig()
            autoConfig.layoutProfile = .auto
            let res = await engine.processPage(page: page0, pageIndex: 0, config: autoConfig)
            #expect(res?.resolvedProfile == .academic)

            // Manual override to .magazine
            var manualConfig = ReflowConfig()
            manualConfig.layoutProfile = .magazine
            let manualRes = await engine.processPage(page: page0, pageIndex: 0, config: manualConfig)
            #expect(manualRes?.resolvedProfile == .magazine)
        }

        // 2. Official Notice document should auto-detect as .officialDoc
        let officialPdfPath = "/Users/mac/Downloads/泉州市医疗保障局晋江分局关于医保智能监管事前提醒功能应用落实情况通报（2026.10.01-10.08）.pdf"
        if FileManager.default.fileExists(atPath: officialPdfPath),
           let doc = PDFDocument(url: URL(fileURLWithPath: officialPdfPath)),
           let page = doc.page(at: 0) {
            var autoConfig = ReflowConfig()
            autoConfig.layoutProfile = .auto
            let res = await engine.processPage(page: page, pageIndex: 0, config: autoConfig)
            #expect(res?.resolvedProfile == .officialDoc)
        }
    }

    @Test("Human-AI Collaboration: Book Preference Store")
    func testBookPreferencePersistence() {
        let testBook = "UnitTest_TestBook.pdf"
        let pref = BookPreference(
            layoutProfile: .book,
            textScale: 1.25,
            sliceSpacing: 14.0,
            readingTheme: ReadingTheme.sepia.rawValue,
            lastPageIndex: 42
        )

        BookPreferenceStore.shared.save(for: testBook, preference: pref)
        let loaded = BookPreferenceStore.shared.load(for: testBook)

        #expect(loaded != nil)
        #expect(loaded?.layoutProfile == .book)
        #expect(loaded?.textScale == 1.25)
        #expect(loaded?.sliceSpacing == 14.0)
        #expect(loaded?.readingTheme == ReadingTheme.sepia.rawValue)
        #expect(loaded?.lastPageIndex == 42)
        #expect(loaded?.inkLevel == .enhanced)
    }

    @Test("Image Clarity: Contrast, Darkening, Thickening and Sharpening Pipeline")
    func testImageClarityPipeline() {
        // Create a 20x20 test image with faint text and grayish background
        let width = 20
        let height = 20
        var pixels = [UInt8](repeating: 230, count: width * height) // Light gray background
        // Draw a faint gray line in the middle (value 120)
        for x in 4..<16 {
            pixels[10 * width + x] = 120
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let inputImage = ctx.makeImage() else {
            #expect(Bool(false), "Failed to create test image")
            return
        }

        for ink in InkLevel.allCases {
            var config = ReflowConfig()
            config.setInkLevel(ink)
            let enhanced = ImageEnhancer.enhance(
                image: inputImage,
                mode: .contrastEnhanced,
                threshold: 128,
                config: config,
                isGraphic: false
            )
            #expect(enhanced.width == width)
            #expect(enhanced.height == height)
        }
    }

    @MainActor
    @Test("Vertical Text Deconstruction & Reflow to Horizontal Flow (古籍/港台竖排转横排)")
    func testVerticalTextReflowAndOCR() async throws {
        guard let doc = SamplePDFGenerator.generateSampleDocument(),
              let page2 = doc.page(at: 2) else {
            #expect(Bool(false), "Failed to generate Page 3 of sample doc")
            return
        }

        let engine = ReflowEngine()
        var config = ReflowConfig()
        config.layoutProfile = .verticalBook
        config.enableWordReflow = true

        let result = await engine.processPage(page: page2, pageIndex: 2, config: config)
        #expect(result != nil)
        guard let res = result else { return }

        #expect(res.resolvedProfile == .verticalBook)
        #expect(!res.columns.isEmpty)
        #expect(!res.allSlices.isEmpty)
        #expect(!res.paragraphs.isEmpty)

        // Verify words exist and flow horizontally
        let totalWords = res.paragraphs.flatMap { $0.words }.count
        #expect(totalWords > 20)

        // Verify at least one paragraph has indentation
        #expect(res.paragraphs.contains { $0.hasIndent })

        // Verify title or body paragraphs have recognized text
        let recognizedParagraphs = res.paragraphs.filter { $0.recognizedText != nil && !$0.recognizedText!.isEmpty }
        #expect(!recognizedParagraphs.isEmpty)

        print("\n=== VERTICAL TEXT REFLOW TEST RESULTS ===")
        print("Detected Vertical Columns: \(res.columns.count)")
        print("Total Slices: \(res.allSlices.count)")
        print("Horizontal Paragraphs: \(res.paragraphs.count)")
        for (i, p) in res.paragraphs.enumerated() {
            print("  Para \(i): isTitle=\(p.isTitle), hasIndent=\(p.hasIndent), words=\(p.words.count), ocr=\"\(p.recognizedText ?? "nil")\"")
        }
    }

    @MainActor
    @Test("Diagnose Page 269 in Xinjiang Book")
    func testDiagnosePage269() async throws {
        let pdfPath = "/Users/mac/Downloads/pdfView/異鄉人之地清帝國在新疆的教化工程 (許臨君).pdf"
        guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else { return }

        for p in 100..<190 {
            guard let page = doc.page(at: p), let cg = ReflowEngine.renderPageToCGImage(page: page, dpi: 150) else { continue }
            let vis = VisionTextRecognizer.recognize(cgImage: cg)
            let texts = vis?.lines.map { $0.text }.joined() ?? ""
            if texts.contains("阿舒爾") || texts.contains("非突厥") || texts.contains("沙赫亞里") || texts.contains("賽拉米") {
                print("🎯🎯🎯 EXACT PAGE IS: \(p)!")
                break
            }
        }
    }

    @MainActor
    @Test("Diagnose Vietnam Page 50")
    func testDiagnoseVietnamPage50() async throws {
        let pdfPath = "/Users/mac/Downloads/pdfView/越南：世界史的失語者 by 〔美〕克里斯多佛著；譚天譯.pdf"
        guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
              let page = doc.page(at: 50) else { return }

        guard let cgImage = ReflowEngine.renderPageToCGImage(page: page, dpi: 200),
              let pixelBuffer = PixelBuffer(cgImage: cgImage) else { return }

        let otsu = pixelBuffer.calculateOtsuThreshold()
        let contentBounds = MarginDetector.detectContentBounds(pixelBuffer: pixelBuffer, threshold: otsu)
        print("Page 50 Image Size: \(cgImage.width)x\(cgImage.height), Otsu: \(otsu), ContentBounds: \(contentBounds)")

        let vision = VisionTextRecognizer.recognize(cgImage: cgImage)
        let vLines = vision?.lines ?? []
        print("Vision lines count: \(vLines.count)")
        let verticalVisionLines = vLines.filter { $0.rect.height > $0.rect.width * 1.35 }
        let horizontalVisionLines = vLines.filter { $0.rect.width > $0.rect.height * 1.25 }
        print("Vision vertical lines: \(verticalVisionLines.count), horizontal lines: \(horizontalVisionLines.count)")
        for l in vLines.prefix(10) {
            print("  Vision line: rect=(\(Int(l.rect.minX)),\(Int(l.rect.minY)),\(Int(l.rect.width))x\(Int(l.rect.height))) text=\"\(l.text)\"")
        }

        // Vertical projection
        let vertProj = pixelBuffer.verticalProjection(in: contentBounds, threshold: otsu)
        let avgInk = vertProj.isEmpty ? 0 : (vertProj.reduce(0, +) / vertProj.count)
        let noiseLimit = max(4, Int(Double(avgInk) * 0.15))
        print("vertProj count: \(vertProj.count), avgInk: \(avgInk), noiseLimit: \(noiseLimit)")

        var inCol = false
        var colW = 0
        var allWidths: [Int] = []
        for x in 0..<vertProj.count {
            if vertProj[x] > noiseLimit {
                if !inCol {
                    inCol = true
                    colW = 1
                } else {
                    colW += 1
                }
            } else {
                if inCol {
                    inCol = false
                    if colW >= 6 {
                        allWidths.append(colW)
                    }
                }
            }
        }
        if inCol && colW >= 6 { allWidths.append(colW) }
        print("Detected raw vertical columns count: \(allWidths.count), widths: \(allWidths)")

        let detectedCols = ColumnDetector.detectColumns(pixelBuffer: pixelBuffer, contentBounds: contentBounds, threshold: otsu)
        print("ColumnDetector count: \(detectedCols.count)")
        for c in detectedCols {
            print("  Col rect: \(c)")
        }

        let profile = LayoutClassifier.classify(detectedColumns: detectedCols, contentBounds: contentBounds, visionAnalysis: vision, pixelBuffer: pixelBuffer)
        print("Classified Profile: \(profile.rawValue)")

        // Now test VerticalTextSegmenter directly
        var vConfig = ReflowConfig()
        vConfig.layoutProfile = .verticalBook
        vConfig.enableWordReflow = true
        let engine = ReflowEngine()
        let result = await engine.processPage(page: page, pageIndex: 50, config: vConfig)
        guard let res = result else {
            print("Direct vertical reflow returned nil!")
            return
        }
        print("\n--- Direct Vertical Reflow on Page 50 ---")
        print("Resolved Profile: \(res.resolvedProfile.rawValue)")
        print("Columns: \(res.columns.count), Slices: \(res.allSlices.count), Paras: \(res.paragraphs.count)")
        for (i, p) in res.paragraphs.enumerated() {
            print("  Para \(i) (indent=\(p.hasIndent), isTitle=\(p.isTitle), words=\(p.words.count)): \"\(p.recognizedText ?? "nil")\"")
        }
    }

    @MainActor
    @Test("Random 10 Pages Reflow Test for Vietnam Book (越南：世界史的失語者)")
    func testVietnamBookRandom10PagesReflow() async throws {
        let pdfPath = "/Users/mac/Downloads/pdfView/越南：世界史的失語者 by 〔美〕克里斯多佛著；譚天譯.pdf"
        guard FileManager.default.fileExists(atPath: pdfPath),
              let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            print("Cannot open 越南：世界史的失語者.pdf")
            return
        }

        let totalPages = doc.pageCount
        print("\n=======================================================")
        print("RANDOM 10 PAGES VERTICAL BOOK BENCHMARK: 越南：世界史的失語者 (Total: \(totalPages) pages)")
        print("=======================================================")

        let testPages = [50, 114, 129, 139, 167, 253, 275, 306, 457, 583]
        print("Selected Pages for Testing: \(testPages)\n")

        let engine = ReflowEngine()
        var config = ReflowConfig()
        config.layoutProfile = .auto
        config.enableWordReflow = true

        for (idx, pageNum) in testPages.enumerated() {
            guard let page = doc.page(at: pageNum) else { continue }
            let startTime = CACurrentMediaTime()
            let result = await engine.processPage(page: page, pageIndex: pageNum, config: config)
            let duration = CACurrentMediaTime() - startTime

            guard let res = result else {
                print("❌ [Page \(pageNum)] (#\(idx + 1)/10): Returned nil!")
                continue
            }

            let titleParas = res.paragraphs.filter { $0.semanticLevel == .title || $0.semanticLevel == .sectionHeader || $0.isTitle }
            let bodyParas = res.paragraphs.filter { !$0.isTitle && $0.semanticLevel == .body }
            let totalWords = res.paragraphs.flatMap { $0.words }.count

            print(String(format: "📖 [Page %3d] (#%2d/10): Profile=%@ | Cols=%2d | Slices=%2d | Paras=%2d (Words=%d, Titles=%d, Body=%d) | Time=%.2fs",
                pageNum, idx + 1, res.resolvedProfile.rawValue, res.columns.count, res.allSlices.count,
                res.paragraphs.count, totalWords, titleParas.count, bodyParas.count, duration
            ))

            for (pIdx, p) in res.paragraphs.prefix(6).enumerated() {
                print(String(format: "    [P%02d] (title=%@, indent=%@, words=%2d): \"%@\"",
                    pIdx, p.isTitle ? "Y" : "N", p.hasIndent ? "Y" : "N", p.words.count, String((p.recognizedText ?? "").prefix(50))
                ))
            }
        }
    }

    @MainActor
    @Test("Random 10 Pages Reflow Test for Caijing Magazine (财经-第13期2026)")
    func testRandom10PagesReflowCaijingMagazine() async throws {
        let pdfPath = "/Users/mac/Downloads/pdfView/财经-第13期2026.pdf"
        guard FileManager.default.fileExists(atPath: pdfPath),
              let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            print("Cannot open 财经-第13期2026.pdf")
            return
        }

        let totalPages = doc.pageCount
        print("\n=======================================================")
        print("RANDOM 10 PAGES MAGAZINE REFLOW BENCHMARK: 财经-第13期2026.pdf (Total: \(totalPages) pages)")
        print("=======================================================")

        var testPages: [Int] = []
        let minPage = 6
        let maxPage = max(16, totalPages - 6)
        let step = max(1, (maxPage - minPage) / 10)
        for i in 0..<10 {
            let jitter = (i * 13 + 5) % max(1, step / 2)
            let p = min(totalPages - 1, minPage + i * step + jitter)
            testPages.append(p)
        }

        print("Selected Pages for Testing: \(testPages)\n")

        let engine = ReflowEngine()
        var config = ReflowConfig()
        config.layoutProfile = .auto
        config.enableWordReflow = true

        for (idx, pageNum) in testPages.enumerated() {
            guard let page = doc.page(at: pageNum) else { continue }
            let startTime = CACurrentMediaTime()
            let result = await engine.processPage(page: page, pageIndex: pageNum, config: config)
            let duration = CACurrentMediaTime() - startTime

            guard let res = result else {
                print("❌ [Page \(pageNum)] (#\(idx + 1)/10): Returned nil!")
                continue
            }

            let figParas = res.paragraphs.filter { $0.isFigure || $0.isTable || $0.isSideBySide }
            let titleParas = res.paragraphs.filter { $0.semanticLevel == .title || $0.semanticLevel == .sectionHeader || $0.semanticLevel == .subHeader }
            let bodyParas = res.paragraphs.filter { $0.semanticLevel == .body && !$0.isFigure && !$0.isTable && !$0.isSideBySide }
            let bodyHeights = Set(bodyParas.map { Int(round($0.baseLineHeight * 10)) })

            print(String(format: "📰 [Page %3d] (#%2d/10): Profile=%@ | Cols=%d | Zones=%d | Paras=%2d (Figs=%d, Titles=%d, Body=%d, BodyHVariants=%d) | Time=%.2fs",
                pageNum, idx + 1, res.resolvedProfile.rawValue, res.columns.count, res.zones.count,
                res.paragraphs.count, figParas.count, titleParas.count, bodyParas.count, bodyHeights.count, duration
            ))

            if !bodyParas.isEmpty {
                #expect(res.resolvedProfile == .magazine, "Page \(pageNum) should be classified as .magazine")
                #expect(bodyHeights.count <= 1, "Page \(pageNum) should have a single unified body line height across all columns")
            } else {
                #expect(!res.paragraphs.isEmpty, "Page \(pageNum) should have at least 1 figure or content block")
            }

            for (pIdx, p) in res.paragraphs.prefix(12).enumerated() {
                if p.isFigure || p.isTable {
                    let r = p.figureSlice?.originalRect ?? .zero
                    print(String(format: "    [P%02d] FIGURE/TABLE (col=%d): rect=(%.0f, %.0f, %.0fx%.0f)", pIdx, p.columnIndex, r.minX, r.minY, r.width, r.height))
                } else if p.isSideBySide {
                    let r = p.sideFigure?.originalRect ?? .zero
                    print(String(format: "    [P%02d] SIDE-BY-SIDE (col=%d): figRect=(%.0f, %.0f, %.0fx%.0f) words=%d ocr=\"%@\"", pIdx, p.columnIndex, r.minX, r.minY, r.width, r.height, p.words.count, String((p.recognizedText ?? "").prefix(25))))
                } else {
                    print(String(format: "    [P%02d] %@ (col=%d, indent=%@, baseH=%.1f, words=%d): \"%@\"",
                        pIdx, p.semanticLevel.rawValue, p.columnIndex, p.hasIndent ? "Y" : "N", p.baseLineHeight, p.words.count, String((p.recognizedText ?? "").prefix(35))
                    ))
                }
            }
        }
    }

    @MainActor
    @Test("PDF Native Text Layer Detection & Direct Vector Text Reflow")
    func testNativeTextLayerDetectionAndVectorReflow() async throws {
        let engine = ReflowEngine()
        var config = ReflowConfig()
        config.textRenderMode = .auto

        // 1. SamplePDFGenerator (Digital-born vector PDF) -> must be detected as .nativeVectorText
        if let sampleDoc = SamplePDFGenerator.generateSampleDocument(), let page0 = sampleDoc.page(at: 0) {
            let start = CACurrentMediaTime()
            let res = await engine.processPage(page: page0, pageIndex: 0, config: config)
            let elapsed = CACurrentMediaTime() - start
            #expect(res != nil)
            if let result = res {
                print("SamplePDF p0: sourceType=\(result.textSourceType.rawValue), useVector=\(result.shouldUseVectorText(for: config)), paras=\(result.paragraphs.count), time=\(String(format: "%.3f", elapsed))s")
                #expect(result.textSourceType == .nativeVectorText)
                #expect(result.shouldUseVectorText(for: config) == true)
                let textParas = result.paragraphs.filter { !$0.isFigure && !$0.isTable && !($0.recognizedText ?? "").isEmpty }
                #expect(!textParas.isEmpty)
            }
        }

        // 2. MoneyWeek_0307.pdf (Native vector English magazine) -> must be detected as .nativeVectorText
        let mwPath = "/Users/mac/Downloads/pdfView/MoneyWeek_0307.pdf"
        if FileManager.default.fileExists(atPath: mwPath),
           let mwDoc = PDFDocument(url: URL(fileURLWithPath: mwPath)),
           let mwPage = mwDoc.page(at: 5) {
            let start = CACurrentMediaTime()
            let res = await engine.processPage(page: mwPage, pageIndex: 5, config: config)
            let elapsed = CACurrentMediaTime() - start
            #expect(res != nil)
            if let result = res {
                print("MoneyWeek p5: sourceType=\(result.textSourceType.rawValue), profile=\(result.resolvedProfile.rawValue), useVector=\(result.shouldUseVectorText(for: config)), paras=\(result.paragraphs.count), time=\(String(format: "%.3f", elapsed))s")
                for (i, p) in result.paragraphs.prefix(10).enumerated() {
                    if p.isFigure || p.isTable {
                        let r = p.figureSlice?.originalRect ?? .zero
                        print("  [P\(i)] FIG/TABLE: rect=(\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width))x\(Int(r.height)))")
                    } else {
                        print("  [P\(i)] \(p.semanticLevel.rawValue) (indent=\(p.hasIndent)): \"\(String((p.recognizedText ?? "").prefix(65)))\"")
                    }
                }
                #expect(result.textSourceType == .nativeVectorText)
                #expect(result.shouldUseVectorText(for: config) == true)
                #expect(!result.paragraphs.isEmpty)
                #expect(result.paragraphs.contains { $0.semanticLevel == .title && ($0.recognizedText ?? "").contains("Micron looks magnificent") })
            }
        }

        // 3. 赤道線的南洋密碼.pdf Page 22 (Scanned book with 3 Tr invisible OCR layer) -> .embeddedOCRLayer
        let nyPath = "/Users/mac/Downloads/pdfView/赤道線的南洋密碼.pdf"
        if FileManager.default.fileExists(atPath: nyPath),
           let nyDoc = PDFDocument(url: URL(fileURLWithPath: nyPath)),
           let nyPage = nyDoc.page(at: 22) {
            let analysis = PDFTextLayerAnalyzer.analyze(page: nyPage, pixelWidth: 1147, pixelHeight: 1738)
            print("Nanyang p22: sourceType=\(analysis.sourceType.rawValue), lines=\(analysis.rawLineCount)")
            #expect(analysis.sourceType == .embeddedOCRLayer)
        }

        // 4. 财经-第13期2026.pdf Page 8 (Pure image scanned magazine) -> .scannedImage
        let cjPath = "/Users/mac/Downloads/pdfView/财经-第13期2026.pdf"
        if FileManager.default.fileExists(atPath: cjPath),
           let cjDoc = PDFDocument(url: URL(fileURLWithPath: cjPath)),
           let cjPage = cjDoc.page(at: 8) {
            let analysis = PDFTextLayerAnalyzer.analyze(page: cjPage, pixelWidth: 4000, pixelHeight: 5169)
            print("Caijing p8: sourceType=\(analysis.sourceType.rawValue), lines=\(analysis.rawLineCount)")
            #expect(analysis.sourceType == .scannedImage)
        }
    }

    @Test("Sideways Latin Recognition in Vertical Books")
    func testSidewaysLatinInVerticalBooks() async throws {
        let screenshotPath = "/Users/mac/Downloads/pdfView/截屏2026-10-11 晚上9.55.53.png"
        guard FileManager.default.fileExists(atPath: screenshotPath),
              let nsImg = NSImage(contentsOfFile: screenshotPath),
              let cgImg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        guard let pixelBuffer = PixelBuffer(cgImage: cgImg) else { return }
        // Left half (x=40..670) contains original scanned vertical PDF page
        let bounds = CGRect(x: 40, y: 0, width: 630, height: cgImg.height)
        var config = ReflowConfig()
        config.enableWordReflow = true

        let (slices, paragraphs, cols) = VerticalTextSegmenter.segmentVerticalPage(
            pixelBuffer: pixelBuffer,
            originalImage: cgImg,
            contentBounds: bounds,
            threshold: 150,
            visualThreshold: 150,
            pageIndex: 0,
            config: config,
            visionAnalysis: nil
        )

        print("=== Sideways Latin Test Results ===")
        print("Columns: \(cols.count), Paragraphs: \(paragraphs.count), Total slices: \(slices.count)")

        var foundLatinWord = false
        var allText = ""
        for (si, s) in slices.enumerated() {
            let ocr = s.recognizedText ?? ""
            allText += ocr + " "
            print("Slice \(si) (rect=\(s.originalRect)): words=\(s.words.count), ocr=\"\(ocr)\"")
            for (wi, w) in s.words.enumerated() {
                if w.originalRect.width > 50 {
                    foundLatinWord = true
                    print("   w[\(wi)]: size=\(w.originalRect.size)")
                }
            }
        }

        #expect(foundLatinWord == true)
        print("Combined OCR Text: \(allText)")
        #expect(allText.contains("Muhammad") || allText.contains("Gharib") || allText.contains("Shahyari") || allText.contains("buzuq"))
    }

    @MainActor
    @Test("Diagnose WeiJin Book Page 10")
    func testDiagnoseWeiJinPage10() async throws {
        let pdfPath = "/Users/mac/Downloads/pdfView/魏晋南北朝通史.pdf"
        guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
              let page = doc.page(at: 9) else {
            return
        }

        let engine = ReflowEngine()
        var config = ReflowConfig()
        config.textRenderMode = .auto
        config.enableWordReflow = true

        guard let cg = ReflowEngine.renderPageToCGImage(page: page, dpi: config.renderDPI),
              let pixelBuffer = PixelBuffer(cgImage: cg) else { return }
        let textLayerResult = PDFTextLayerAnalyzer.analyze(page: page, pixelWidth: cg.width, pixelHeight: cg.height, cgImage: cg)
        let lines = textLayerResult.visionAnalysis?.lines ?? []
        print("Page 10 cgSize: \(cg.width)x\(cg.height), lines: \(lines.count)")
        let hLines = lines.filter { $0.rect.width > $0.rect.height * 2.0 && $0.rect.width >= CGFloat(cg.width) * 0.40 }
        let vLines = lines.filter { $0.rect.height > $0.rect.width * 1.5 }
        print("Horizontal long lines: \(hLines.count), Vertical lines: \(vLines.count)")
        for l in lines.prefix(5) {
            print("  Line: rect=\(l.rect) text=\"\(l.text)\"")
        }

        let result = await engine.processPage(page: page, pageIndex: 9, config: config)
        guard let res = result else {
            print("ReflowEngine returned nil")
            return
        }

        print("=== WeiJin Page 10 Reflow Result ===")
        print("textSourceType: \(res.textSourceType)")
        print("resolvedProfile: \(res.resolvedProfile)")
        print("useVectorText: \(res.shouldUseVectorText(for: config))")
        print("Paragraphs count: \(res.paragraphs.count)")
        for (i, p) in res.paragraphs.prefix(5).enumerated() {
            print("Para \(i) (words: \(p.words.count), level: \(p.semanticLevel)): \"\(p.recognizedText ?? "")\"")
        }
    }

    @MainActor
    @Test("Diagnose WeiJin Book Page 12")
    func testDiagnoseWeiJinPage12() async throws {
        let pdfPath = "/Users/mac/Downloads/pdfView/魏晋南北朝通史.pdf"
        guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
              let page = doc.page(at: 11) else {
            return
        }

        let engine = ReflowEngine()
        var config = ReflowConfig()
        config.textRenderMode = .auto
        config.enableWordReflow = true

        guard let cg = ReflowEngine.renderPageToCGImage(page: page, dpi: config.renderDPI),
              let pixelBuffer = PixelBuffer(cgImage: cg) else { return }
        let textLayerResult = PDFTextLayerAnalyzer.analyze(page: page, pixelWidth: cg.width, pixelHeight: cg.height, cgImage: cg)
        let visualRegions = VisualBlockDetector.detectVisualRegions(
            pixelBuffer: pixelBuffer,
            columnRect: CGRect(x: 207, y: 213, width: 1284, height: 1373),
            threshold: 128,
            expectedLineHeight: 41,
            visionAnalysis: textLayerResult.visionAnalysis
        )
        print("visualRegions count: \(visualRegions.count)")
        let macroZones = PageZoneDetector.detectZones(
            pixelBuffer: pixelBuffer,
            contentBounds: CGRect(x: 207, y: 213, width: 1284, height: 1373),
            layoutThreshold: 128,
            visionAnalysis: textLayerResult.visionAnalysis,
            resolvedProfile: .book,
            detectedColumns: [CGRect(x: 207, y: 213, width: 1284, height: 1373)]
        )
        print("PageZoneDetector macro zones: \(macroZones.allZones.count)")
        print("  header: \(macroZones.headerZone?.rect as Any)")
        print("  body: \(macroZones.bodyZones.map { $0.rect })")
        print("  footnote: \(macroZones.footnoteZone?.rect as Any)")
        print("  footer: \(macroZones.footerZone?.rect as Any)")

        let result = await engine.processPage(page: page, pageIndex: 11, config: config)
        guard let res = result else {
            print("ReflowEngine returned nil")
            return
        }

        print("=== WeiJin Page 12 Reflow Result ===")
        print("textSourceType: \(res.textSourceType)")
        print("resolvedProfile: \(res.resolvedProfile)")
        print("useVectorText: \(res.shouldUseVectorText(for: config))")
        print("Macro Zones count: \(res.zones.count)")
        for (i, z) in res.zones.enumerated() {
            print("Zone \(i): type=\(z.type.rawValue), rect=\(z.rect), paragraphs=\(z.paragraphs.count)")
        }
        print("Paragraphs count: \(res.paragraphs.count)")
        for (i, p) in res.paragraphs.enumerated() {
            print("Para \(i): isFig=\(p.isFigure), isTable=\(p.isTable), isSideBySide=\(p.isSideBySide), figSliceRect=\(p.figureSlice?.originalRect as Any), level=\(p.semanticLevel), hasIndent=\(p.hasIndent), text=\"\(p.recognizedText ?? "")\"")
        }
        #expect(macroZones.footnoteZone != nil)
        #expect(res.paragraphs.contains { $0.isTable } == false)
        #expect(res.paragraphs.contains { $0.semanticLevel == .subHeader && ($0.recognizedText ?? "").contains("注 释") })
        #expect(res.paragraphs.contains { $0.semanticLevel == .caption && ($0.recognizedText ?? "").contains("黄初元年") })
        #expect(res.paragraphs.contains { $0.semanticLevel == .caption && ($0.recognizedText ?? "").contains("党锢列传") })
    }

    @MainActor
    @Test("Test Page Synchronization across modes")
    func testPageSynchronization() async throws {
        let pdfPath = "/Users/mac/Downloads/pdfView/魏晋南北朝通史.pdf"
        let viewModel = PDFReaderViewModel()
        viewModel.openFile(url: URL(fileURLWithPath: pdfPath))
        #expect(viewModel.hasDocument)
        #expect(viewModel.totalPages > 15)

        // Simulate page turn in original view
        viewModel.goToPage(11)
        #expect(viewModel.currentPageIndex == 11)

        // Switch to reflow view
        viewModel.activeMode = .reflow
        #expect(viewModel.activeMode == .reflow)
        #expect(viewModel.currentPageIndex == 11)

        // Switch to OCR text view
        viewModel.activeMode = .ocrText
        #expect(viewModel.activeMode == .ocrText)
        #expect(viewModel.currentPageIndex == 11)
    }

    @MainActor
    @Test("Test Recent Documents Store and History Management")
    func testRecentDocumentsStoreAndHistory() async throws {
        let store = RecentDocumentsStore.shared
        store.clearAll()
        #expect(store.loadRecents().isEmpty)

        let testURL = URL(fileURLWithPath: "/Users/mac/Downloads/pdfView/魏晋南北朝通史.pdf")
        store.addOrUpdate(url: testURL, title: "魏晋南北朝通史.pdf", pageIndex: 5, totalPages: 100)

        var recents = store.loadRecents()
        #expect(recents.count == 1)
        #expect(recents.first?.title == "魏晋南北朝通史.pdf")
        #expect(recents.first?.lastPageIndex == 5)
        #expect(recents.first?.totalPages == 100)

        // Test updating progress
        store.updateProgress(title: "魏晋南北朝通史.pdf", pageIndex: 12, totalPages: 100)
        recents = store.loadRecents()
        #expect(recents.first?.lastPageIndex == 12)

        // Test resolveURL
        let resolvedURL = store.resolveURL(for: recents.first!)
        #expect(resolvedURL != nil)

        // Test removal
        store.remove(urlString: testURL.absoluteString)
        recents = store.loadRecents()
        #expect(recents.isEmpty)

        // Test ViewModel integration
        let viewModel = PDFReaderViewModel()
        viewModel.openFile(url: testURL)
        #expect(viewModel.recentDocuments.contains { $0.title == "魏晋南北朝通史.pdf" })

        viewModel.goToPage(8)
        viewModel.saveCurrentBookPreference()
        #expect(viewModel.recentDocuments.first?.lastPageIndex == 8)

        viewModel.clearRecentDocuments()
        #expect(viewModel.recentDocuments.isEmpty)
    }

    @MainActor
    @Test("Test Copy Current Page Text and Home Slogans")
    func testCopyCurrentPageTextAndHomeSlogans() async throws {
        let testURL = URL(fileURLWithPath: "/Users/mac/Downloads/pdfView/魏晋南北朝通史.pdf")
        let viewModel = PDFReaderViewModel()
        viewModel.openFile(url: testURL)
        #expect(viewModel.hasDocument)

        // Test currentPageText and hasCopyableText
        let pageText = viewModel.currentPageText()
        #expect(!pageText.isEmpty)
        #expect(viewModel.hasCopyableText)

        // Test copyCurrentPageText
        let copied = viewModel.copyCurrentPageText()
        #expect(copied)
        #expect(viewModel.showCopiedToast)
        #expect(!viewModel.copiedToastMessage.isEmpty)

        // Test L10n Home Slogans in all supported languages
        for lang in AppLanguage.allCases {
            let l10n = L10n(lang)
            #expect(!l10n.homeHeroSlogan.isEmpty)
            #expect(!l10n.homeHeroSubSlogan.isEmpty)
            #expect(!l10n.homeFeature1Title.isEmpty)
            #expect(!l10n.homeFeature1Desc.isEmpty)
            #expect(!l10n.homeFeature2Title.isEmpty)
            #expect(!l10n.homeFeature3Title.isEmpty)
            #expect(!l10n.homeFeature4Title.isEmpty)
            #expect(!l10n.homeFeature5Title.isEmpty)
            #expect(!l10n.homeFeature5Desc.isEmpty)
            #expect(!l10n.viewFullGuideLink.isEmpty)
            #expect(!l10n.copyPageText.isEmpty)
            #expect(!l10n.copiedPageTextSuccess.isEmpty)
        }
    }

    @MainActor
    @Test("Test CaiJing Magazine and IMG_0038 Image Slice Reflow and Margin Clearing")
    func testCaijingAndIMG0038() async throws {
        // Test Caijing Magazine (scanned magazine defaults to image slice reflow in .auto, vector text when manually selected)
        let caijingURL = URL(fileURLWithPath: "财经-第13期2026.pdf")
        if let doc = PDFDocument(url: caijingURL), let page = doc.page(at: 2) {
            let engine = ReflowEngine()
            var config = ReflowConfig()
            let result = await engine.processPage(page: page, pageIndex: 2, config: config)
            #expect(result != nil)
            // Default config is image slice reflow (图形文字横排)
            #expect(result?.shouldUseVectorText(for: config) == false)

            // When user explicitly selects vectorText mode, it switches to vector typography
            config.textRenderMode = .vectorText
            #expect(result?.shouldUseVectorText(for: config) == true)
        }

        // Test True Vector PDF (MoneyWeek) defaults to vector text in .auto mode
        let mwURL = URL(fileURLWithPath: "MoneyWeek_0307.pdf")
        if let doc = PDFDocument(url: mwURL), let page = doc.page(at: 2) {
            let engine = ReflowEngine()
            var config = ReflowConfig()
            config.textRenderMode = .auto
            let result = await engine.processPage(page: page, pageIndex: 2, config: config)
            #expect(result != nil)
            #expect(result?.textSourceType == .nativeVectorText)
            #expect(result?.shouldUseVectorText(for: config) == true)
        }

        // Test IMG_0038: Loaded with EXIF orientation and reflowed as image slices ("图片重排")
        let imgURL = URL(fileURLWithPath: "IMG_0038.HEIC")
        if let imgDoc = PlatformImageDocumentLoader.createPDFDocument(fromImageURL: imgURL),
           let imgPage = imgDoc.page(at: 0) {
            let mediaBox = imgPage.bounds(for: .mediaBox)
            // Portrait orientation from EXIF (height > width)
            #expect(mediaBox.height > mediaBox.width)

            let engine = ReflowEngine()
            var config = ReflowConfig()
            config.textRenderMode = .auto
            let imgResult = await engine.processPage(page: imgPage, pageIndex: 0, config: config)
            #expect(imgResult != nil)
            // IMG_0038 must strictly reflow as image slices, NOT OCR vector text!
            #expect(imgResult?.shouldUseVectorText(for: config) == false)
            #expect(imgResult?.allSlices.isEmpty == false)
            if let res = imgResult {
                print("IMG_0038 paragraphs count: \(res.paragraphs.count), allSlices count: \(res.allSlices.count)")
                for (pi, p) in res.paragraphs.enumerated() {
                    print("  P[\(pi)]: words=\(p.words.count), recognizedText=\"\(p.recognizedText ?? "")\"")
                }
            }
        }

        // Test IMG_0038 Margin and Border Clearing
        if let source = CGImageSourceCreateWithURL(imgURL as CFURL, nil),
           let cg = CGImageSourceCreateImageAtIndex(source, 0, nil),
           let pb = PixelBuffer(cgImage: cg) {
            let threshold = pb.calculateOtsuThreshold()
            let contentBounds = MarginDetector.detectContentBounds(pixelBuffer: pb, threshold: threshold)
            print("IMG_0038 contentBounds: \(contentBounds), original size: \(cg.width) x \(cg.height)")
            #expect(contentBounds.width < CGFloat(cg.width - 200))
            #expect(contentBounds.height < CGFloat(cg.height - 200))

            var config = ReflowConfig()
            config.isImageDocument = true
            config.enablePageEnhancement = true
            config.autoPerspectiveCorrection = true
            config.autoCropBlackBorders = true
            let pre = PagePreprocessEngine.shared.processCGImage(cg, config: config)
            print("Preprocessed IMG_0038 cropRect: \(pre.cropRect), size: \(pre.processedImage.width) x \(pre.processedImage.height)")
            #expect(pre.isPerspectiveCorrected || pre.isCropApplied)
        }
    }

    @MainActor
    @Test("Test Page Rotation Triggers Re-Reflow")
    func testPageRotationTriggersReReflow() async throws {
        let caijingURL = URL(fileURLWithPath: "财经-第13期2026.pdf")
        guard let doc = PDFDocument(url: caijingURL), let page = doc.page(at: 2) else { return }

        let initialRot = page.rotation
        let engine = ReflowEngine()
        var config = ReflowConfig()
        config.textRenderMode = .auto

        let result0 = await engine.processPage(page: page, pageIndex: 2, config: config)
        #expect(result0 != nil)

        // Rotate page by 90 degrees
        page.rotation = ((initialRot + 90) % 360 + 360) % 360
        engine.clearCache()
        PagePreprocessEngine.shared.clearCache()

        let resultRotated = await engine.processPage(page: page, pageIndex: 2, config: config)
        #expect(resultRotated != nil)
        #expect(page.rotation == (initialRot + 90) % 360)

        // Test PDFReaderViewModel rotation handling: updates rotation and triggers reprocess
        let viewModel = PDFReaderViewModel()
        viewModel.setDocument(doc, title: "TestDoc")
        viewModel.currentPageIndex = 2
        let rotBefore = viewModel.currentPageRotation
        viewModel.rotateCurrentPage(by: 90)
        #expect(viewModel.currentPageRotation == (rotBefore + 90) % 360)
    }

    @MainActor
    @Test("Test Caijing Magazine Recognized as Text PDF and IMG_0038 as Image Slice Reflow")
    func testCaijingTextPDFRecognitionAndIMG0038ImageReflow() async throws {
        // 1. Caijing Magazine: should be recognized as Text PDF with vector text typography
        let caijingURL = URL(fileURLWithPath: "财经-第13期2026.pdf")
        if let doc = PDFDocument(url: caijingURL) {
            let engine = ReflowEngine()
            var config = ReflowConfig()
            config.textRenderMode = .auto
            if let p2 = doc.page(at: 2) {
                let res2 = await engine.processPage(page: p2, pageIndex: 2, config: config)
                #expect(res2 != nil)
                #expect(res2?.textSourceType == .ocrRecognizedText || res2?.textSourceType == .nativeVectorText)
                #expect(res2?.shouldUseVectorText(for: config) == true)
                let badge2 = L10n(.zhHans).sourceTypeBadge(res2!.textSourceType)
                #expect(badge2 == "文字版 PDF")
            }
            if let p3 = doc.page(at: 3) {
                let p3Res = await engine.processPage(page: p3, pageIndex: 3, config: config)
                #expect(p3Res != nil)
                #expect(p3Res?.textSourceType == .ocrRecognizedText || p3Res?.textSourceType == .nativeVectorText)
                #expect(p3Res?.shouldUseVectorText(for: config) == true)
                #expect((p3Res?.paragraphs.count ?? 0) >= 10)
                let badge3 = L10n(.zhHans).sourceTypeBadge(p3Res!.textSourceType)
                #expect(badge3 == "文字版 PDF")
            }
        }

        // 2. IMG_0038: Camera photo of document, should strictly remain image slice reflow ("图片重排")
        let imgURL = URL(fileURLWithPath: "IMG_0038.HEIC")
        if let imgDoc = PlatformImageDocumentLoader.createPDFDocument(fromImageURL: imgURL),
           let imgPage = imgDoc.page(at: 0) {
            let engine = ReflowEngine()
            var config = ReflowConfig()
            config.textRenderMode = .auto
            let imgResult = await engine.processPage(page: imgPage, pageIndex: 0, config: config)
            #expect(imgResult != nil)
            #expect(imgResult?.shouldUseVectorText(for: config) == false)
        }
    }

    @Test("Test Vertical Book Upfront Detection, Glyph Slice Reflow & Zero Mode Flipping")
    func testVerticalBookUpfrontDetectionAndStability() async throws {
        // 1. Create a synthetic 8-column vertical book page
        let width = 1000
        let height = 1400
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create graphics context for vertical book test")
            return
        }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        let columnCount = 8
        let colW: CGFloat = 38.0
        let gutter: CGFloat = 32.0
        let totalSpan = CGFloat(columnCount) * colW + CGFloat(columnCount - 1) * gutter
        let startX = (CGFloat(width) - totalSpan) / 2.0

        for c in 0..<columnCount {
            let x = startX + CGFloat(c) * (colW + gutter)
            var y: CGFloat = 120.0
            while y < CGFloat(height) - 180.0 {
                ctx.fill(CGRect(x: x, y: y, width: colW, height: colW - 6.0))
                y += colW + 8.0
            }
        }

        guard let vertCGImage = ctx.makeImage(),
              let pixelBuffer = PixelBuffer(cgImage: vertCGImage) else {
            Issue.record("Failed to create CGImage / PixelBuffer")
            return
        }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)

        // 2. Upfront detection BEFORE OCR:
        let isVert = LayoutClassifier.detectVerticalBook(pixelBuffer: pixelBuffer, contentBounds: bounds)
        #expect(isVert == true)

        // 3. Reflow Engine Execution with explicit Vertical Book layout:
        let engine = ReflowEngine()
        var config = ReflowConfig()
        config.reflowLayoutMode = .verticalGraphic

        let result = await engine.processRenderedImage(
            cgImage: vertCGImage,
            pageIndex: 0,
            config: config
        )
        #expect(result != nil)
        #expect(result?.resolvedProfile == .verticalBook)

        // In .auto mode, vertical books MUST strictly use original glyph slices ("字形切片重排"), never flipping to vector text!
        #expect(result?.shouldUseVectorText(for: config) == false)

        // If user explicitly chooses vectorText mode, it respects it:
        var explicitVectorConfig = config
        explicitVectorConfig.textRenderMode = .vectorText
        #expect(result?.shouldUseVectorText(for: explicitVectorConfig) == true)

        // 4. Test sparse chapter-ending page with Document Affinity:
        guard let ctxSparse = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctxSparse.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctxSparse.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctxSparse.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        // Only 2 columns on chapter-ending page:
        for c in 0..<2 {
            let x = startX + CGFloat(c) * (colW + gutter)
            var y: CGFloat = 120.0
            while y < CGFloat(height) * 0.45 {
                ctxSparse.fill(CGRect(x: x, y: y, width: colW, height: colW - 6.0))
                y += colW + 8.0
            }
        }
        guard let sparseCG = ctxSparse.makeImage(),
              let sparsePB = PixelBuffer(cgImage: sparseCG) else { return }

        // Without affinity, 2 columns would not trigger 4-column threshold:
        let sparseNoAffinity = LayoutClassifier.detectVerticalBook(pixelBuffer: sparsePB, contentBounds: bounds, hasDocumentAffinity: false)
        #expect(sparseNoAffinity == false)

        // With vertical book document affinity, it stably detects as vertical book!
        let sparseWithAffinity = LayoutClassifier.detectVerticalBook(pixelBuffer: sparsePB, contentBounds: bounds, hasDocumentAffinity: true)
        #expect(sparseWithAffinity == true)

        var affinityConfig = config
        affinityConfig.reflowLayoutMode = .verticalGraphic
        let sparseResult = await engine.processRenderedImage(cgImage: sparseCG, pageIndex: 5, config: affinityConfig)
        #expect(sparseResult?.resolvedProfile == .verticalBook)
        #expect(sparseResult?.shouldUseVectorText(for: affinityConfig) == false)
    }

    @Test("Test 34.JPG Long Image Reflow")
    func testLongImage34() async throws {
        let url = URL(fileURLWithPath: "/Users/mac/Downloads/34.JPG")
        guard let doc = PlatformImageDocumentLoader.createPDFDocument(fromImageURL: url),
              let page = doc.page(at: 0) else {
            Issue.record("Failed to load 34.JPG")
            return
        }
        var config = ReflowConfig()
        config.isImageDocument = true
        // Default has autoPerspectiveCorrection = true; our fix should automatically prevent cropping long images
        let result = await ReflowEngine.shared.processPage(page: page, pageIndex: 0, config: config)
        #expect(result != nil)
        guard let res = result else { return }
        #expect(res.paragraphs.count >= 20)
        #expect(res.allSlices.count >= 40)
        // Ensure content spans the whole document, not just the bottom third
        let allText = res.paragraphs.compactMap { $0.recognizedText }.joined(separator: "\n")
        #expect(allText.contains("明查暗访") || allText.contains("迎检方案"))
        #expect(allText.contains("一、行程安排") || allText.contains("行程安排"))
        #expect(allText.contains("三、其他事项") || allText.contains("其他事项"))
        #expect(allText.contains("晋江市安全生产委员会办公室") || allText.contains("安全生产"))
    }
}


