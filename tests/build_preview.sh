#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building Bubble Lab..."

# Detect SDK for Liquid Glass support
SDK_VERSION=$(xcrun --show-sdk-version 2>/dev/null || echo "0")
SDK_MAJOR=$(echo "$SDK_VERSION" | cut -d. -f1)
GLASS_FLAGS=""
if [ "$SDK_MAJOR" -ge 26 ] 2>/dev/null; then
    GLASS_FLAGS="-DLIQUID_GLASS"
fi

# Copy sources to temp dir, preview as main.swift
TMPDIR=$(mktemp -d)
cp Sources/Models.swift "$TMPDIR/"
cp Sources/Settings.swift "$TMPDIR/"
cp Sources/Helpers.swift "$TMPDIR/"
cp Sources/BubbleView.swift "$TMPDIR/"
cp Sources/ActivityBubbleView.swift "$TMPDIR/"
cp Sources/CPUBubbleView.swift "$TMPDIR/"
cp Sources/GlassBubble.swift "$TMPDIR/"
cp tests/KnobView.swift "$TMPDIR/"
cp tests/BubblePreviewApp.swift "$TMPDIR/main.swift"

swiftc \
    -O \
    ${GLASS_FLAGS} \
    "$TMPDIR"/*.swift \
    -o tests/BubblePreview \
    -framework Cocoa \
    -framework SwiftUI

rm -rf "$TMPDIR"

echo "==> Done. Run with: ./tests/BubblePreview"
