// swift-tools-version: 6.0
//
//  The Swift foundation the suite's AUv3 plug-ins stand on.
//
//  Five targets, one per layer of PORTING.md §2, stacked in that order. The
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
        .library(name: "UI", targets: ["UI"]),
    ],
    targets: [
        // Primitives with nothing musical in them.
        .target(name: "Core", swiftSettings: mode),

        // Chords, scales, voice leading, progressions — the suite's own.
        .target(name: "Theory", dependencies: ["Core"], swiftSettings: mode),

        // What a take is made of, and how it is stored, judged, exported.
        .target(name: "Carrier", dependencies: ["Core", "Theory"], swiftSettings: mode),

        // Sibling of Shell, not above or below it: the kernel is handed notes
        // and the piano roll draws them, and neither may reach for the other.
        .target(name: "UI", dependencies: ["Core", "Theory", "Carrier"], swiftSettings: mode),

        // Shell is not here yet. It is the AU plumbing, and it carries three
        // things the other four do not: a header-only C++ kernel that needs a
        // C++ target and `.interoperabilityMode(.Cxx)`, an ObjC bridging header
        // that SwiftPM has no equivalent for, and — found while moving it —
        // `MelGenExtensionDSPKernel.hpp` including MelGen's own parameter
        // addresses, which is an app dependency the boundary check could never
        // see because everything under `Common/`, `DSP/` and `Parameters/` is
        // classified shell by its directory. That last one is a seam, and it
        // wants cutting before the kernel is shared rather than after.
    ]
)
