// swift-tools-version: 6.0
import PackageDescription

/// One package, five library targets.
///
/// Five *packages* would be five manifests to keep in step for the same
/// compile-time layering. Targets give the same enforcement — `MetricsCore`
/// genuinely cannot import `NotchUI` — with one file to edit.
///
/// Tests live here rather than in an Xcode test bundle so CI can run
/// `swift test` without a scheme, and therefore without generating the project.
let package = Package(
    name: "NotchMetricsKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MetricsCore", targets: ["MetricsCore"]),
        .library(name: "MetricsAPI", targets: ["MetricsAPI"]),
        .library(name: "PluginRuntime", targets: ["PluginRuntime"]),
        .library(name: "Updater", targets: ["Updater"]),
        .library(name: "NotchUI", targets: ["NotchUI"]),
    ],
    targets: [
        // Models, paths, settings, keychain, layout maths. No UI, no network.
        .target(name: "MetricsCore"),
        .target(name: "MetricsAPI", dependencies: ["MetricsCore"]),
        .target(name: "PluginRuntime", dependencies: ["MetricsCore"]),
        .target(name: "Updater", dependencies: ["MetricsCore"]),
        .target(name: "NotchUI", dependencies: ["MetricsCore", "MetricsAPI", "PluginRuntime", "Updater"]),

        .testTarget(name: "MetricsCoreTests", dependencies: ["MetricsCore"]),
        .testTarget(name: "NotchUITests", dependencies: ["NotchUI"]),
        // Decodes the committed contracts/fixtures/*.json. This is what fails,
        // by name, when the Worker's wire shape drifts from these structs.
        //
        // It reads the fixtures through #filePath rather than through a
        // resource bundle, so there is one copy in the repository and it is
        // the one `pnpm contracts` regenerates. A copied bundle would let a
        // stale duplicate keep passing after the real contract moved.
        .testTarget(name: "ContractTests", dependencies: ["MetricsCore"]),
    ]
)
