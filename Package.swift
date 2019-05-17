// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XcodeInstanceRun",

    dependencies: [
        .package(url: "https://github.com/Carthage/Commandant.git", from: "0.17.0"),
    ],
    targets: [
        .target(
            name: "XcodeInstanceRun",
            dependencies: ["Commandant"]),
    ]
)
