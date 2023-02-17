// swift-tools-version:5.7

import PackageDescription

let package = Package(
        name: "gonzales",
        targets: [
                .executableTarget(
                        name: "gonzales",
                        dependencies: [
                                "embree3",
                                "openImageIOBridge",
                                "ptexBridge",
                        ]
                ),
                .target(
                        name: "openImageIOBridge",
                        dependencies: ["openimageio"]
                ),
                .target(
                        name: "ptexBridge",
                        dependencies: ["ptex"]
                ),
                .systemLibrary(name: "embree3"),
                .systemLibrary(name: "openimageio", pkgConfig: "OpenImageIO"),
                .systemLibrary(name: "ptex", pkgConfig: "ptex"),
        ],
        cxxLanguageStandard: .cxx20
)
