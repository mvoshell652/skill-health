#!/bin/sh
# What built a binary, three lines: Xcode, Swift and the SDK. Scripts/build_plugin_bin.sh records it in
# plugin/bin/BUILT_WITH, and Scripts/verify_plugin_bin.sh prints this machine's beside it, so a
# failure on a different toolchain isn't mistaken for tampering.
xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'
echo
swift --version 2>&1 | head -1
echo "SDK $(xcrun --show-sdk-version 2>/dev/null)"
