// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "iOSMcuManagerLibrary",
    platforms: [.iOS(.v13), .macOS(.v10_14)],
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
            .exact("0.5.0")
        ),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git",
            .upToNextMajor(from: "0.9.0")
        ),
        .package(url: "https://github.com/NordicSemiconductor/IOS-BLE-Library",
            .branchItem("main")
        ),
        .package(url: "https://github.com/NordicPlayground/IOS-Common-Libraries",
            .branchItem("main")
        )
    ],
    targets: [
        .target(
            name: "iOSMcuManagerLibrary",
            dependencies: ["SwiftCBOR", "ZIPFoundation"],
            path: "iOSMcuManagerLibrary/Source",
            exclude: ["Info.plist"]
        ),
        .target(
            name: "iOSOtaLibrary",
            dependencies: [
                .product(name: "iOS-BLE-Library-Mock", package: "IOS-BLE-Library"),
                .product(name: "iOSCommonLibraries", package: "IOS-Common-Libraries")
            ],
            path: "iOSOtaLibrary/Source"
        )
    ]
)
