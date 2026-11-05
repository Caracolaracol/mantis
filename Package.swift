// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingRecorder",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "MeetingRecorder", targets: ["MeetingRecorder"]),
        .library(name: "MeetingCore", targets: ["MeetingCore"])
    ],
    targets: [
        .binaryTarget(
            name: "CTranscribe",
            url: "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.4.1/TranscribeCpp.xcframework.zip",
            checksum: "fb5646e564036a6c49659e3efcf72eb567af20da31b8569045c9a08181d35126"
        ),
        .target(name: "MeetingCore", dependencies: ["CTranscribe"], linkerSettings: [
            .linkedLibrary("c++"), .linkedLibrary("z"),
            .linkedFramework("Accelerate"), .linkedFramework("Foundation"),
            .linkedFramework("Metal"), .linkedFramework("MetalKit")
        ]),
        .executableTarget(name: "MeetingRecorder", dependencies: ["MeetingCore"]),
        .testTarget(name: "MeetingCoreTests", dependencies: ["MeetingCore"]),
        .testTarget(name: "MeetingRecorderTests", dependencies: ["MeetingRecorder", "MeetingCore"])
    ]
)
