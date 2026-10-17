#!/usr/bin/env bash
# Checks that the committed plugin binary, plugin/bin/skill-health, is the code of this checkout's source.
#   Scripts/verify_plugin_bin.sh
# It first ties plugin/bin/BUILT_FROM to what you can read: the commit it names must be in this
# checkout's history and have the same Sources/SkillHealthCore, Sources/skill-health, Package.swift and
# build scripts as the working tree. Then it builds that commit in a scratch worktree with its own build
# script, and compares the code of the two binaries.
# A plain cmp or shasum of the two files differs whenever the build path's length does: each binary
# carries a UUID, and an ad hoc signature that covers it. So the signature and the UUID are removed from
# copies of both before comparing. A pass means the committed binary is the build of the source you have,
# not that the source is safe: read it. A different Xcode or Swift can change the code itself, which is
# why plugin/bin/BUILT_WITH records the toolchain; this prints it beside this machine's.
# The build runs the commit's build script and Package.swift with your privileges, as swift build does:
# use a clone you would build anyway. This script is part of the checkout it checks, so read it too.
# Needs a full clone, and about a minute or two. Changes nothing in this working tree.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
fail() { echo "verify_plugin_bin: $*" >&2; exit 1; }

COMMIT=$(tr -d '[:space:]' < plugin/bin/BUILT_FROM)
[[ $COMMIT =~ ^[0-9a-f]{40}$ ]] || fail "plugin/bin/BUILT_FROM doesn't hold a commit id."
git rev-parse --verify --quiet "${COMMIT}^{commit}" >/dev/null \
  || fail "the commit $COMMIT isn't in this clone. Use a full clone (git fetch --unshallow)."
git merge-base --is-ancestor "$COMMIT" HEAD \
  || fail "the commit $COMMIT isn't in this checkout's history (a squash or a rebase drops it)."
git diff --quiet HEAD -- plugin/bin || fail "plugin/bin has uncommitted changes; the committed binary is the one to check."
SOURCE=(Sources/SkillHealthCore Sources/skill-health Package.swift Scripts/build_plugin_bin.sh Scripts/toolchain_description.sh)
git diff --quiet "$COMMIT" -- "${SOURCE[@]}" \
  || fail "the source here differs from the source of $COMMIT, so the binary was built from something else. Don't rely on it."

echo "Binary built from $(git log -1 --format='%h %ad %s' --date=short "$COMMIT")"
RECORDED=$(cat plugin/bin/BUILT_WITH 2>/dev/null || echo "(not recorded)")
THIS=$(Scripts/toolchain_description.sh)
printf 'Built with (recorded):\n%s\nThis machine:\n%s\n' "$RECORDED" "$THIS"

WORK=$(mktemp -d)
cleanup() { git worktree remove --force "$WORK/source" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
git worktree add --detach "$WORK/source" "$COMMIT" >/dev/null 2>&1
(cd "$WORK/source" && Scripts/build_plugin_bin.sh >/dev/null)

# The code alone: no signature, no UUID.
normalized() { cp "$1" "$2"; codesign --remove-signature "$2" 2>/dev/null; strip -no_uuid "$2" 2>/dev/null; }
normalized plugin/bin/skill-health "$WORK/committed"
normalized "$WORK/source/plugin/bin/skill-health" "$WORK/rebuilt"

if cmp -s "$WORK/committed" "$WORK/rebuilt"; then
  echo "Same code: plugin/bin/skill-health is the build of the source in this checkout."
elif [ "$THIS" = "$RECORDED" ]; then
  fail "same toolchain, different code: plugin/bin/skill-health is not the build of the source in this checkout."
else
  fail "the code differs, and this machine's toolchain isn't the recorded one, so this is not evidence either way. Use the recorded Xcode, or open an issue."
fi
