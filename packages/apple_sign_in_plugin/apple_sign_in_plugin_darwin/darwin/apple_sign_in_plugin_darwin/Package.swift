// swift-tools-version: 5.9

// Copyright (c) 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import PackageDescription

let package = Package(
  name: "apple_sign_in_plugin_darwin",
  platforms: [
    .iOS("13.0"),
    .macOS("10.15"),
  ],
  products: [
    .library(name: "apple-sign-in-plugin-darwin", targets: ["apple_sign_in_plugin_darwin"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "apple_sign_in_plugin_darwin",
      dependencies: [],
      resources: [
        .process("Resources")
      ]
    )
  ]
)
