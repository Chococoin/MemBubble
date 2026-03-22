#!/bin/bash
set -euo pipefail

APP_NAME="MemBubble"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"

WIDGET_NAME="MemBubbleWidget"
WIDGET_BUNDLE="${WIDGET_NAME}.appex"
PLUGINS="${CONTENTS}/PlugIns"
WIDGET_CONTENTS="${PLUGINS}/${WIDGET_BUNDLE}/Contents"
WIDGET_MACOS="${WIDGET_CONTENTS}/MacOS"

# Optional: set SIGN_IDENTITY to enable code signing
# e.g. SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

# Detect macOS SDK version for Liquid Glass support
SDK_VERSION=$(xcrun --show-sdk-version 2>/dev/null || echo "0")
SDK_MAJOR=$(echo "$SDK_VERSION" | cut -d. -f1)
GLASS_FLAGS=""
if [ "$SDK_MAJOR" -ge 26 ] 2>/dev/null; then
    GLASS_FLAGS="-DLIQUID_GLASS"
    echo "==> Liquid Glass enabled (SDK ${SDK_VERSION})"
else
    echo "==> Legacy pearl mode (SDK ${SDK_VERSION}, need 26+ for Liquid Glass)"
fi

echo "==> Building ${APP_NAME}..."

# Clean previous build
rm -rf "${APP_BUNDLE}"

# Create .app bundle structure
mkdir -p "${MACOS}"

# Compile main app
swiftc \
    -O \
    -whole-module-optimization \
    ${GLASS_FLAGS} \
    Sources/*.swift \
    -o "${MACOS}/${APP_NAME}" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework UserNotifications \
    -framework ServiceManagement

# Copy main Info.plist and app icon
cp Info.plist "${CONTENTS}/Info.plist"
mkdir -p "${CONTENTS}/Resources"
cp AppIcon.icns "${CONTENTS}/Resources/AppIcon.icns"

echo "==> Main app built"

# Build widget extension
echo "==> Building ${WIDGET_NAME}..."

mkdir -p "${WIDGET_MACOS}"

swiftc \
    -O \
    -whole-module-optimization \
    -parse-as-library \
    WidgetExtension/MemBubbleWidget.swift \
    -o "${WIDGET_MACOS}/${WIDGET_NAME}" \
    -framework SwiftUI \
    -framework WidgetKit

# Copy widget Info.plist
cp WidgetExtension/Info.plist "${WIDGET_CONTENTS}/Info.plist"

echo "==> Widget extension built"

# Code signing (if identity is set)
if [ -n "${SIGN_IDENTITY}" ]; then
    echo "==> Signing with: ${SIGN_IDENTITY}"

    # Sign widget extension first (inside-out)
    codesign --force --sign "${SIGN_IDENTITY}" \
        --entitlements WidgetExtension/MemBubbleWidget.entitlements \
        --options runtime \
        "${PLUGINS}/${WIDGET_BUNDLE}"

    # Sign main app
    codesign --force --sign "${SIGN_IDENTITY}" \
        --entitlements MemBubble.entitlements \
        --options runtime \
        "${APP_BUNDLE}"

    echo "==> Signed successfully"

    # Notarization (if APPLE_ID and APP_PASSWORD are set)
    if [ -n "${APPLE_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ] && [ -n "${TEAM_ID:-}" ]; then
        echo "==> Submitting for notarization..."

        # Create zip for notarization
        ditto -c -k --keepParent "${APP_BUNDLE}" "${APP_NAME}.zip"

        xcrun notarytool submit "${APP_NAME}.zip" \
            --apple-id "${APPLE_ID}" \
            --password "${APP_PASSWORD}" \
            --team-id "${TEAM_ID}" \
            --wait

        # Staple the ticket
        xcrun stapler staple "${APP_BUNDLE}"

        rm -f "${APP_NAME}.zip"
        echo "==> Notarization complete"
    fi
else
    echo "==> Skipping code signing (set SIGN_IDENTITY to enable)"
fi

echo ""
echo "==> Built ${APP_BUNDLE} successfully"
echo ""
echo "Run with:  open ${APP_BUNDLE}"
echo "Or:        ./${MACOS}/${APP_NAME}"
echo ""
echo "Note: Widget requires code signing to function."
echo "  SIGN_IDENTITY=\"Developer ID Application: ...\" bash build.sh"
