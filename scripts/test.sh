#!/bin/sh
# `swift test` wrapper that also works with Command Line Tools only (no Xcode):
# CLT ships swift-testing outside the default search paths.
set -eu
cd "$(dirname "$0")/.."

DEV=/Library/Developer/CommandLineTools/Library/Developer
if [ -d "$DEV/Frameworks/Testing.framework" ] && ! xcode-select -p | grep -q Xcode.app; then
    exec swift test \
        -Xswiftc -F"$DEV/Frameworks" \
        -Xlinker -F"$DEV/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEV/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEV/usr/lib" "$@"
fi
exec swift test "$@"
