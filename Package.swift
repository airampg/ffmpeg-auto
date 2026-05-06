// swift-tools-version: 5.9
import PackageDescription

#if os(macOS)
let macOnlyProducts: [Product] = [
    .executable(name: "FFmpegAuto", targets: ["FFmpegAutoApp"]),
    .executable(name: "FFmpegAutoCoreTestRunner", targets: ["FFmpegAutoCoreTestRunner"]),
    .library(name: "FFmpegAutoCoreMac", targets: ["FFmpegAutoCoreMac"])
]
let macOnlyTargets: [Target] = [
    .target(
        name: "FFmpegAutoCoreMac",
        dependencies: ["FFmpegAutoCore"],
        path: "Sources/FFmpegAutoCoreMac"
    ),
    .executableTarget(
        name: "FFmpegAutoApp",
        dependencies: ["FFmpegAutoCore", "FFmpegAutoCoreMac"],
        path: "Sources/FFmpegAutoApp"
    ),
    .executableTarget(
        name: "FFmpegAutoCoreTestRunner",
        dependencies: ["FFmpegAutoCore", "FFmpegAutoCoreMac"],
        path: "Sources/FFmpegAutoCoreTestRunner"
    )
]
#else
let macOnlyProducts: [Product] = []
let macOnlyTargets: [Target] = []
#endif

let crossPlatformProducts: [Product] = [
    .executable(name: "FFmpegAutoServer", targets: ["FFmpegAutoServer"]),
    .library(name: "FFmpegAutoCore", targets: ["FFmpegAutoCore"])
]

let crossPlatformTargets: [Target] = [
    .target(
        name: "FFmpegAutoCore",
        path: "Sources/FFmpegAutoCore"
    ),
    .executableTarget(
        name: "FFmpegAutoServer",
        dependencies: [
            "FFmpegAutoCore",
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "MultipartKit", package: "multipart-kit")
        ],
        path: "Sources/FFmpegAutoServer"
    ),
    .testTarget(
        name: "FFmpegAutoServerTests",
        dependencies: [
            "FFmpegAutoServer",
            "FFmpegAutoCore"
        ],
        path: "Tests/FFmpegAutoServerTests"
    )
]

let package = Package(
    name: "FFmpegAuto",
    platforms: [
        .macOS(.v14)
    ],
    products: crossPlatformProducts + macOnlyProducts,
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
        .package(url: "https://github.com/vapor/multipart-kit.git", from: "4.7.0")
    ],
    targets: crossPlatformTargets + macOnlyTargets
)
