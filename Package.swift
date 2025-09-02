// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "iOSMcuManagerLibrary",
    platforms: [.iOS(.v12), .macOS(.v10_13)],
    products: [
        .library(
            name: "iOSMcuManagerLibrary",
            targets: ["iOSMcuManagerLibrary"]
        ),
        .library(
            name: "iOSOtaLibrary",
            targets: ["iOSOtaLibrary"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/valpackett/SwiftCBOR.git",
            .exact("0.4.7")
        ),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git",
            .upToNextMajor(from: "0.9.0")
        )
    ],
    targets: [
        .target(
            name: "iOSMcuManagerLibrary",
            dependencies: ["SwiftCBOR", "ZIPFoundation"],
            path: "Source",
            exclude: ["Info.plist"]
        ),
        .target(
            name: "iOSOtaLibrary",
            path: "iOSOtaLibrary/Source"
        )
    ]
)
