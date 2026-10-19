// swift-tools-version:5.9
//
// Read-Only Local File Organizer
//
// No third-party dependencies: only Apple system frameworks are used, so the
// package resolves and builds fully offline.

import PackageDescription

let package = Package(
    name: "ReadOnlyOrganizer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ReadOnlyOrganizer", targets: ["ReadOnlyOrganizer"]),
        .library(name: "OrganizerCore", targets: ["OrganizerCore"]),
    ],
    targets: [
        // Scanning, classification, grouping, filtering. Foundation only; no UI.
        .target(name: "OrganizerCore"),
        // Native macOS UI (AppKit lifecycle + SwiftUI views).
        .executableTarget(name: "ReadOnlyOrganizer", dependencies: ["OrganizerCore"]),
        .testTarget(name: "OrganizerCoreTests", dependencies: ["OrganizerCore"]),
    ]
)
