// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FFmpegAuto",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FFmpegAuto", targets: ["FFmpegAutoApp"]),
        .executable(name: "FFmpegAutoCoreTestRunner", targets: ["FFmpegAutoCoreTestRunner"]),
        .library(name: "FFmpegAutoCore", targets: ["FFmpegAutoCore"])
    ],
    targets: [
        .target(name: "FFmpegAutoCore"),
        .executableTarget(
            name: "FFmpegAutoApp",
            dependencies: ["FFmpegAutoCore"]
        ),
        .executableTarget(
            name: "FFmpegAutoCoreTestRunner",
            dependencies: ["FFmpegAutoCore"]
        )
    ]
)
