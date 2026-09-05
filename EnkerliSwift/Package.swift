// swift-tools-version: 6.0
//
//  The Swift foundation the suite's AUv3 plug-ins stand on.
//
//  Six targets: one per layer of PORTING.md §2, stacked in that order, plus the
//  C++ kernel the shell talks to. The
//  layering used to be a manifest in `Scripts/tests/foundation-boundary.py` and
//  a promise; here it is a dependency graph, so the compiler refuses an upward
//  reference instead of a Python script reporting one after the fact. The check
//  stays, because it is still the cheapest way to *propose* a reclassification
//  and see what it would cost — but it is no longer the only thing holding the
//  line.
//
//  Named after their music-suite counterparts where they have one: Theory is
//  the Swift `@enkerli/theory`, UI the Swift `@enkerli/ui`. Carrier has no
//  counterpart — it was invented here, and PORTING.md §2 argues it is the thing
//  most worth promoting back into the monorepo.
//

import PackageDescription

// Swift 5 language mode, matching `SWIFT_VERSION = 5.0` in MelGen.xcodeproj.
// The package exists to hold the same code the extension already builds; a
// different concurrency model would make it a different build of it, and the
// Swift 6 migration is its own piece of work with its own reasons.
let mode: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "enkerli-swift",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Theory", targets: ["Theory"]),
        .library(name: "Carrier", targets: ["Carrier"]),
        .library(name: "Kernel", targets: ["Kernel"]),
        .library(name: "Shell", targets: ["Shell"]),
        .library(name: "UI", targets: ["UI"]),
    ],
    targets: [
        // Primitives with nothing musical in them.
        .target(name: "Core", swiftSettings: mode),

        // Chords, scales, voice leading, progressions — the suite's own.
        .target(name: "Theory", dependencies: ["Core"], swiftSettings: mode),

        // What a take is made of, and how it is stored, judged, exported.
        .target(name: "Carrier", dependencies: ["Core", "Theory"], swiftSettings: mode),

        // Siblings, not stacked: the kernel is handed notes and the piano roll
        // draws them, and neither may name the other. SwiftPM says that by
        // omission — neither target depends on the other — which is exactly the
        // rule the build cannot enforce, and the reason
        // Scripts/tests/foundation-boundary.py is still worth running.
        .target(name: "UI", dependencies: ["Core", "Theory", "Carrier"], swiftSettings: mode),

        // The AU plumbing, and the only target that talks to C++.
        //
        // `Kernel` is the header-only DSP class. It is a separate target rather
        // than files in `Shell` because SwiftPM builds C++ and Swift as separate
        // units, and because the thing the render thread touches is worth being
        // able to point at.
        //
        // The header used to be `MelGenExtensionParameterAddresses.h`, which
        // made the kernel look as if it depended on the melody app — the one
        // seam the boundary check could never see, because everything under the
        // extension's `Common/`, `DSP/` and `Parameters/` was classified shell
        // by its directory rather than by what it named. The dependency was in
        // the name: play, direction and host sync are what a loop player has.
        .target(name: "Kernel"),
        .target(name: "Shell",
                dependencies: ["Core", "Theory", "Carrier", "Kernel"],
                swiftSettings: mode + [.interoperabilityMode(.Cxx)]),
    ]
)
