#!/usr/bin/env bash
# Compile et exécute les vérifications de logique pure (fichiers sans SwiftUI/UIKit).
# Fonctionne sur macOS (Xcode) comme sous Linux avec une toolchain Swift.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)/logic-checks"
swiftc -swift-version 5 -o "$out" \
  IGClean/Models.swift IGClean/SnapshotEngine.swift IGClean/Store.swift IGClean/HotInflux.swift \
  Tests/LogicChecks/main.swift
"$out"
