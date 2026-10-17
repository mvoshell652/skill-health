#!/usr/bin/env bash
# Builds build/SkillHealth.app from the SwiftPM package. Adapted from the macos-spm-app-packaging
# skill's package_app.sh: Skill Health's executable product (SkillHealthApp) differs from its bundle name.
#   Scripts/package_app.sh [debug|release]
# Signs ad hoc with the sandbox entitlements unless APP_IDENTITY names a signing identity.
# Resources/SkillHealth.entitlements carries no comments (Apple asks for a plain plist), so here is why
# each key is there: app-sandbox, because the Mac App Store requires it and the direct download is
# the same build; user-selected.read-write and bookmarks.app-scope, for the .claude folder the
# person chooses once in the open panel; network.client, for comparing skills with GitHub (M3).
set -euo pipefail

CONF=${1:-debug}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"

APP_NAME=SkillHealth
# The name people see (menus, window titles, Quit), with its space.
DISPLAY_NAME="Skill Health"
PRODUCT=SkillHealthApp
BUNDLE_ID=${BUNDLE_ID:-com.mvoshell.skillhealth}
APP_IDENTITY=${APP_IDENTITY:-}

swift build -c "$CONF" --product "$PRODUCT"
BIN_DIR=$(swift build -c "$CONF" --show-bin-path)

APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$APP_NAME"
# The icon (Scripts/make_icon.swift draws it from a Phosphor glyph) and the privacy
# manifest: no tracking, no data collected, file timestamps and UserDefaults for Skill Health's own use.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
# The shared corrections snapshot: known wrong instructions, matched by exact file contents. One
# file for both: the plugin's command-line tool reads the same plugin/data/corrections.json.
cp plugin/data/corrections.json "$APP/Contents/Resources/corrections.json"
# The sample library ("Try with Sample Skills"), installed into the container on demand.
cp -R Resources/SampleClaude "$APP/Contents/Resources/SampleClaude"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Matthew Voshell</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <!-- HTTPS through URLSession only: exempt from export documentation. -->
    <key>ITSAppUsesNonExemptEncryption</key><false/>
</dict>
</plist>
PLIST

chmod -R u+w "$APP"
xattr -cr "$APP"
if [[ -n "$APP_IDENTITY" ]]; then
  codesign --force --timestamp --options runtime --entitlements Resources/SkillHealth.entitlements --sign "$APP_IDENTITY" "$APP"
else
  codesign --force --options runtime --entitlements Resources/SkillHealth.entitlements --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "$APP"
