// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KirkTranslation",
    platforms: [.macOS(.v14)],
    products: [.library(name: "KirkTranslation", targets: ["KirkTranslation"])],
    targets: [.target(name: "KirkTranslation")],
    swiftLanguageModes: [.v5]
)
