// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hotkey",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Hotkey", targets: ["HotkeyApp"]),
        .executable(name: "ExamplePlugin", targets: ["ExamplePlugin"]),
        .executable(name: "TranslationPlugin", targets: ["TranslationPlugin"]),
        .library(name: "PluginSDK", targets: ["PluginSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kirktools/pkg-logging.git", exact: "0.1.0"),
        .package(url: "https://github.com/kirktools/pkg-translation.git", exact: "0.1.0"),
    ],
    targets: [
        .target(name: "PluginSDK"),
        .target(name: "HotkeyDiagnostics", dependencies: [.product(name: "KirkLogging", package: "pkg-logging")]),
        .target(name: "HotkeyCore", dependencies: ["PluginSDK", "HotkeyDiagnostics"], exclude: ["Updates/LICENSE-Screenshot"]),
        .target(name: "AppSwitchPlugin", dependencies: ["PluginSDK", "HotkeyDiagnostics"]),
        .executableTarget(name: "HotkeyApp", dependencies: ["HotkeyCore", "AppSwitchPlugin", "PluginSDK", "HotkeyDiagnostics"]),
        .executableTarget(name: "ExamplePlugin", dependencies: ["PluginSDK"]),
        .executableTarget(name: "TranslationPlugin", dependencies: [
            "PluginSDK", "HotkeyDiagnostics",
            .product(name: "KirkTranslation", package: "pkg-translation"),
            .product(name: "KirkTranslationUI", package: "pkg-translation"),
        ]),
        .executableTarget(name: "ProtocolFixture", dependencies: ["PluginSDK"], path: "Tests/Fixtures/ProtocolFixture"),
        .testTarget(name: "HotkeyCoreTests", dependencies: ["HotkeyCore", "HotkeyDiagnostics", "PluginSDK", "ProtocolFixture"]),
    ],
    swiftLanguageModes: [.v5]
)
