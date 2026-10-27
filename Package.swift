// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hotkey",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Hotkey", targets: ["HotkeyApp"]),
        .executable(name: "ExamplePlugin", targets: ["ExamplePlugin"]),
        .library(name: "PluginSDK", targets: ["PluginSDK"]),
    ],
    targets: [
        .target(name: "PluginSDK"),
        .target(name: "HotkeyCore", dependencies: ["PluginSDK"]),
        .target(name: "AppSwitchPlugin", dependencies: ["PluginSDK"]),
        .executableTarget(name: "HotkeyApp", dependencies: ["HotkeyCore", "AppSwitchPlugin", "PluginSDK"]),
        .executableTarget(name: "ExamplePlugin", dependencies: ["PluginSDK"]),
        .executableTarget(name: "ProtocolFixture", dependencies: ["PluginSDK"], path: "Tests/Fixtures/ProtocolFixture"),
        .testTarget(name: "HotkeyCoreTests", dependencies: ["HotkeyCore", "PluginSDK", "ProtocolFixture"]),
    ],
    swiftLanguageModes: [.v5]
)
