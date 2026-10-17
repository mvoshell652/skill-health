#!/usr/bin/env bash
# Builds the plugin's command-line tool, plugin/bin/skill-health, from Sources/skill-health and SkillHealthCore:
# a universal (arm64 + x86_64) release build, stripped. The binary is committed, because Claude Code
# installs a plugin by copying its folder, with nothing built on the person's Mac.
#   Scripts/build_plugin_bin.sh
# Refuses to build from uncommitted source, so plugin/bin/BUILT_FROM names exactly what's inside;
# a test fails when the engine or the tool changed after that commit.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if ! git diff --quiet HEAD -- Sources/SkillHealthCore Sources/skill-health Package.swift; then
  echo "build_plugin_bin: commit the changes under Sources/SkillHealthCore, Sources/skill-health and Package.swift first." >&2
  exit 1
fi
swift build -c release --arch arm64 --arch x86_64 --product skill-health
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/skill-health
mkdir -p plugin/bin
cp "$BIN" plugin/bin/skill-health
strip -x plugin/bin/skill-health
# Linking signs ad hoc; stripping invalidates it, so sign again (arm64 runs only signed code).
codesign --force --sign - plugin/bin/skill-health
git rev-parse HEAD > plugin/bin/BUILT_FROM
Scripts/toolchain_description.sh > plugin/bin/BUILT_WITH
lipo -archs plugin/bin/skill-health
plugin/bin/skill-health version
ls -l plugin/bin/skill-health
