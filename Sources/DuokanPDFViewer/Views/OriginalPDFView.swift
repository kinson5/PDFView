import SwiftUI
import PDFKit

#if canImport(AppKit)
import AppKit

final class DuokanPDFKitView: PDFView {
    var onPageChange: ((Int) -> Void)?
    var isProgrammaticScroll: Bool = false

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        notifyPageChangeIfNeeded()
    }

    override func swipe(with event: NSEvent) {
        // macOS trackpad three-finger or two-finger swipe gestures
        if event.deltaX > 0 || event.deltaY > 0 {
            goToPreviousPage(nil)
        } else if event.deltaX < 0 || event.deltaY < 0 {
            goToNextPage(nil)
        } else {
            super.swipe(with: event)
        }
        notifyPageChangeIfNeeded()
    }

    func notifyPageChangeIfNeeded() {
        guard !isProgrammaticScroll else { return }
        guard let page = currentPage, let doc = document else { return }
        let idx = doc.index(for: page)
        if idx != NSNotFound {
            onPageChange?(idx)
        }
    }
}

public struct OriginalPDFView: NSViewRepresentable {
    @ObservedObject var viewModel: PDFReaderViewModel

    public init(viewModel: PDFReaderViewModel) {
        self.viewModel = viewModel
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    public class Coordinator: NSObject {
        var parent: OriginalPDFView
        var isUpdatingFromViewModel = false
        var observer: Any?

        var lastRotationVersion: Int = 0

        init(_ parent: OriginalPDFView) {
            self.parent = parent
        }

        func setupObserver(for pdfView: PDFView) {
            if let obs = observer {
                NotificationCenter.default.removeObserver(obs)
            }
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self, weak pdfView] _ in
                Task { @MainActor [weak self, weak pdfView] in
                    guard let self = self, let pdfView = pdfView else { return }
                    guard !self.isUpdatingFromViewModel else { return }
                    if let page = pdfView.currentPage, let doc = pdfView.document {
                        let pageIdx = doc.index(for: page)
                        if pageIdx != NSNotFound && pageIdx != self.parent.viewModel.currentPageIndex {
                            self.parent.viewModel.goToPage(pageIdx)
                        }
                    }
                }
            }
        }

        func cleanup() {
            if let obs = observer {
                NotificationCenter.default.removeObserver(obs)
                observer = nil
            }
        }
    }

    public static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    public func makeNSView(context: Context) -> PDFView {
        let pdfView = DuokanPDFKitView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor.windowBackgroundColor
        pdfView.onPageChange = { [weak viewModel] pageIdx in
            if let vm = viewModel, vm.currentPageIndex != pageIdx {
                vm.goToPage(pageIdx)
            }
        }
        context.coordinator.setupObserver(for: pdfView)
        return pdfView
    }

    public func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== viewModel.document {
            pdfView.document = viewModel.document
            context.coordinator.setupObserver(for: pdfView)
        }

        if abs(pdfView.scaleFactor - viewModel.zoomScale) > 0.01 {
            if abs(viewModel.zoomScale - 1.0) < 0.01 {
                pdfView.autoScales = true
            } else {
                pdfView.autoScales = false
                pdfView.scaleFactor = viewModel.zoomScale
            }
        }

        if context.coordinator.lastRotationVersion != viewModel.pageRotationVersion {
            context.coordinator.lastRotationVersion = viewModel.pageRotationVersion
            pdfView.layoutDocumentView()
            if let doc = viewModel.document, viewModel.currentPageIndex < doc.pageCount,
               let targetPage = doc.page(at: viewModel.currentPageIndex) {
                pdfView.go(to: targetPage)
            }
        }

        if let doc = viewModel.document,
           viewModel.currentPageIndex < doc.pageCount,
           let targetPage = doc.page(at: viewModel.currentPageIndex),
           pdfView.currentPage != targetPage {
            context.coordinator.isUpdatingFromViewModel = true
            (pdfView as? DuokanPDFKitView)?.isProgrammaticScroll = true
            pdfView.go(to: targetPage)
            DispatchQueue.main.async {
                context.coordinator.isUpdatingFromViewModel = false
                (pdfView as? DuokanPDFKitView)?.isProgrammaticScroll = false
            }
        }
    }
}

#elseif canImport(UIKit)
import UIKit

public struct OriginalPDFView: UIViewRepresentable {
    @ObservedObject var viewModel: PDFReaderViewModel

    public init(viewModel: PDFReaderViewModel) {
        self.viewModel = viewModel
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    public class Coordinator: NSObject {
        var parent: OriginalPDFView
        var isUpdatingFromViewModel = false
        var observer: Any?
        var lastRotationVersion: Int = 0

        init(_ parent: OriginalPDFView) {
            self.parent = parent
        }

        func setupObserver(for pdfView: PDFView) {
            if let obs = observer {
                NotificationCenter.default.removeObserver(obs)
            }
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self, weak pdfView] _ in
                Task { @MainActor [weak self, weak pdfView] in
                    guard let self = self, let pdfView = pdfView else { return }
                    guard !self.isUpdatingFromViewModel else { return }
                    if let page = pdfView.currentPage, let doc = pdfView.document {
                        let pageIdx = doc.index(for: page)
                        if pageIdx != NSNotFound && pageIdx != self.parent.viewModel.currentPageIndex {
                            self.parent.viewModel.goToPage(pageIdx)
                        }
                    }
                }
            }
        }

        func cleanup() {
            if let obs = observer {
                NotificationCenter.default.removeObserver(obs)
                observer = nil
            }
        }
    }

    public static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    public func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.backgroundColor = UIColor.systemBackground
        context.coordinator.setupObserver(for: pdfView)
        return pdfView
    }

    public func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== viewModel.document {
            pdfView.document = viewModel.document
            pdfView.autoScales = true
            context.coordinator.setupObserver(for: pdfView)
        }

        if abs(pdfView.scaleFactor - viewModel.zoomScale) > 0.01 {
            if abs(viewModel.zoomScale - 1.0) < 0.01 {
                pdfView.autoScales = true
            } else {
                pdfView.autoScales = false
                pdfView.scaleFactor = viewModel.zoomScale
            }
        }

        if context.coordinator.lastRotationVersion != viewModel.pageRotationVersion {
            context.coordinator.lastRotationVersion = viewModel.pageRotationVersion
            pdfView.layoutDocumentView()
            if let doc = viewModel.document, viewModel.currentPageIndex < doc.pageCount,
               let targetPage = doc.page(at: viewModel.currentPageIndex) {
                pdfView.go(to: targetPage)
            }
        }

        if let doc = viewModel.document,
           viewModel.currentPageIndex < doc.pageCount,
           let targetPage = doc.page(at: viewModel.currentPageIndex),
           pdfView.currentPage != targetPage {
            context.coordinator.isUpdatingFromViewModel = true
            pdfView.go(to: targetPage)
            DispatchQueue.main.async {
                context.coordinator.isUpdatingFromViewModel = false
            }
        }
    }
}
#endif
