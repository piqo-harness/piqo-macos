// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PiqoKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PiqoProtocol", targets: ["PiqoProtocol"]),
        .library(name: "PiqoRuntime", targets: ["PiqoRuntime"]),
        .library(name: "PiqoData", targets: ["PiqoData"]),
        .library(name: "PiqoPresentation", targets: ["PiqoPresentation"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.7.0"),
        .package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-toml.git", from: "0.7.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.7.0")
    ],
    targets: [
        .target(name: "PiqoProtocol"),
        .target(name: "PiqoRuntime", dependencies: ["PiqoProtocol"]),
        .target(
            name: "PiqoData",
            dependencies: [
                "PiqoProtocol",
                .product(name: "TOML", package: "swift-toml"),
                .product(name: "TreeSitterTOML", package: "tree-sitter-toml")
            ]
        ),
        .target(
            name: "PiqoPresentation",
            dependencies: [
                "PiqoProtocol",
                "PiqoRuntime",
                "PiqoData",
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .testTarget(name: "PiqoProtocolTests", dependencies: ["PiqoProtocol"]),
        .testTarget(name: "PiqoRuntimeTests", dependencies: ["PiqoRuntime"]),
        .testTarget(name: "PiqoDataTests", dependencies: ["PiqoData"])
    ]
)
