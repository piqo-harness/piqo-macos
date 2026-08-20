// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Piqo",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Piqo", targets: ["Piqo"])],
    dependencies: [.package(path: "Packages/PiqoKit")],
    targets: [
        .executableTarget(
            name: "Piqo",
            dependencies: [
                .product(name: "PiqoProtocol", package: "PiqoKit"),
                .product(name: "PiqoRuntime", package: "PiqoKit"),
                .product(name: "PiqoData", package: "PiqoKit"),
                .product(name: "PiqoPresentation", package: "PiqoKit")
            ],
            path: "Piqo/Sources"
        )
    ]
)
