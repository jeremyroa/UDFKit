// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "UDFKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "UDFKit",
            targets: ["UDFKit"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            "602.0.0"..<"605.0.0"
        ),
        .package(
            url: "https://github.com/realm/SwiftLint.git",
            from: "0.57.0"
        ),
        .package(
            url: "https://github.com/nicklockwood/SwiftFormat.git",
            from: "0.54.0"
        ),
    ],
    targets: [
        .macro(
            name: "UDFKitMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "UDFKit",
            dependencies: ["UDFKitMacros"]
        ),
        .testTarget(
            name: "UDFKitTests",
            dependencies: ["UDFKit"]
        ),
        .testTarget(
            name: "UDFKitMacrosTests",
            dependencies: [
                "UDFKitMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
