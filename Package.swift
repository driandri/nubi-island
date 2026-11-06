// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "NotchLogic", platforms: [.macOS(.v14)], products: [.library(name: "NotchLogic", targets: ["NotchLogic"])], targets: [
    .target(name: "NotchLogic", path: "Notch/Core", exclude: ["DisplayManager.swift", "NotchWindowManager.swift", "LockScreenOverlay.swift"], sources: ["InteractionState.swift", "NotchConfiguration.swift", "NotchStateController.swift", "IslandPresentationModel.swift", "OnboardingStore.swift"]),
    .target(name: "NotchMedia", path: "Notch/Features/Music"),
    .target(name: "NotchFocus", path: "Notch/Features/Focus"),
    .target(name: "NotchCalendar", path: "Notch/Features/Calendar"),
    .target(name: "NotchShelf", path: "Notch/Features/Shelf"),
    .target(name: "NotchClipboard", path: "Notch/Features/Clipboard"),
    .target(name: "NotchDownloads", path: "Notch/Features/Downloads"),
    .target(name: "NotchNotifications", path: "Notch/Features/Notifications"),
    .target(name: "NotchTools", path: "Notch/Features/Tools"),
    .target(name: "NotchMixer", path: "Notch/Features/Mixer"),
    .target(name: "NotchWeather", path: "Notch/Features/Weather"),
    .target(name: "NotchWater", path: "Notch/Features/Water"),
    .testTarget(name: "NotchLogicTests", dependencies: ["NotchLogic", "NotchMedia", "NotchShelf", "NotchFocus", "NotchCalendar", "NotchClipboard", "NotchDownloads", "NotchNotifications", "NotchTools", "NotchMixer", "NotchWeather", "NotchWater"])
])
