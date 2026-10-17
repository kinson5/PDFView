// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DuokanPDFViewer",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    targets: [
        .executableTarget(
            name: "DuokanPDFViewer",
            path: "Sources/DuokanPDFViewer"
        ),
        .testTarget(
            name: "DuokanPDFViewerTests",
            dependencies: ["DuokanPDFViewer"],
            path: "Tests/DuokanPDFViewerTests"
        ),
    ]
)
