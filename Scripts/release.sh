#!/usr/bin/env bash
# The direct-download release (spec M6): Developer ID signed, notarized and stapled, then checked
# the way Gatekeeper will: spctl --assess and stapler validate must both pass.
#   APP_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=skill-health Scripts/release.sh
# One-time setup, by the owner (needs an Apple Developer Program membership):
#   1. Create a "Developer ID Application" certificate (Xcode > Settings > Accounts > Manage Certificates).
#   2. xcrun notarytool store-credentials skill-health --apple-id <email> --team-id <TEAMID>
# It is the same sandboxed build as the Mac App Store's: only the signature and packaging differ.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"
APP_IDENTITY=${APP_IDENTITY:-}
NOTARY_PROFILE=${NOTARY_PROFILE:-skill-health}

missing=()
if [[ -z "$APP_IDENTITY" ]]; then
  missing+=("APP_IDENTITY: set it to your \"Developer ID Application: …\" identity")
elif ! security find-identity -v -p codesigning | grep -qF "$APP_IDENTITY"; then
  missing+=("the signing identity \"$APP_IDENTITY\" isn't in this Mac's keychain")
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  missing+=("notarization credentials: run xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <email> --team-id <TEAMID>")
fi
if (( ${#missing[@]} )); then
  echo "release: nothing was built. Missing:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

APP_IDENTITY="$APP_IDENTITY" Scripts/package_app.sh release
APP="$ROOT/build/SkillHealth.app"
ZIP="$ROOT/build/SkillHealth-$MARKETING_VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=4 "$APP"
xcrun stapler validate "$APP"
# Re-zip the stapled app: the download carries its own ticket and opens offline.
rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
echo "release: $ZIP (signed, notarized, stapled; spctl and stapler both passed)"
