// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ListrDesktop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ListrDesktop", targets: ["ListrDesktop"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .executableTarget(
            name: "ListrDesktop",
            dependencies: [
                "ZIPFoundation"
            ],
            path: "Sources/ListrDesktop"
        ),
    ]
)
