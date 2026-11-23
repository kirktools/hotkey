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
    dependencies: [.package(path: "Vendor/KirkTranslation")],
    targets: [
        .target(name: "PluginSDK"),
        .target(name: "HotkeyCore", dependencies: ["PluginSDK"], exclude: ["Updates/LICENSE-Screenshot"]),
        .target(name: "AppSwitchPlugin", dependencies: ["PluginSDK"]),
        .executableTarget(name: "HotkeyApp", dependencies: ["HotkeyCore", "AppSwitchPlugin", "PluginSDK"]),
        .executableTarget(name: "ExamplePlugin", dependencies: ["PluginSDK"]),
        .executableTarget(name: "TranslationPlugin", dependencies: ["PluginSDK", "KirkTranslation"]),
        .executableTarget(name: "ProtocolFixture", dependencies: ["PluginSDK"], path: "Tests/Fixtures/ProtocolFixture"),
        .testTarget(name: "HotkeyCoreTests", dependencies: ["HotkeyCore", "PluginSDK", "ProtocolFixture"]),
    ],
    swiftLanguageModes: [.v5]
)
