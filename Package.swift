// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SkylineSDK",
    platforms: [
        .iOS(.v14) // Укажите минимальные версии платформ
    ], products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SkylineSDK",
            targets: ["SkylineSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/AppsFlyerSDK/AppsFlyerFramework-Static", from: "6.15.3"),
        .package(url: "https://github.com/facebook/facebook-ios-sdk", from: "17.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.10.0")),
        .package(url: "https://github.com/pushexpress/pushexpress-swift-sdk.git", .upToNextMajor(from: "1.0.1"))
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SkylineSDK",
            dependencies: [
                .product(name: "AppsFlyerLib-Static", package: "AppsFlyerFramework-Static"),
                .product(name: "FacebookCore", package: "facebook-ios-sdk"),
                .product(name: "FacebookAEM", package: "facebook-ios-sdk"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "SdkPushExpress", package: "pushexpress-swift-sdk")
            ]),
        .testTarget(
            name: "SkylineSDKTests",
            dependencies: ["SkylineSDK"]),
    ]
)
