#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building Bubble Preview..."

# Copy preview as main.swift in a temp dir, compile with library sources
TMPDIR=$(mktemp -d)
cp Sources/Models.swift "$TMPDIR/"
cp Sources/Settings.swift "$TMPDIR/"
cp Sources/Helpers.swift "$TMPDIR/"
cp Sources/BubbleView.swift "$TMPDIR/"
cp Sources/ActivityBubbleView.swift "$TMPDIR/"
cp Sources/CPUBubbleView.swift "$TMPDIR/"
cp tests/BubblePreviewApp.swift "$TMPDIR/main.swift"

swiftc \
    -O \
    "$TMPDIR"/*.swift \
    -o tests/BubblePreview \
    -framework Cocoa \
    -framework SwiftUI

rm -rf "$TMPDIR"

echo "==> Done. Run with: ./tests/BubblePreview"
