// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenSize",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DisplayCatalog", targets: ["DisplayCatalog"]),
        .library(name: "DisplayRuntime", targets: ["DisplayRuntime"]),
        .executable(name: "ScreenSize", targets: ["ScreenSizeApp"]),
        .executable(name: "screen-size-inspect", targets: ["ScreenSizeInspect"])
    ],
    targets: [
        .target(name: "DisplayCatalog"),
        .target(name: "DisplayRuntime", dependencies: ["DisplayCatalog"]),
        .executableTarget(name: "ScreenSizeApp", dependencies: ["DisplayCatalog", "DisplayRuntime"]),
        .executableTarget(name: "ScreenSizeInspect", dependencies: ["DisplayCatalog"]),
        .testTarget(name: "DisplayCatalogTests", dependencies: ["DisplayCatalog"])
    ]
)
