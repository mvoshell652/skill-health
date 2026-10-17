#!/usr/bin/env bash
# The Mac App Store package (spec M6): the same sandboxed build, signed for distribution with the
# app's provisioning profile embedded, wrapped in a signed installer package for upload.
#   MAS_APP_IDENTITY="Apple Distribution: Name (TEAMID)" \
#   MAS_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Name (TEAMID)" \
#   PROVISIONING_PROFILE=~/Downloads/SkillHealth_Mac_App_Store.provisionprofile TEAM_ID=TEAMID \
#   Scripts/package_mas.sh
# One-time setup, by the owner in the Apple Developer portal and App Store Connect: an App ID for
# com.mvoshell.skillhealth, an "Apple Distribution" and a "Mac Installer Distribution" certificate, a Mac
# App Store provisioning profile for that App ID, and the app record (name, which must be unique).
# Upload the .pkg with Transporter, then submit with docs/app-store/review-notes.md.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"
BUNDLE_ID=${BUNDLE_ID:-com.mvoshell.skillhealth}

missing=()
for var in MAS_APP_IDENTITY MAS_INSTALLER_IDENTITY PROVISIONING_PROFILE TEAM_ID; do
  [[ -n "${!var:-}" ]] || missing+=("$var")
done
if [[ -n "${MAS_APP_IDENTITY:-}" ]] && ! security find-identity -v -p codesigning | grep -qF "$MAS_APP_IDENTITY"; then
  missing+=("the identity \"$MAS_APP_IDENTITY\" in this Mac's keychain")
fi
if [[ -n "${MAS_INSTALLER_IDENTITY:-}" ]] && ! security find-identity -v | grep -qF "$MAS_INSTALLER_IDENTITY"; then
  missing+=("the identity \"$MAS_INSTALLER_IDENTITY\" in this Mac's keychain")
fi
if [[ -n "${PROVISIONING_PROFILE:-}" && ! -r "${PROVISIONING_PROFILE:-}" ]]; then
  missing+=("a readable provisioning profile at $PROVISIONING_PROFILE")
fi
if (( ${#missing[@]} )); then
  echo "package_mas: nothing was built. Missing:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

Scripts/package_app.sh release
APP="$ROOT/build/SkillHealth.app"
cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
# The App Store build's entitlements: the sandbox set plus the app and team identifiers the
# provisioning profile grants.
ENTITLEMENTS="$ROOT/build/SkillHealth-MAS.entitlements"
cp Resources/SkillHealth.entitlements "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENTITLEMENTS"
codesign --force --timestamp --entitlements "$ENTITLEMENTS" --sign "$MAS_APP_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"
PKG="$ROOT/build/SkillHealth-$MARKETING_VERSION.pkg"
productbuild --component "$APP" /Applications --sign "$MAS_INSTALLER_IDENTITY" "$PKG"
pkgutil --check-signature "$PKG"
echo "package_mas: $PKG, ready to upload with Transporter."
